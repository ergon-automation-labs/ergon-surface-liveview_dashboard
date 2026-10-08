defmodule BotArmyDashboardLiveview.SelfReport do
  @moduledoc """
  The maid's own numbers: two screens, one card each, hers to tap.

  Two things are reported here and nowhere else: **yearning** (the goddess-focus
  indicator, `/yearning-phone`) and a **body reading** (how much of something the
  body is showing, `/body-phone`). Both are hers to say. Neither is measured, and
  neither is inferred by these screens: a tap is a report, and the panel says so
  in the row it writes.

  ## Why its own screens, and not the household HUD

  The household HUD reads the house — what is holding, how hard the board is set,
  what the pet layer is doing, where the exit is. It is a *view*. Putting the
  input ladders on it made the reading screen and the reporting screen the same
  screen, which is how a report becomes something a person does *for* a screen
  rather than about herself. So each ladder is its own page, reached from the
  phone navigation bar the way fitness and gtd are, and the HUD keeps only the
  two *reads*.

  They are deliberately **not** placed inside a `phx-hook="TouchCarousel"`
  container (as `/timer-phone` is): that hook pushes a `tap` event for any touch
  that does not move, and on a page like that the event drives something else. A
  tap on a point must mean one thing only. `test/yearning_phone_test.exs` pins
  that these screens carry no carousel hook at all.

  ## The rules a report obeys

    * **A tap the screen cannot parse is refused here**, before anything is sent.
      Only the six points of the house scale exist; anything else is not a report.
    * **A channel the card is not drawing is refused here too** — the bot would
      refuse it as well, but sending a write this screen knows is wrong is not
      something to delegate.
    * **Every write is followed by a full re-read**, and the sentence afterwards
      reports the *read*, never the write. "The bot took 4" and "the reading is
      4" are different claims, and only the second one is this screen's to make.
    * **A dead broker is not a refusal.** Nothing was recorded, and the sentence
      says so rather than implying the bot said no.

  ## The seam a host page uses

  A page is three lines of boilerplate (`start/1` on mount, `info/2` for the
  read, `click/3` for a tap) plus `<.card which={...} report={...} tap={...} />`.
  The rules above live here rather than in each page, so a third report would not
  have to re-learn them.
  """

  use Phoenix.Component

  require Logger

  alias BotArmyDashboardLiveview.BotRead
  alias BotArmyDashboardLiveview.Broker
  alias BotArmyDashboardLiveview.HouseholdHUDPayload, as: HUD

  @panel_subject "wife_care.control_panel.state"
  @yearning_subject "wife_care.control_panel.record_goddess_proximity"
  @body_subject "wife_care.control_panel.record_body_reading"
  @escape_subject "wife_care.control_panel.record_cage_escape"
  @undo_escape_subject "wife_care.control_panel.undo_cage_escape"
  @flip_escape_subject "wife_care.control_panel.set_cage_escape_period"
  @request_timeout 3_000

  @doc "The subject yearning is reported on."
  def yearning_subject, do: @yearning_subject

  @doc "The subject a body reading is reported on."
  def body_subject, do: @body_subject

  # ── the seam a host page uses ───────────────────────────────────────────────

  @doc """
  Start the one read these screens need, and open with nothing on record.

  The read is the panel state — the same reply the household HUD reads — because
  both cards show the house's own reading of each number beside the ladder.
  """
  @spec start(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def start(socket) do
    BotRead.async(self(), :self_report, @panel_subject, %{}, timeout: @request_timeout)
    assign(socket, report: nil, tap: nil)
  end

  @doc """
  Take the read, and reconcile it with any tap that is waiting on it.

  This runs for the opening read and for the re-read after a write; they are the
  same read, and settling twice is idempotent.
  """
  @spec info(Phoenix.LiveView.Socket.t(), map() | nil) :: Phoenix.LiveView.Socket.t()
  def info(socket, answer) do
    report = HUD.build(answer, nil)

    assign(socket, report: report, tap: settle(socket.assigns.tap, report))
  end

  @doc """
  One tap, from the event to the sentence under the card.

  `where` is `:yearning` or `{:body, kind}`. A refusal this screen owns never
  reaches the bot; a sent write is always followed by a re-read, so the sentence
  reports the reading rather than the acknowledgement.
  """
  @spec click(Phoenix.LiveView.Socket.t(), :yearning | {:body, String.t()}, term()) ::
          Phoenix.LiveView.Socket.t()
  def click(socket, where, raw) do
    case plan(where, raw, socket.assigns[:report]) do
      {:refused, tap} ->
        assign(socket, tap: tap)

      {:send, subject, payload, tap} ->
        case write(subject, payload) do
          {:ok, _data} -> socket |> assign(tap: tap) |> reread()
          {:error, sentence} -> assign(socket, tap: Map.put(tap, :error, sentence))
        end
    end
  end

  defp reread(socket) do
    BotRead.async(self(), :self_report, @panel_subject, %{}, timeout: @request_timeout)
    socket
  end

  @doc """
  One press on the cage card.

  `action` is `:record` (one escape came off, now), `:undo` (take the newest
  back), or `:flip` (`params` naming an event id and the side to move it to).

  There is nothing here for this screen to refuse the way `click/3` refuses a
  point off the scale: the only inputs are the ones this card drew, and every one
  of them is already a fact she is reporting. A press with the id missing is a
  stale page rather than a bad tap, and it says so instead of sending a request
  the bot could only answer with a refusal.
  """
  @spec escape(Phoenix.LiveView.Socket.t(), :record | :undo | :flip, map()) ::
          Phoenix.LiveView.Socket.t()
  def escape(socket, :record, _params) do
    send_escape(socket, @escape_subject, %{}, :record)
  end

  def escape(socket, :undo, _params) do
    send_escape(socket, @undo_escape_subject, %{}, :undo)
  end

  def escape(socket, :flip, %{"id" => id, "period" => period}) do
    send_escape(socket, @flip_escape_subject, %{"id" => id, "period" => period}, :flip)
  end

  def escape(socket, :flip, _params) do
    assign(socket,
      tap: %{
        where: :cage_escapes,
        error: "those buttons are from an older page — reload and try again"
      }
    )
  end

  defp send_escape(socket, subject, payload, intent) do
    case write(subject, payload) do
      {:ok, _data} -> socket |> assign(tap: %{where: :cage_escapes, intent: intent}) |> reread()
      {:error, sentence} -> assign(socket, tap: %{where: :cage_escapes, error: sentence})
    end
  end

  # ── deciding what a tap means ───────────────────────────────────────────────

  @doc """
  Turn a tap into either a write or a refusal this screen owns.

  `spec` is `:yearning` or `{:body, kind}`. Returns `{:send, subject, payload,
  tap}` when the tap is worth sending, and `{:refused, tap}` when it is not.
  """
  @spec plan(:yearning | {:body, String.t()}, term(), map() | nil) ::
          {:send, String.t(), map(), map()} | {:refused, map()}
  def plan(:yearning, raw, report) do
    case parse_point(raw) do
      {:ok, level} ->
        payload = %{"goddess_proximity_seeking" => level}
        {:send, @yearning_subject, payload, yearning_tap(level, report)}

      :error ->
        {:refused, bad_point(:yearning)}
    end
  end

  def plan({:body, kind}, raw, report) do
    if channel?(report, kind) do
      case parse_point(raw) do
        {:ok, level} ->
          payload = %{"kind" => kind, "level" => level, "source" => "reported"}
          {:send, @body_subject, payload, body_tap(kind, level, report)}

        :error ->
          {:refused, bad_point(:body)}
      end
    else
      {:refused, bad_channel(kind)}
    end
  end

  @doc """
  Send one report. The body is the payload itself — there is nothing to check
  here that the bot does not check harder, and a second opinion about a range is
  a second place for it to be wrong.
  """
  @spec write(String.t(), map()) :: {:ok, map()} | {:error, String.t()}
  def write(subject, payload) do
    case Broker.request(subject, Jason.encode!(payload), timeout: @request_timeout) do
      {:ok, %{body: body}} -> decode_write(body)
      other -> {:error, write_trouble(other)}
    end
  rescue
    error -> {:error, write_trouble({:raised, error})}
  catch
    kind, reason -> {:error, write_trouble({kind, reason})}
  end

  @doc """
  Reconcile a tap with a fresh read.

  `confirmed?` is not "the write returned ok" — it is "the reading that came
  back is the one that was sent, and it is today's". Anything less says what the
  bot actually reports, which is the only thing this screen knows.
  """
  @spec settle(map() | nil, map() | nil) :: map() | nil
  def settle(nil, _report), do: nil

  # The escape card's sentence is made from the read that came back, never from
  # the write that went out: "counted" is not a number, and the number is the only
  # thing this card is for. A refusal has no read to wait for.
  def settle(%{where: :cage_escapes, error: _} = tap, _report), do: tap

  def settle(%{where: :cage_escapes, intent: intent} = tap, report) do
    Map.put(tap, :sentence, escape_line(intent, escape_block(report)))
  end

  def settle(%{level: level} = tap, report) do
    case reading_of(report, tap) do
      %{today?: true, level: ^level} -> Map.put(tap, :confirmed?, true)
      %{display: display} -> tap |> Map.put(:confirmed?, false) |> Map.put(:reading, display)
      _other -> tap
    end
  end

  def settle(tap, _report), do: tap

  @doc "The sentence under the card that owns this tap."
  def line(%{error: error}), do: error
  def line(%{sentence: sentence}), do: sentence

  # Between the press and the read that follows it there is no number yet, so the
  # line says what was done and not what it counted. It must not guess a count: a
  # count that flickers from wrong to right is a count nobody trusts.
  def line(%{where: :cage_escapes, intent: intent}),
    do: "#{escape_verb(intent)} — reading it back…"

  def line(%{confirmed?: true} = tap),
    do: "logged — the reading that came back is #{tap.what} today."

  def line(%{reading: reading} = tap),
    do: "the bot took #{tap.what}, but its reading shows #{reading} — showing what it reports."

  def line(tap), do: "logged #{tap.what} — reading it back…"

  @doc "An error line is not a reading; it must not be styled like one."
  def class(%{error: _}), do: "unreported"
  def class(_tap), do: "dim"

  # ── one card ────────────────────────────────────────────────────────────────

  @doc """
  One report card, with its own styles and its own result line.

  `which` is `:yearning` or `:body`; each screen draws its own card only. `report`
  is the built panel payload (`HouseholdHUDPayload.build/2`); while it is `nil`
  the card says the read has not landed rather than drawing an empty ladder.
  """
  attr(:which, :atom, required: true)
  attr(:report, :map, default: nil)
  attr(:tap, :map, default: nil)

  def card(%{which: which} = assigns) when which in [:yearning, :body, :cage_escapes] do
    ~H"""
    <style>
      .report-card { background: #131a3a; border: 1px solid #222c56; border-radius: 10px; padding: 14px 16px; margin: 0 auto 14px; max-width: 900px; }
      .report-card .card-title { font-size: 12px; letter-spacing: 1.5px; text-transform: uppercase; color: #6f7db2; margin-bottom: 10px; }
      .report-card .row { display: flex; justify-content: space-between; gap: 10px; }
      .report-card .dim { color: #8b93b0; }
      .report-card .unreported { color: #b98b3f; }
      .report-card .chip { display: inline-block; padding: 2px 8px; border-radius: 999px; border: 1px solid #2c3766; color: #a9b4e0; font-size: 12px; }
      .report-card .chip.on { color: #0a0e27; background: #ffd166; border-color: #ffb545; font-weight: 600; }
      .tap-row { display: flex; gap: 6px; margin: 8px 0 4px; }
      .tap-row .tap { flex: 1; min-height: 44px; font: inherit; font-size: 15px; color: #a9b4e0; background: #10162f; border: 1px solid #222c56; border-radius: 8px; cursor: pointer; }
      .tap-row .tap.on { color: #0a0e27; background: #ffd166; border-color: #ffb545; font-weight: 600; }
      .tap-legend { color: #6f7db2; font-size: 12px; margin: 2px 0 0; }
    </style>

    <%= if @report do %>
      <%= case @which do %>
        <% :yearning -> %><%= yearning_card(assigns) %>
        <% :body -> %><%= body_card(assigns) %>
        <% :cage_escapes -> %><%= cage_card(assigns) %>
      <% end %>
    <% else %>
      <div class="report-card">
        <div class="card-title"><%= card_title(@which) %></div>
        <p class="unreported">nothing from the panel yet — the card appears when the read lands</p>
      </div>
    <% end %>
    """
  end

  defp yearning_card(assigns) do
    ~H"""
    <div class="report-card">
      <div class="card-title">Yearning — the goddess-focus indicator  ·  tap a point to log it</div>
      <%= if @report.yearning.active? do %>
        <div class="row">
          <span class="chip on">Yearning Active</span>
          <span class="dim"><%= @report.yearning.display %></span>
        </div>
      <% else %>
        <div class="row">
          <span class="chip">Yearning</span>
          <span class="dim">no reading today</span>
        </div>
      <% end %>
      <p class="dim" style="margin-top:6px; font-size:12px;"><%= @report.yearning.line %></p>
      <div class="tap-row">
        <%= for point <- @report.scale do %>
          <button
            type="button"
            phx-click="record_yearning"
            phx-value-level={point.level}
            phx-disable-with="…"
            title={"#{point.level} — #{point.word}"}
            aria-label={"log #{point.level}, #{point.word}"}
            class={"tap#{if @report.yearning.today? and @report.yearning.level == point.level, do: " on", else: ""}"}
          ><%= point.level %></button>
        <% end %>
      </div>
      <p class="tap-legend"><%= Enum.map_join(@report.scale, " · ", &"#{&1.level} #{&1.word}") %></p>
      <.result tap={@tap} where={:yearning} />
      <p class="dim" style="margin-top:6px; font-size:12px;">
        This one is hers to say and is never measured: the house records what she reports, at the point she picked, now.
      </p>
    </div>
    """
  end

  defp card_title(:yearning), do: "Yearning"
  defp card_title(:body), do: "The body"
  defp card_title(:cage_escapes), do: "The cage"
  defp card_title(_which), do: "The record"

  # The escapes card. It sits beside the body card on the same screen because it is
  # a fact about the same body, and it is still not a body channel: a channel is a
  # level on the house scale, an escape is an event with a time. There is no sixth
  # point for it to be, and nothing on this card is ever inferred.
  #
  # No streak and no "days since the last one". An escape is not a lapse, and a
  # countdown turns a household fact into something that resets.
  defp cage_card(assigns) do
    ~H"""
    <div class="report-card">
      <div class="card-title">The cage — escapes  ·  press + when it came off</div>
      <%= if @report.cage_escapes.source == :unreported do %>
        <p class="unreported">the panel has not reported the escape log yet</p>
      <% else %>
        <div class="row" style="align-items:baseline;">
          <span style="font-size:30px; line-height:1;"><%= @report.cage_escapes.total %></span>
          <span class="dim"><%= night_phrase(@report.cage_escapes) %></span>
        </div>
        <div class="tap-row">
          <button
            type="button"
            phx-click="record_cage_escape"
            phx-disable-with="…"
            title="it came off on its own"
            aria-label="count one cage escape"
            class="tap"
            style="font-size:17px;"
          >+  it came off</button>
        </div>
        <p class="tap-legend"><%= escape_legend(@report.cage_escapes) %></p>
        <%= if @report.cage_escapes.last do %><%= cage_last(assigns) %><% end %>
      <% end %>
      <.result tap={@tap} where={:cage_escapes} />
      <p class="dim" style="margin-top:8px; font-size:12px;">
        A count is not a reading: it stays here rather than on the body card, where every point is a number on one scale. Nothing on this card is measured or inferred — it is what she says happened.
      </p>
    </div>
    """
  end

  # The one entry she is most likely to want back, with both corrections drawn as
  # words rather than a toggle: "it was night" says what pressing it will do, and a
  # switch whose current state has to be inferred from its position is the thing
  # people get wrong at five in the morning.
  defp cage_last(assigns) do
    event = assigns.report.cage_escapes.last

    assigns =
      assigns
      |> assign(:escape_id, event.id)
      |> assign(:escape_period, event.period)
      |> assign(:escape_target, if(event.period == :night, do: "day", else: "night"))
      |> assign(:escape_ago, ago(event.at))
      |> assign(:escape_note, event.note)

    ~H"""
    <div style="margin-top:10px; border-top:1px solid #222c56; padding-top:8px;">
      <div class="row">
        <span class="dim" style="font-size:12px;">
          most recent — <%= @escape_ago %><%= if @escape_note, do: " · #{@escape_note}", else: "" %>
        </span>
        <span class="chip"><%= @escape_period %></span>
      </div>
      <div class="tap-row" style="margin:6px 0 0;">
        <button
          type="button"
          phx-click="flip_cage_escape"
          phx-value-id={@escape_id}
          phx-value-period={@escape_target}
          title={"move this one to the #{@escape_target}"}
          aria-label={"count the most recent escape as #{@escape_target} instead"}
          class="tap"
          style="min-height:34px; font-size:13px;"
        >it was <%= @escape_target %></button>
        <button
          type="button"
          phx-click="undo_cage_escape"
          title="take back the most recent escape"
          aria-label="take back the most recent escape"
          class="tap"
          style="min-height:34px; font-size:13px; flex:0 0 28%;"
        >undo</button>
      </div>
    </div>
    """
  end

  defp night_phrase(%{night: night, day: day}) when is_integer(night) and is_integer(day),
    do: "#{night} at night · #{day} during the day"

  defp night_phrase(_block), do: ""

  defp escape_legend(%{window: %{from: from, until: until}}),
    do:
      "night means #{clock(from)}\u2013#{clock(until)}. An escape found in the morning can be moved with one press."

  defp escape_legend(_block),
    do: "An escape found in the morning can be moved with one press."

  defp clock(hour) when is_integer(hour),
    do: "#{String.pad_leading(Integer.to_string(hour), 2, "0")}:00"

  defp clock(_hour), do: "?"

  defp escape_verb(:record), do: "counted"
  defp escape_verb(:undo), do: "took it back"
  defp escape_verb(:flip), do: "moved it"
  defp escape_verb(_intent), do: "saved it"

  defp escape_line(intent, %{total: total} = block) when is_integer(total) do
    counts = "#{block.night || 0} at night, #{block.day || 0} during the day"

    case intent do
      :record -> "counted — #{total} in all, #{counts}."
      :undo -> "took the last one back — #{total} in all, #{counts}."
      :flip -> "moved it — #{total} in all, #{counts}."
    end
  end

  defp escape_line(_intent, _block), do: "the log did not read back — reload the page"

  defp escape_block(%{cage_escapes: block}) when is_map(block), do: block
  defp escape_block(_report), do: nil

  # Relative, never a clock time. This surface has no timezone database either, so
  # a UTC hour drawn as if it were local would be six hours out and look entirely
  # plausible. "3h ago" is true wherever the reader is standing.
  defp ago(at) when is_binary(at) do
    case DateTime.from_iso8601(at) do
      {:ok, then, _offset} -> ago_phrase(DateTime.diff(DateTime.utc_now(), then, :second))
      {:error, _reason} -> "just now"
    end
  end

  defp ago(_at), do: "just now"

  defp ago_phrase(seconds) when seconds < 60, do: "just now"
  defp ago_phrase(seconds) when seconds < 3_600, do: "#{div(seconds, 60)}m ago"
  defp ago_phrase(seconds) when seconds < 86_400, do: "#{div(seconds, 3_600)}h ago"

  defp ago_phrase(seconds) do
    case div(seconds, 86_400) do
      1 -> "yesterday"
      days -> "#{days} days ago"
    end
  end

  defp body_card(assigns) do
    ~H"""
    <div class="report-card">
      <div class="card-title">The body — <%= HUD.channels_label(channels_of(@report)) %>  ·  tap a point to log it</div>
      <p class="tap-legend">The points: <%= Enum.map_join(@report.body.scale, " · ", &"#{&1.level} #{&1.word}") %></p>
      <%= for channel <- @report.body.channels do %>
        <div class="row" style="margin-top:10px;">
          <span><%= channel.label %></span>
          <span class={if channel.source == :unreported, do: "unreported", else: "dim"}>
            <%= channel.display %><%= if channel.source_label, do: " · #{channel.source_label}", else: "" %>
          </span>
        </div>
        <p class="dim" style="margin:2px 0 4px; font-size:11px;"><%= channel.detail %></p>
        <div class="tap-row">
          <%= for point <- @report.body.scale do %>
            <button
              type="button"
              phx-click="record_body_reading"
              phx-value-kind={channel.key}
              phx-value-level={point.level}
              phx-disable-with="…"
              title={"#{channel.label} #{point.level} — #{point.word}"}
              aria-label={"log #{channel.label} at #{point.level}, #{point.word}"}
              class={"tap#{if channel.today? and channel.level == point.level, do: " on", else: ""}"}
            ><%= point.level %></button>
          <% end %>
        </div>
      <% end %>
      <.result tap={@tap} where={:body} />
      <p class="dim" style="margin-top:8px; font-size:12px;">
        A reading carries one number and the point she picked. A tap is what she says, never what was measured — and a channel with nothing on record stays empty rather than reading as nothing at all.
      </p>
    </div>
    """
  end

  # The result line belongs to the card the tap was made in. Each screen draws
  # one card today, and the `where` still has to match: a line under the wrong
  # card is a lie about where the reading went.
  attr(:tap, :map, default: nil)
  attr(:where, :atom, required: true)

  defp result(assigns) do
    ~H"""
    <%= if @tap && Map.get(@tap, :where) == @where do %>
      <p class={class(@tap)} style="margin-top:6px; font-size:12px;"><%= line(@tap) %></p>
    <% end %>
    """
  end

  # ── the tap, said out loud ──────────────────────────────────────────────────

  # The word comes from the same scale the buttons were drawn from, so the
  # sentence and the button cannot disagree about what a 4 means. `what` is the
  # tapped point said out loud; `where` is which card owns the sentence.
  defp yearning_tap(level, report) do
    %{where: :yearning, level: level, what: point_phrase(level, scale_of(report))}
  end

  defp body_tap(kind, level, report) do
    channel = Enum.find(channels_of(report), &(&1.key == kind))
    label = if channel, do: channel.label, else: kind

    %{
      where: :body,
      kind: kind,
      level: level,
      what: "#{label} at #{point_phrase(level, body_scale_of(report))}"
    }
  end

  defp point_phrase(level, scale) do
    word = Enum.find_value(scale, fn point -> point.level == level && point.word end)
    "#{level} of 5 (#{word})"
  end

  defp parse_point(raw) when is_binary(raw) do
    case Integer.parse(raw) do
      {level, ""} when level in 0..5 -> {:ok, level}
      _other -> :error
    end
  end

  defp parse_point(_raw), do: :error

  # Which reading the re-read produced for the tap being confirmed: hers for
  # yearning, that channel's for a body reading. A channel that vanished between
  # the tap and the read answers `nil`, which cannot confirm anything.
  defp reading_of(report, %{where: :body, kind: kind}) do
    Enum.find(channels_of(report), &(&1.key == kind)) ||
      %{level: nil, today?: false, display: "not reported"}
  end

  defp reading_of(report, _tap) when is_map(report), do: Map.get(report, :yearning)
  defp reading_of(_report, _tap), do: nil

  defp channel?(_report, kind) when not is_binary(kind), do: false
  defp channel?(report, kind), do: Enum.any?(channels_of(report), &(&1.key == kind))

  defp channels_of(%{body: %{channels: channels}}) when is_list(channels), do: channels
  defp channels_of(_report), do: []

  defp scale_of(%{scale: scale}) when is_list(scale) and scale != [], do: scale
  defp scale_of(_report), do: HUD.house_scale()

  defp body_scale_of(%{body: %{scale: scale}}) when is_list(scale) and scale != [], do: scale
  defp body_scale_of(_report), do: HUD.house_scale()

  defp bad_point(where) do
    %{where: where, error: "that is not one of the six points this house keeps"}
  end

  defp bad_channel(kind) do
    %{
      where: :body,
      error: "#{kind} is not a channel on this card — reload the page and tap it again"
    }
  end

  # A refusal keeps the bot's own sentence: it names the channels, or the range,
  # or says the house is paused, and none of that is improved by this screen
  # paraphrasing it. A reply that is not a result says so rather than being
  # rounded up to success.
  defp decode_write(body) do
    case Jason.decode(body) do
      {:ok, %{"ok" => true, "data" => data}} when is_map(data) -> {:ok, data}
      {:ok, %{"ok" => true}} -> {:ok, %{}}
      {:ok, %{"ok" => false, "error" => error}} when is_binary(error) -> {:error, error}
      {:ok, %{"ok" => false}} -> {:error, "the bot refused it without saying why"}
      {:ok, _other} -> {:error, "the bot answered something that is not a result"}
      {:error, _} -> {:error, "the bot's answer could not be read"}
    end
  end

  # A dead broker is not a refusal and must not read like one. "Nothing was
  # recorded" is the one thing this sentence has to make unambiguous.
  defp write_trouble(reason) do
    Logger.debug("[SelfReport] a write answered nothing: #{inspect(reason)}")
    "no answer from the wife care bot — nothing was recorded"
  end
end
