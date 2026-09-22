defmodule BotArmyDashboardLiveview.HouseholdHUDPayloadTest do
  use ExUnit.Case, async: true

  alias BotArmyDashboardLiveview.HouseholdHUDPayload, as: HUD

  # The two replies exactly as the wife care bot sends them (JSON strings), so the
  # test cannot pass against a shape the bot does not produce. Both are wrapped in
  # the fleet envelope `{"ok": true, "data": {...}}` — the shape the live bot sends.
  # The un-enveloped shapes are accepted too, and pinned by a test below.
  defp panel_reply(overrides \\ %{}) do
    state =
      Map.merge(
        %{
          "timestamp" => "2026-09-22T10:00:00Z",
          "intent" => %{"mode" => "care"},
          "register" => %{"register" => "tender"},
          "pet" => %{
            "louiza" => "on",
            "abby" => "off",
            "state" => "pet",
            "behavior" => %{
              "register" => "warm",
              "interaction" => "close",
              "verbal" => "soft",
              "example" => "Good girl — you did that without being told."
            },
            "whisper" => "You belong to the house itself",
            "hibernating" => false,
            "energy" => 60,
            "warmth_daily_score" => 74,
            "tracker" => %{
              "bots" => [
                %{
                  "bot" => "fitness",
                  "name" => "Fitness",
                  "score" => 85,
                  "note" => "engaged heavily"
                },
                %{"bot" => "sre", "name" => "SRE", "score" => nil, "note" => "no readings yet"},
                %{
                  "bot" => "wife_care",
                  "name" => "Wife Care",
                  "score" => 100,
                  "note" => "primary caregiver — always engaged"
                }
              ],
              "overall" => 85
            }
          },
          "wishes" => %{
            "toggles" => [
              %{
                "key" => "proximity",
                "label" => "Proximity",
                "value" => "extended_contact",
                "option_label" => "extended contact",
                "pressure" => 2,
                "options" => [
                  %{"value" => "distant", "label" => "distant", "pressure" => 0},
                  %{"value" => "moderate_touch", "label" => "moderate touch", "pressure" => 1},
                  %{"value" => "extended_contact", "label" => "extended contact", "pressure" => 2}
                ]
              },
              %{
                "key" => "voice_presence",
                "label" => "Voice presence",
                "value" => "none",
                "option_label" => nil,
                "pressure" => 0,
                "options" => [
                  %{"value" => "none", "label" => "none", "pressure" => 0},
                  %{"value" => "balanced", "label" => "balanced", "pressure" => 1},
                  %{"value" => "full", "label" => "full", "pressure" => 2}
                ]
              }
            ],
            "mood_color" => "purple",
            "wish_text" => "I want to be told what to do today",
            "suggestion" => "a longer leash, perhaps"
          },
          "window" => %{"paused" => false, "paused_reason" => nil, "reply_count" => 3},
          "audit" => []
        },
        overrides
      )

    Jason.encode!(%{"ok" => true, "data" => state})
  end

  defp chorus_reply do
    Jason.encode!(%{
      "ok" => true,
      "data" => %{
        "chorus" => %{
          "categories" => [
            %{
              "key" => "focus",
              "glyph" => "🔵",
              "label" => "What should I focus on next?",
              "answering" => ["GTD", "Wife Care"],
              "mode" => "targeted"
            },
            %{
              "key" => "clarification",
              "glyph" => "💬",
              "label" => "Something else",
              "answering" => ["Wife Care"],
              "mode" => "targeted"
            }
          ],
          "tone" => %{"register" => "warm", "ownership?" => true, "state" => "pet"},
          "max_rating" => 5
        }
      }
    })
  end

  # The bot's envelope is the shape that matters: `{"ok": true, "data": {...}}`.
  # These two tests exist because the HUD was reading `body["state"]` and so found
  # nothing in a perfectly good answer — every section rendered as "not set" while
  # the wire was full of data. Fixtures that skip the envelope hide that.
  describe "the wire shapes the bot actually sends" do
    test "the envelope's data is the state" do
      state = %{"pet" => %{"state" => "pet", "energy_detail" => %{"band" => "strained"}}}
      hud = HUD.build(Jason.encode!(%{"ok" => true, "data" => state}), nil)

      assert hud.answering?
      assert hud.pet.state == "pet"
      assert hud.visual.key == :strain
    end

    test "an un-enveloped state is still accepted" do
      hud = HUD.build(Jason.encode!(%{"ok" => true, "state" => %{"pet" => %{}}}), nil)
      assert hud.answering?
    end

    test "the chorus arrives inside the same envelope" do
      reply =
        Jason.encode!(%{
          "ok" => true,
          "data" => %{
            "chorus" => %{"categories" => [%{"key" => "focus", "label" => "Focus"}]}
          }
        })

      hud = HUD.build(nil, reply)

      assert hud.answering?
      assert [%{label: "Focus"}] = hud.chorus.categories
    end
  end

  describe "the ladder" do
    test "is structure, so it is present even when nothing answered" do
      hud = HUD.build(nil, nil)
      names = Enum.map(hud.hierarchy, & &1.name)

      assert names == [
               "Goddess Louiza",
               "Wife Care Bot",
               "Bot Army",
               "Visual Novel Interface",
               "Abby — Maid / Servant"
             ]
    end

    test "marks the bots as mechanism and Louiza as authority, not as parties" do
      hud = HUD.build(nil, nil)
      roles = Map.new(hud.hierarchy, &{&1.name, &1.role})

      assert roles["Goddess Louiza"] == :authority
      assert roles["Wife Care Bot"] == :mechanism
      assert roles["Bot Army"] == :mechanism
      assert roles["Visual Novel Interface"] == :surface
      assert roles["Abby — Maid / Servant"] == :self
      assert hud.tier == "Abby — Maid / Servant"
    end
  end

  describe "answering" do
    test "true when the panel replied" do
      assert HUD.build(panel_reply(), nil).answering?
    end

    test "false when nothing answered" do
      refute HUD.build(nil, nil).answering?
    end

    test "false for a bare success notice, which carries no state" do
      refute HUD.build(Jason.encode!(%{"ok" => true}), nil).answering?
    end

    test "false when the bot refused" do
      refute HUD.build(Jason.encode!(%{"ok" => false, "error" => "no token"}), nil).answering?
    end

    test "survives a reply that is not JSON at all" do
      hud = HUD.build("not json", 42)

      refute hud.answering?
      assert hud.containment.source == :unreported
      assert hud.pet.bots == []
    end
  end

  describe "containment" do
    test "reads the window rather than asserting a value" do
      open = HUD.build(panel_reply(), nil).containment

      assert open.state == :open
      assert open.display == "OPEN"
      assert open.source == :reported
    end

    test "paused shows her own reason" do
      reply =
        panel_reply(%{"window" => %{"paused" => true, "paused_reason" => "not today"}})

      hud = HUD.build(reply, nil)

      assert hud.containment.state == :paused
      assert hud.containment.display == "PAUSED"
      assert hud.containment.detail == "not today"
    end

    test "paused with no reason says so instead of inventing one" do
      hud = HUD.build(panel_reply(%{"window" => %{"paused" => true}}), nil)

      assert hud.containment.detail == "no reason given"
    end

    test "no reply is not the same as open" do
      hud = HUD.build(nil, nil)

      assert hud.containment.state == :unreported
      assert hud.containment.display == "not reported"
    end

    test "an explicit false is open; a missing window is open too (the bot's default)" do
      assert HUD.build(panel_reply(%{"window" => %{}}), nil).containment.state == :open
    end
  end

  describe "maid level" do
    test "is unreported until a board sets it — never a fabricated 65%" do
      hud = HUD.build(panel_reply(), nil)

      assert hud.maid_level.value == nil
      assert hud.maid_level.display == "not set"
      assert hud.maid_level.source == :unreported
    end

    test "a number set on the board is reported" do
      hud = HUD.build(panel_reply(%{"maid_level" => 65}), nil)

      assert hud.maid_level.value == 65
      assert hud.maid_level.display == "65%"
      assert hud.maid_level.source == :reported
    end

    test "zero is a value, not an absence" do
      hud = HUD.build(panel_reply(%{"maid_level" => 0}), nil)

      assert hud.maid_level.value == 0
      assert hud.maid_level.display == "0%"
      assert hud.maid_level.source == :reported
    end
  end

  describe "the pet layer" do
    test "reads the two toggles the bot sends, as flat keys" do
      pet = HUD.build(panel_reply(), nil).pet
      toggles = Map.new(pet.toggles, &{&1.key, &1})

      assert toggles["louiza"].on?
      assert toggles["louiza"].label == "Mistress layer"
      refute toggles["abby"].on?
      assert toggles["abby"].display == "off"
      assert pet.state == "pet"
    end

    test "reads the register and its example from behavior" do
      pet = HUD.build(panel_reply(), nil).pet

      assert pet.register == "warm"
      assert pet.example == "Good girl — you did that without being told."
      assert pet.whisper == "You belong to the house itself"
    end

    test "warmth is taken from warmth_daily_score" do
      warmth = HUD.build(panel_reply(), nil).pet.warmth

      assert warmth.value == 74
      assert warmth.display == "74%"
      assert warmth.source == :reported
    end

    test "a day nobody measured reads 'no readings yet', not 0%" do
      reply = panel_reply(%{"pet" => %{"warmth_daily_score" => nil, "state" => "neutral"}})
      warmth = HUD.build(reply, nil).pet.warmth

      assert warmth.value == nil
      assert warmth.display == "no readings yet"
      assert warmth.source == :unreported
      refute warmth.display =~ "0%"
    end

    test "a measured zero IS a zero" do
      reply = panel_reply(%{"pet" => %{"warmth_daily_score" => 0}})
      warmth = HUD.build(reply, nil).pet.warmth

      assert warmth.value == 0
      assert warmth.display == "0%"
      assert warmth.source == :reported
    end

    test "the per-bot tracker carries a bot with no readings as no readings" do
      bots = HUD.build(panel_reply(), nil).pet.bots
      sre = Enum.find(bots, &(&1.name == "SRE"))

      assert sre.score == nil
      assert sre.display == "no readings"
      assert sre.source == :unreported
    end

    test "the wife care pin arrives with its own number and note" do
      bots = HUD.build(panel_reply(), nil).pet.bots
      wife_care = Enum.find(bots, &(&1.name == "Wife Care"))

      assert wife_care.score == 100
      assert wife_care.display == "100%"
      assert wife_care.note =~ "primary caregiver"
    end

    test "the overall line is present and distinct from the pin" do
      hud = HUD.build(panel_reply(), nil)

      assert hud.pet.overall.name == "All bots"
      assert hud.pet.overall.score == 85
      assert hud.pet.overall.display == "85%"
    end

    test "an overall of nil is not the same as an overall of zero" do
      reply = panel_reply(%{"pet" => %{"tracker" => %{"bots" => [], "overall" => nil}}})
      overall = HUD.build(reply, nil).pet.overall

      assert overall.score == nil
      assert overall.display == "no readings"
    end

    test "no panel reply gives the toggles as unreported rather than off" do
      pet = HUD.build(nil, nil).pet

      assert Enum.all?(pet.toggles, &(&1.source == :unreported))
      assert Enum.all?(pet.toggles, &(&1.display == "not set"))
      refute Enum.any?(pet.toggles, & &1.on?)
    end
  end

  describe "mood and wishes" do
    test "the mood colour is a glyph and a meaning, never a bare code" do
      mood = HUD.build(panel_reply(), nil).mood

      assert mood.color == "purple"
      assert mood.glyph == "🟣"
      assert mood.meaning == "dreaming, suggestion, drift"
      assert mood.source == :reported
    end

    test "an unset colour is unreported, not red" do
      reply = panel_reply(%{"wishes" => %{"mood_color" => nil}})
      mood = HUD.build(reply, nil).mood

      assert mood.color == nil
      assert mood.source == :unreported
    end

    test "only wishes away from their baseline are 'in play'" do
      wishes = HUD.build(panel_reply(), nil).wishes

      assert Enum.map(wishes.in_play, & &1.key) == ["proximity"]
    end

    test "the wishes are ordered by the doc's list, not by arrival" do
      wishes = HUD.build(panel_reply(), nil).wishes

      assert Enum.map(wishes.all, & &1.key) == ["voice_presence", "proximity"]
    end

    test "the option's own label is used so the surface need not know the vocabulary" do
      proximity = HUD.build(panel_reply(), nil).wishes.in_play |> hd()

      assert proximity.display == "extended contact"
    end

    test "her own words do not cross into the HUD" do
      hud = HUD.build(panel_reply(), chorus_reply())
      rendered = inspect(hud)

      refute rendered =~ "I want to be told what to do today"
      assert hud.wishes.suggestion == "a longer leash, perhaps"
    end

    test "no wishes read is unreported, and says which case it is" do
      wishes = HUD.build(nil, nil).wishes

      assert wishes.source == :unreported
      assert wishes.in_play == []
    end

    test "every toggle at baseline is reported-but-empty, not unreported" do
      reply =
        panel_reply(%{
          "wishes" => %{
            "toggles" => [
              %{
                "key" => "proximity",
                "label" => "Proximity",
                "value" => "distant",
                "option_label" => "distant",
                "pressure" => 0,
                "options" => [
                  %{"value" => "distant", "label" => "distant", "pressure" => 0},
                  %{"value" => "moderate_touch", "label" => "moderate touch", "pressure" => 1}
                ]
              }
            ]
          }
        })

      wishes = HUD.build(reply, nil).wishes

      assert wishes.source == :reported
      assert wishes.in_play == []
    end

    test "the baseline is the bot's first option, not a list the surface keeps" do
      # The bot's own definition of rest is the first option; a surface that
      # hardcoded "moderate_touch" (or any value) would be a second source of
      # truth for the vocabulary and would drift.
      reply =
        panel_reply(%{
          "wishes" => %{
            "toggles" => [
              %{
                "key" => "stillness",
                "label" => "Stillness",
                "value" => "balanced",
                "option_label" => "balanced",
                "pressure" => 1,
                "options" => [
                  %{"value" => "balanced", "label" => "balanced", "pressure" => 1},
                  %{"value" => "high_stillness", "label" => "high stillness", "pressure" => 2}
                ]
              }
            ]
          }
        })

      wish = HUD.build(reply, nil).wishes.all |> hd()

      assert wish.baseline == "balanced"
      refute wish.active?
    end
  end

  describe "the chorus" do
    test "lists the questions with who answers each" do
      chorus = HUD.build(panel_reply(), chorus_reply()).chorus

      assert Enum.map(chorus.categories, & &1.label) == [
               "What should I focus on next?",
               "Something else"
             ]

      assert hd(chorus.categories).answering_label == "GTD + Wife Care"
      assert hd(chorus.categories).glyph == "🔵"
    end

    test "carries the register and the rating ceiling" do
      chorus = HUD.build(panel_reply(), chorus_reply()).chorus

      assert chorus.tone["register"] == "warm"
      assert chorus.tone["ownership?"] == true
      assert chorus.max_rating == 5
    end

    test "a quiet chorus is unreported, not an empty list pretending to be an answer" do
      chorus = HUD.build(panel_reply(), nil).chorus

      assert chorus.categories == []
      assert chorus.source == :unreported
      assert chorus.tone["register"] == nil
    end

    test "the chorus alone counts as answering" do
      assert HUD.build(nil, chorus_reply()).answering?
    end
  end

  describe "the exit" do
    test "is always available, in both states" do
      assert HUD.build(panel_reply(), nil).exit.available?
      assert HUD.build(nil, nil).exit.available?
    end

    test "offers the way out when nothing is paused" do
      assert HUD.build(panel_reply(), nil).exit.label == "Stop everything"
    end

    test "offers the way back while paused, matching the containment card" do
      hud = HUD.build(panel_reply(%{"window" => %{"paused" => true}}), nil)

      assert hud.containment.display == "PAUSED"
      assert hud.exit.label == "Resume what was paused"
    end

    test "defaults to the way out when the panel has said nothing" do
      assert HUD.build(nil, nil).exit.label == "Stop everything"
    end

    test "points at the control panel, because that is where the gate lives" do
      assert HUD.build(nil, nil).exit.detail == "on the control panel"
    end
  end

  describe "the gauge helper" do
    test "formats integers without a decimal" do
      assert HUD.gauge(65) == %{value: 65, display: "65%", source: :reported}
    end

    test "formats floats that are whole numbers without a decimal" do
      assert HUD.gauge(85.0).display == "85%"
    end

    test "keeps a real fraction" do
      assert HUD.gauge(85.7).display == "85.7%"
    end

    test "an absent value is unreported and displays as 'not set'" do
      assert HUD.gauge(nil) == %{value: nil, display: "not set", source: :unreported}
    end
  end

  describe "the visual state (the doc's background system)" do
    test "nothing firing is neutral, and says so rather than inventing a mood" do
      visual = HUD.build(panel_reply(), nil).visual

      assert visual.key == :neutral
      assert visual.reason == nil
      assert visual.source == :unreported
    end

    test "the cage outranks everything — the doc puts containment first" do
      visual =
        visual_for(%{
          "outfit" => %{
            "active" => true,
            "components" => %{"cage" => "dog_cage", "plug" => "hollow"}
          }
        })

      assert visual.key == :restricted
      assert visual.reason == "the cage is on"
    end

    test "one punishment trigger is Punishment Mode" do
      visual =
        visual_for(%{"outfit" => %{"active" => true, "components" => %{"plug" => "hollow"}}})

      assert visual.key == :punishment
      assert visual.reason == "the plug is on"
    end

    test "several punishment triggers at once is Intensity Peak" do
      visual =
        visual_for(%{
          "outfit" => %{
            "active" => true,
            "humiliation_level" => 9,
            "components" => %{"plug" => "hollow"}
          }
        })

      assert visual.key == :intensity_peak
      assert visual.reason == "2 punishment triggers at once"
    end

    test "recognition needs the pet layer on AND a strong week" do
      visual = visual_for(%{"pet" => %{"abby" => "on", "tracker" => %{"overall" => 95}}})

      assert visual.key == :recognition
    end

    test "a strong week with the pet layer off is not recognition" do
      visual = visual_for(%{"pet" => %{"abby" => "off", "tracker" => %{"overall" => 95}}})

      assert visual.key == :neutral
    end

    test "low energy is strain, and the reason quotes the number" do
      visual = visual_for(%{"pet" => %{"energy" => 42}})

      assert visual.key == :strain
      assert visual.reason =~ "42"
    end

    test "punishment outranks strain, as the doc's chain does" do
      visual =
        visual_for(%{
          "pet" => %{"energy" => 42},
          "outfit" => %{"active" => true, "components" => %{"plug" => "hollow"}}
        })

      assert visual.key == :punishment
    end

    test "a grounded mood colour is the tender override" do
      visual = visual_for(%{"wishes" => %{"mood_color" => "brown"}})

      assert visual.key == :tender
    end

    test "the tender override cannot outrank strain" do
      visual = visual_for(%{"pet" => %{"energy" => 30}, "wishes" => %{"mood_color" => "brown"}})

      assert visual.key == :strain
    end

    test "an unreported energy is never read as strain" do
      visual = visual_for(%{"pet" => %{"energy" => nil}})

      assert visual.key == :neutral
      assert visual.energy.source == :unreported
      assert visual.energy.display == "not set"
    end

    test "energy is carried as its own reading" do
      assert visual_for(%{"pet" => %{"energy" => 81}}).energy.display == "81%"
    end

    test "the pet layer changes the transitions, not the state" do
      off = visual_for(%{"pet" => %{"abby" => "off"}})
      on = visual_for(%{"pet" => %{"abby" => "on"}})

      refute off.pet_on?
      assert off.transition_ms == 0

      assert on.pet_on?
      assert on.transition_ms == 500
    end

    test "a check-in word is strain, and the reason quotes her word rather than a number" do
      visual =
        visual_for(%{
          "pet" => %{
            "energy" => nil,
            "energy_detail" => %{
              "level" => nil,
              "label" => "low",
              "display" => "Low (checkin)",
              "band" => "strained",
              "source" => "checkin",
              "readings" => 1
            }
          }
        })

      assert visual.key == :strain
      assert visual.reason =~ "Low (checkin)"
      assert visual.energy.display == "Low (checkin)"
      assert visual.energy.band == "strained"
      assert visual.energy.producer == "checkin"
      # No meter: a bar for a word would be a percentage nobody measured.
      assert visual.energy.source == :unreported
      assert visual.energy.value == nil
    end

    test "a reported band decides strain, so no threshold is re-derived here" do
      grounded = energy_detail(%{"band" => "grounded", "level" => 20, "display" => "20% (sre)"})
      strained = energy_detail(%{"band" => "strained", "level" => 90, "display" => "90% (sre)"})

      assert visual_for(%{"pet" => grounded}).key == :neutral
      assert visual_for(%{"pet" => strained}).key == :strain
    end

    test "a recovery out of strain is the doc's Restoration State" do
      visual =
        visual_for(%{
          "pet" =>
            energy_detail(%{
              "band" => "grounded",
              "label" => "medium",
              "display" => "Medium (checkin)",
              "previous_band" => "strained",
              "restoring" => true
            })
        })

      assert visual.key == :restoration
      assert visual.reason =~ "climbing out"
      assert visual.energy.restoring
    end

    test "strain outranks a recovery, as the doc's chain does" do
      visual =
        visual_for(%{
          "pet" =>
            energy_detail(%{
              "band" => "strained",
              "label" => "low",
              "display" => "Low (checkin)",
              "restoring" => true
            })
        })

      assert visual.key == :strain
    end

    test "a capable day brightens whatever state is already in play" do
      visual =
        visual_for(%{
          "pet" => energy_detail(%{"band" => "capable", "level" => 95, "display" => "95%"}),
          "wishes" => %{"toggles" => []}
        })

      assert Enum.map(visual.modulations, & &1.key) == ["bright"]
    end

    test "strain stays visible underneath a stronger state" do
      visual =
        visual_for(%{
          "pet" =>
            energy_detail(%{"band" => "strained", "label" => "low", "display" => "Low (checkin)"}),
          "outfit" => %{"active" => true, "components" => %{"plug" => "hollow"}}
        })

      assert visual.key == :punishment
      assert "grain" in Enum.map(visual.modulations, & &1.key)
    end

    test "a grounded day adds no visual weight, and an unmeasured day adds none either" do
      grounded =
        visual_for(%{
          "pet" => energy_detail(%{"band" => "grounded", "level" => 70, "display" => "70%"}),
          "wishes" => %{"toggles" => []}
        })

      assert grounded.modulations == []

      assert visual_for(%{"pet" => %{"energy" => nil}, "wishes" => %{"toggles" => []}}).modulations ==
               []
    end

    test "a bot that predates the feed still reads on the raw percentage" do
      visual = visual_for(%{"pet" => %{"energy" => 30}})

      assert visual.key == :strain
      assert visual.energy.display == "30%"
      assert visual.energy.band == nil
      assert visual.energy.readings == 0
    end

    test "each documented wish modulates the background, and only those" do
      keys =
        visual_for(%{
          "wishes" => %{
            "toggles" => [
              %{"key" => "sensitivity", "value" => "warm_sensitivity"},
              %{"key" => "proximity", "value" => "extended_contact"},
              %{"key" => "stillness", "value" => "high_stillness"},
              %{"key" => "sensory_deprivation", "value" => "maximum"},
              %{"key" => "toys", "value" => "novelty"}
            ]
          }
        }).modulations
        |> Enum.map(& &1.key)

      assert keys == ["glow", "pulse", "hush", "deep"]
    end

    test "a wish at its baseline modulates nothing" do
      assert visual_for(%{
               "wishes" => %{"toggles" => [%{"key" => "proximity", "value" => "distant"}]}
             }).modulations ==
               []
    end

    test "the states this panel cannot reach are named with what is missing" do
      underivable = HUD.build(panel_reply(), nil).visual.underivable

      keys = Enum.map(underivable, & &1.key)

      assert :reward_pulse in keys
      assert :bodily in keys

      # Restoration is no longer on this list: the energy feed made it derivable
      # from two readings, so it is a state the panel can actually reach.
      refute :restoration in keys

      assert Enum.all?(underivable, fn s -> is_binary(s.missing) and s.missing != "" end)
    end

    test "a dead panel yields the neutral state rather than an exception" do
      visual = HUD.build(nil, nil).visual

      assert visual.key == :neutral
      assert visual.energy.source == :unreported
    end

    test "garbage does not take the visual state down" do
      for body <- ["not json", "%{}", "[]", 7, {:ok, :weird}] do
        assert HUD.build(body, nil).visual.key == :neutral
      end
    end
  end

  defp energy_detail(detail) do
    Map.put(%{"energy" => nil}, "energy_detail", detail)
  end

  defp visual_for(overrides) do
    HUD.build(panel_reply(overrides), nil).visual
  end
end
