defmodule BotArmyDashboardLiveview.HouseholdHUDPayload do
  @moduledoc """
  The household HUD: what the control panel actually reports, as a view model.

  This module shapes two replies into one screen. It does not invent a value to
  fill a slot — the rule from the control surface contract is that **failure is
  not an empty state and an unreported number is not a zero**. Every section
  carries where its number came from, so a surface can say "not reported yet"
  without a lie and without a blank.

  ## The sections, and where each one is allowed to read

  | Section | Source | When it is missing |
  |---|---|---|
  | `hierarchy` | the doc's ladder (fixed) | never — it is structure, not data |
  | `containment` | the window (`paused`, `paused_reason`) | `:unreported` |
  | `maid_level` | the panel's `maid_level`, once a board sets it | `:unreported` |
  | `hypnosis` | the panel's `hypnosis`, once a board sets it | `:unreported` |
  | `pet` | `pet_layer` read (toggles, `warmth_daily_score`, tracker) | `:unreported` per column |
  | `mood`, `wishes` | the `wishes` read | `:unreported` |
  | `chorus` | `wife_care.chorus.categories` | `:unreported` |

  Her own words are not here either. `wishes.wish_text` is hers and stays on the
  panel she typed it into; the HUD shows which *wishes are in play*, not what she
  wrote. The same allowlist discipline as `Chorus.prompt_context/2`, for the same
  reason.

  The doc's `MAID LEVEL 65%` and `CONTAINMENT ACTIVE` arrive as **structure**
  with the real value beside them, never as a hardcoded 65: a fabricated meter is
  the most expensive kind of decoration, because it looks like a measurement.
  """

  @ladder [
    %{name: "Goddess Louiza", role: :authority, note: "the house is hers"},
    %{name: "Wife Care Bot", role: :mechanism, note: "holds the centre, speaks for the house"},
    %{name: "Bot Army", role: :mechanism, note: "carries out the work"},
    %{name: "Visual Novel Interface", role: :surface, note: "this screen"},
    %{name: "Abby — Maid / Servant", role: :self, note: "the one being held"}
  ]

  @mood_glyphs %{
    "red" => "🔴",
    "blue" => "🔵",
    "purple" => "🟣",
    "brown" => "🟤"
  }

  @mood_meanings %{
    "red" => "heat, hunger, wanting",
    "blue" => "quiet, cool, reflective",
    "purple" => "dreaming, suggestion, drift",
    "brown" => "grounded, held, steady"
  }

  @pet_labels %{
    "louiza" => "Mistress layer",
    "abby" => "Her own choice"
  }

  @wish_order [
    "voice_presence",
    "proximity",
    "display_intensity",
    "toys",
    "sensitivity",
    "stillness",
    "sensory_deprivation"
  ]

  # The doc's "Visual State Background System": the interface's texture follows
  # where she actually is, so the space itself acknowledges the day without her
  # having to name it. Each state carries the doc's own colours and emotional
  # texture, because those words are the feature — not decoration.
  @visual_states %{
    restricted: %{
      name: "Restricted State",
      style: "indigo/black gradient, corner framing lines",
      texture: "restricted energy — the visual space compresses to match"
    },
    intensity_peak: %{
      name: "Intensity Peak State",
      style: "deep amber / burnt orange gradient with texture overlay",
      texture: "intense but not chaotic — grounded in discipline's warmth"
    },
    punishment: %{
      name: "Punishment Mode",
      style: "deep crimson / charcoal wash with grain",
      texture: "weight present without heaviness — readable, and it reads as effort"
    },
    reward_pulse: %{
      name: "Reward Pulse State",
      style: "soft golden light filter, floating particles",
      texture: "celebration without noise — she can see it materially"
    },
    recognition: %{
      name: "Recognition Mode",
      style: "pastel sky blue or soft peach with a gentle bloom",
      texture: "warmth felt in the space itself, like being held"
    },
    strain: %{
      name: "Strain Detection State",
      style: "edges darken slightly, a little grain added",
      texture: "she can see the system noticing strain before she says it"
    },
    restoration: %{
      name: "Restoration State",
      style: "soft green tint fading in",
      texture: "rest is present; permission to soften"
    },
    tender: %{
      name: "Tender Operations State",
      style: "cream/white base, watercolour edges",
      texture: "visual permission to rest even while working"
    },
    bodily: %{
      name: "Bodily Awareness Mode",
      style: "soft purple-grey wash, muted light",
      texture: "gentle restriction — present, not harsh"
    },
    neutral: %{
      name: "Neutral (normal operations)",
      style: "matte base, minimal gradient",
      texture: "tasks and notifications stay the focus"
    }
  }

  # The doc's wish → background table. A wish with no documented background
  # response simply does not modulate anything.
  @wish_effects %{
    "warm_sensitivity" => %{
      key: "glow",
      label: "Sensory sensitivity high",
      effect: "soft glow at the edges — amplified perception"
    },
    "extended_contact" => %{
      key: "pulse",
      label: "Proximity mode",
      effect: "a slow heartbeat pulse at the centre — presence without a task"
    },
    "high_stillness" => %{
      key: "hush",
      label: "Silence required",
      effect: "dimmed with a muted texture — a visual hush"
    },
    "maximum" => %{
      key: "deep",
      label: "Maximum intensity",
      effect: "deeper base, sharper edges — contrast heightened"
    }
  }

  # States this panel cannot currently reach, and what is missing. Saying so in
  # place beats a silent absence — the doc's own priority table calls these
  # lower-priority, and a state that can never fire should be visible as such.
  @underivable %{
    reward_pulse:
      "needs today's satisfaction rating and completion, which the panel read does not carry",
    bodily: "needs a diaper-confinement signal; the bot has no diaper tracking yet"
  }

  @doc """
  Build the HUD view model from the two replies.

  Each argument may be a decoded map, a raw JSON body, or anything else — a reply
  that is missing or unreadable becomes `:unreported`, never an exception and
  never a zero.
  """
  @spec build(term(), term()) :: map()
  def build(panel_body, chorus_body) do
    panel = fetch(panel_body, "state")
    chorus = fetch(chorus_body, "chorus")

    %{
      answering?: is_map(panel) or is_map(chorus),
      hierarchy: ladder(),
      tier: "Abby — Maid / Servant",
      containment: containment(panel),
      maid_level: gauge(Map.get(panel || %{}, "maid_level")),
      hypnosis: gauge(Map.get(panel || %{}, "hypnosis")),
      pet: pet_section(panel),
      mood: mood_section(panel),
      wishes: wishes_section(panel),
      visual: visual_section(panel),
      chorus: chorus_section(chorus),
      exit: exit_section(panel)
    }
  end

  @doc "The doc's ladder — structure, so it is always present."
  @spec ladder() :: [map()]
  def ladder, do: @ladder

  @doc """
  One numbered reading, with where it came from.

  `:reported` means a surface or a bot set it. `:unreported` means nobody has —
  the display reads "not set" and no meter is drawn, because an empty meter reads
  as zero.
  """
  @spec gauge(number() | nil, atom()) :: %{
          value: number() | nil,
          display: String.t(),
          source: atom()
        }
  def gauge(value, unit \\ :percent) do
    if is_number(value) do
      %{value: value, display: "#{trim(value)}#{unit_suffix(unit)}", source: :reported}
    else
      unreported_gauge()
    end
  end

  defp unreported_gauge, do: %{value: nil, display: "not set", source: :unreported}

  @doc """
  Containment, read from the window rather than asserted.

  Paused or open, with the reason she gave — the doc's `CONTAINMENT ACTIVE` with
  a real state behind it.
  """
  @spec containment(map() | nil) :: map()
  def containment(panel) when is_map(panel) do
    window = Map.get(panel, "window") || %{}

    if Map.get(window, "paused") == true do
      %{
        state: :paused,
        display: "PAUSED",
        detail: Map.get(window, "paused_reason") || "no reason given",
        source: :reported
      }
    else
      %{state: :open, display: "OPEN", detail: "nothing is being withheld", source: :reported}
    end
  end

  def containment(_panel) do
    %{
      state: :unreported,
      display: "not reported",
      detail: "the panel did not answer",
      source: :unreported
    }
  end

  @doc """
  The pet layer: the two toggles, today's warmth, and the weekly per-bot tracker.

  Warmth is measured, never inferred. A day nobody measured is `nil` and reads
  "no readings yet"; `0` would be an accusation dressed as a measurement.
  """
  @spec pet_section(map() | nil) :: map()
  def pet_section(panel) when is_map(panel) do
    pet = Map.get(panel, "pet") || %{}
    tracker = Map.get(pet, "tracker") || %{}
    behavior = Map.get(pet, "behavior") || %{}

    %{
      toggles: [toggle_row("louiza", pet["louiza"]), toggle_row("abby", pet["abby"])],
      state: pet["state"] || "unknown",
      register: behavior["register"] || "unknown",
      example: behavior["example"],
      whisper: pet["whisper"],
      warmth: warmth(%{"score" => pet["warmth_daily_score"]}),
      bots: bot_rows(tracker["bots"]),
      overall: bot_row(%{"name" => "All bots", "score" => tracker["overall"]}),
      source: if(map_size(pet) > 0, do: :reported, else: :unreported)
    }
  end

  def pet_section(_panel) do
    %{
      toggles: [toggle_row("louiza", nil), toggle_row("abby", nil)],
      state: "unknown",
      register: "unknown",
      example: nil,
      whisper: nil,
      warmth: warmth(%{}),
      bots: [],
      overall: bot_row(%{}),
      source: :unreported
    }
  end

  @doc "Today's warmth: a number when it was measured, `nil` when it was not."
  @spec warmth(map()) :: map()
  def warmth(reading) when is_map(reading) do
    case Map.get(reading, "score") do
      score when is_number(score) ->
        %{
          value: score,
          display: "#{trim(score)}%",
          label: Map.get(reading, "label") || "today",
          source: :reported
        }

      _ ->
        %{value: nil, display: "no readings yet", label: "today", source: :unreported}
    end
  end

  @doc "The doc's mood colours: a glyph and what the colour means."
  @spec mood_section(map() | nil) :: map()
  def mood_section(panel) when is_map(panel) do
    color = panel |> Map.get("wishes", %{}) |> Map.get("mood_color")

    case color do
      c when is_binary(c) and is_map_key(@mood_glyphs, c) ->
        %{color: c, glyph: @mood_glyphs[c], meaning: @mood_meanings[c], source: :reported}

      _ ->
        %{color: nil, glyph: "⚪", meaning: "no colour set today", source: :unreported}
    end
  end

  def mood_section(_panel) do
    %{color: nil, glyph: "⚪", meaning: "no colour set today", source: :unreported}
  end

  @doc """
  Which wishes are in play — never what she wrote.

  `wish_text` is hers and stays on the panel she typed it into.
  """
  @spec wishes_section(map() | nil) :: map()
  def wishes_section(panel) when is_map(panel) do
    wishes = Map.get(panel, "wishes") || %{}

    rows =
      wishes
      |> Map.get("toggles", [])
      |> Enum.filter(&is_map/1)
      |> Enum.map(&wish_row/1)
      |> Enum.sort_by(& &1.position)

    %{
      in_play: Enum.filter(rows, & &1.active?),
      all: rows,
      mood_color: wishes["mood_color"],
      suggestion: wishes["suggestion"],
      source: if(rows == [], do: :unreported, else: :reported)
    }
  end

  def wishes_section(_panel) do
    %{in_play: [], all: [], mood_color: nil, suggestion: nil, source: :unreported}
  end

  @doc """
  The interface's texture: which state the day is in, and why it won.

  The doc's own transition logic is a priority chain, so this is too — containment
  above punishment, punishment above strain, and the tender override last among
  the shifts, so a gentle day can be set over a punishing one. Every state reports
  the signal that matched (`reason`) or says plainly that nothing shifted it, and
  the states whose triggers this panel does not carry are listed rather than
  quietly unreachable.
  """
  @spec visual_section(map() | nil) :: map()
  def visual_section(panel) when is_map(panel) do
    pet = Map.get(panel, "pet") || %{}
    {key, reason} = visual_key(panel)
    state = Map.fetch!(@visual_states, key)

    %{
      key: key,
      name: state.name,
      style: state.style,
      texture: state.texture,
      reason: reason,
      source: if(reason, do: :reported, else: :unreported),
      pet_on?: Map.get(pet, "abby") == "on",
      transition_ms: if(Map.get(pet, "abby") == "on", do: 500, else: 0),
      energy: energy_view(pet),
      modulations: modulations(panel, key),
      underivable: underivable()
    }
  end

  def visual_section(_panel), do: visual_section(%{})

  @doc "The doc's states this panel cannot currently reach, with what is missing."
  @spec underivable() :: [map()]
  def underivable do
    for {key, missing} <- @underivable do
      %{key: key, name: Map.fetch!(@visual_states, key).name, missing: missing}
    end
  end

  # The priority chain, strongest and most specific first — the doc's own
  # transition logic. A reason travels with the state so the screen can say why
  # the texture changed.
  defp visual_key(panel) do
    outfit = Map.get(panel, "outfit") || %{}
    components = Map.get(outfit, "components") || %{}
    pet = Map.get(panel, "pet") || %{}
    cage? = wearing?(components["cage"])

    # "Full penalty day" is *multiple* punishment triggers. Counting them beats
    # guessing a single threshold, and each one carries its own reason.
    load = punishment_load(panel, outfit, components)

    cond do
      cage? ->
        {:restricted, "the cage is on"}

      length(load) >= 2 ->
        {:intensity_peak, "#{length(load)} punishment triggers at once"}

      length(load) == 1 ->
        {:punishment, hd(load)}

      recognition?(pet) ->
        {:recognition, "the pet layer is on and the week's warmth is high"}

      strained?(pet) ->
        {:strain, "energy reads #{energy_view(pet).display}"}

      restoring?(pet) ->
        {:restoration, "energy is climbing out of strain (#{energy_view(pet).display})"}

      tender?(panel) ->
        {:tender, "gentleness is set for today"}

      true ->
        {:neutral, nil}
    end
  end

  @high_humiliation 7

  # The reasons a punishment is in play today, each one phrased for the screen.
  defp punishment_load(panel, outfit, components) do
    [
      wearing?(components["plug"]) && "the plug is on",
      high_humiliation?(outfit) && "humiliation is set high (#{outfit["humiliation_level"]})",
      critical_hygiene?(panel) && "a hygiene item is critically overdue"
    ]
    |> Enum.filter(&is_binary/1)
  end

  defp high_humiliation?(outfit) do
    level = Map.get(outfit, "humiliation_level")
    is_number(level) and level >= @high_humiliation
  end

  defp critical_hygiene?(panel) do
    panel |> Map.get("hygiene", %{}) |> Map.get("critical_overdue") == true
  end

  # The doc: recognition when the pet layer is ON and the week is strong. The
  # week's number is the bot's own tracker, not a threshold invented here.
  defp recognition?(pet) do
    tracker = Map.get(pet, "tracker") || %{}
    score = tracker["overall"] || pet["warmth_daily_score"]

    Map.get(pet, "abby") == "on" and is_number(score) and score >= 90
  end

  # Strain is read from the band the bot derived, and only falls back to the raw
  # percentage for a bot that predates the feed. The band knows about her
  # check-in words, which have no number to compare.
  defp strained?(pet) do
    energy = energy_view(pet)

    cond do
      energy.band == "strained" -> true
      is_binary(energy.band) -> false
      is_number(energy.value) -> energy.value < 60
      true -> false
    end
  end

  # The doc's "Energy Recovery Active", which the bot derives from two readings
  # (or from her own `Recovering` mood). Derived, so it is present only when the
  # reading really moved — never a mood someone has to remember to set.
  defp restoring?(pet), do: energy_view(pet).restoring == true

  # The doc's "Louiza toggles Gentleness": on this wire that is the grounded
  # mood colour or a day set to stillness.
  defp tender?(panel) do
    mood = panel |> Map.get("wishes", %{}) |> Map.get("mood_color")
    mood == "brown" or wish_value(panel, "stillness") == "high_stillness"
  end

  # The reading as the bot reported it, with the meter only when there is a
  # number to fill it: a check-in word reads "Low (checkin)" and draws no bar,
  # because a bar for the word would be a percentage nobody measured.
  defp energy_view(pet) do
    detail = Map.get(pet, "energy_detail")
    detail = if is_map(detail), do: detail, else: %{}

    level = Map.get(detail, "level") || Map.get(pet, "energy")
    gauge = gauge(level)

    gauge
    |> Map.merge(%{
      display: Map.get(detail, "display") || gauge.display,
      band: Map.get(detail, "band"),
      band_text: Map.get(detail, "band_text") || band_text(nil),
      producer: Map.get(detail, "source"),
      mood: Map.get(detail, "mood"),
      restoring: Map.get(detail, "restoring") == true,
      readings: Map.get(detail, "readings") || 0,
      recorded_at: Map.get(detail, "recorded_at")
    })
  end

  @doc "The doc's description of an energy band, for a caller that has only the name."
  @spec band_text(String.t() | nil) :: String.t()
  def band_text("capable"), do: "clean, bright, airy textures — capability, visible"
  def band_text("grounded"), do: "neutral grounded state — no visual weight added"

  def band_text("strained"),
    do: "edges darken and grain is added — the system noticing strain"

  def band_text(_band), do: "no reading yet, so no visual weight is added"

  defp modulations(panel, key) do
    wish_effects(panel) ++ energy_modulations(panel, key)
  end

  defp wish_effects(panel) do
    for toggle <- panel |> Map.get("wishes", %{}) |> Map.get("toggles", []),
        is_map(toggle),
        effect = Map.get(@wish_effects, toggle["value"]),
        effect do
      effect
    end
  end

  # The doc's band responses that are not whole states: a capable day brightens
  # whatever state is already in play, and strain stays visible underneath a
  # stronger state (the plug can be on during a strained day, and she should
  # still see the system noticing both).
  defp energy_modulations(panel, key) do
    band = energy_view(Map.get(panel, "pet") || %{}).band

    cond do
      band == "capable" ->
        [
          %{
            key: "bright",
            label: "Energy above 80%",
            effect: "clean, bright, airy textures — capability is visible"
          }
        ]

      band == "strained" and key != :strain ->
        [
          %{
            key: "grain",
            label: "Energy below 60%",
            effect: "edges darken and grain is added under it — strain still showing"
          }
        ]

      true ->
        []
    end
  end

  # The payload writes a component as `to_string(value)` or `nil`, so anything
  # present and not a negative spelling is worn.
  defp wearing?(nil), do: false
  defp wearing?(value) when is_binary(value), do: value not in ["", "false", "off", "none", "nil"]
  defp wearing?(value), do: value not in [false, :off, :none, nil]

  defp wish_value(panel, key) do
    panel
    |> Map.get("wishes", %{})
    |> Map.get("toggles", [])
    |> Enum.find_value(fn
      %{"key" => ^key, "value" => value} -> value
      _ -> nil
    end)
  end

  @doc """
  The chorus panel: the questions she can ask, who answers each, and the voice the
  house is answering in today.
  """
  @spec chorus_section(map() | nil) :: map()
  def chorus_section(chorus) when is_map(chorus) do
    %{
      categories: Enum.map(Map.get(chorus, "categories") || [], &chorus_row/1),
      tone: tone_row(Map.get(chorus, "tone")),
      score: nil,
      summary: nil,
      max_rating: Map.get(chorus, "max_rating") || 5,
      source: :reported
    }
  end

  def chorus_section(_chorus) do
    %{
      categories: [],
      tone: tone_row(nil),
      score: nil,
      summary: nil,
      max_rating: 5,
      source: :unreported
    }
  end

  @doc """
  The exit, which is the one control that is never hidden.

  Its label comes from the window's own state, so the button and the containment
  card cannot disagree: while paused it offers the way back, otherwise it offers
  the way out. The press itself lives on the control panel, where the pause gate
  and the audit log are.
  """
  @spec exit_section(map() | nil) :: map()
  def exit_section(panel) do
    %{
      available?: true,
      label: exit_label(containment(panel).state),
      hint: "always available",
      detail: "on the control panel",
      source: :reported
    }
  end

  # Stop is the safe direction: while paused the exit offers the way back, and
  # when the panel has said nothing the exit still offers the way out rather than
  # guessing that something is being withheld.
  defp exit_label(:paused), do: "Resume what was paused"
  defp exit_label(_other), do: "Stop everything"

  # --- rows ---------------------------------------------------------------

  defp toggle_row(key, value) do
    %{
      key: key,
      label: @pet_labels[key],
      value: value,
      on?: value == "on",
      display: label_for(value),
      source: if(value in ["on", "off"], do: :reported, else: :unreported)
    }
  end

  # The bot sends each toggle with its own label, the chosen option's label, and
  # the full option list, so the surface never has to know the vocabulary — not
  # even which value is the baseline (the bot's first option is).
  defp wish_row(row) do
    key = row["key"]
    value = row["value"]
    options = row["options"] || []
    baseline = baseline_value(options)

    %{
      key: key,
      position: wish_position(key),
      label: row["label"] || key || "wish",
      value: value,
      options: options,
      baseline: baseline,
      pressure: row["pressure"],
      active?: active_wish?(value, baseline, row["pressure"]),
      display: row["option_label"] || label_for(value)
    }
  end

  # The first option is the bot's own definition of rest (see `Wishes.default/0`),
  # so nothing here needs a hand-written list of baseline values to drift from.
  defp baseline_value([%{"value" => value} | _rest]), do: value
  defp baseline_value([first | _rest]) when is_map(first), do: Map.get(first, "value")
  defp baseline_value(_options), do: nil

  # Without an option list, fall back to the pressure the bot reported: a wish that
  # raises nothing is not in play.
  defp active_wish?(nil, _baseline, _pressure), do: false
  defp active_wish?(value, baseline, _pressure) when is_binary(baseline), do: value != baseline
  defp active_wish?(_value, _baseline, pressure) when is_number(pressure), do: pressure > 0
  defp active_wish?(_value, _baseline, _pressure), do: false

  # The doc's wishes list in one order; sorting by it keeps the panel stable
  # between refreshes.
  defp wish_position(key), do: Enum.find_index(@wish_order, &(&1 == key)) || 99

  defp bot_rows(bots) when is_list(bots) do
    bots |> Enum.filter(&is_map/1) |> Enum.map(&bot_row/1)
  end

  defp bot_rows(_bots), do: []

  # One bot's number, or the honest absence of one. The Wife Care pin (100%, the
  # primary caregiver) arrives the same way as any other reading.
  defp bot_row(bot) when is_map(bot) do
    score = Map.get(bot, "score")

    %{
      name: Map.get(bot, "name") || Map.get(bot, "bot") || "unknown",
      score: score,
      note: Map.get(bot, "note"),
      display: if(is_number(score), do: "#{trim(score)}%", else: "no readings"),
      source: if(is_number(score), do: :reported, else: :unreported)
    }
  end

  defp chorus_row(row) when is_map(row) do
    answering = Map.get(row, "answering") || []

    %{
      key: Map.get(row, "key"),
      glyph: Map.get(row, "glyph") || "💬",
      label: Map.get(row, "label") || "…",
      answering: answering,
      answering_label: Enum.join(answering, " + "),
      mode: Map.get(row, "mode") || "targeted"
    }
  end

  defp chorus_row(_row), do: chorus_row(%{})

  # The tone travels as data with string keys (JSON), so it is normalised here
  # rather than read twice in a template.
  defp tone_row(tone) when is_map(tone) do
    %{
      "register" => Map.get(tone, "register") || Map.get(tone, :register),
      "example" => Map.get(tone, "example") || Map.get(tone, :example),
      "ownership?" => Map.get(tone, "ownership?") || Map.get(tone, :ownership?),
      "state" => Map.get(tone, "state") || Map.get(tone, :state)
    }
  end

  defp tone_row(_tone) do
    %{"register" => nil, "example" => nil, "ownership?" => nil, "state" => nil}
  end

  # --- plumbing -----------------------------------------------------------

  # A reply may arrive decoded, as a body, or not at all. Anything unreadable is
  # `nil`, which every section renders as unreported.
  defp fetch(body, key) when is_map(body), do: unwrap(body, key)

  defp fetch(body, key) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> fetch(decoded, key)
      _ -> nil
    end
  end

  defp fetch(_body, _key), do: nil

  # The panel's own read answers `{"ok": true, "data": {...}}`; a direct read of
  # the store may answer with the state itself. Both are accepted, and neither a
  # failed reply nor a bare success notice is mistaken for a state with data.
  defp unwrap(%{"ok" => false}, _key), do: nil

  # The fleet envelope carries the state inside `data`. Reading `body["state"]`
  # finds nothing here, and that failure is quiet: every section renders as "not
  # set" against a bot that answered perfectly. This is the shape the live bot
  # sends, so it is the shape the tests use.
  defp unwrap(%{"data" => data}, key) when is_map(data) do
    case Map.get(data, key) do
      value when is_map(value) -> value
      _ -> data
    end
  end

  defp unwrap(body, key) when is_map(body) do
    case Map.get(body, key) do
      value when is_map(value) -> value
      _ -> if Map.get(body, "ok") == true, do: nil, else: body
    end
  end

  defp label_for(nil), do: "not set"
  defp label_for("none"), do: "none"
  defp label_for(value) when is_binary(value), do: String.replace(value, "_", " ")
  defp label_for(value) when is_atom(value), do: value |> Atom.to_string() |> label_for()
  defp label_for(value), do: inspect(value)

  defp unit_suffix(:percent), do: "%"
  defp unit_suffix(_unit), do: ""

  defp trim(value) when is_integer(value), do: Integer.to_string(value)

  defp trim(value) when is_float(value) do
    if value == Float.round(value, 0),
      do: Integer.to_string(trunc(value)),
      else: Float.to_string(value)
  end
end
