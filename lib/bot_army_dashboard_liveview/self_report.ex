defmodule BotArmyDashboardLiveview.SelfReport do
  @moduledoc """
  The maid's own numbers, tapped by her on her own screen.

  Two things are reported here and nowhere else: **yearning** (the goddess-focus
  indicator) and a **body reading** (how much of something the body is showing).
  Both are hers to say. Neither is measured, and neither is inferred by this
  screen: a tap is a report, and the panel says so in the row it writes.

  ## Why here, and not on the household HUD

  The household HUD reads the house — what is holding, how hard the board is
  set, what the pet layer is doing, where the exit is. It is a *view*. Putting
  the input ladder on it made the reading screen and the reporting screen the
  same screen, which is how a report becomes something a person does *for* a
  screen rather than about herself. This block lives on the maid's own screen
  (`/timer-phone`), next to the timer she already uses.

  It is also deliberately **outside** the touch-carousel container on that
  screen: that container emits a `tap` event for any touch that does not move,
  and that event drives the timer. A tap on a point here must not also start a
  session, so this block sits outside the hook.

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
  """

  use Phoenix.Component

  require Logger

  alias BotArmyDashboardLiveview.Broker
  alias BotArmyDashboardLiveview.HouseholdHUDPayload, as: HUD

  @yearning_subject "wife_care.control_panel.record_goddess_proximity"
  @body_subject "wife_care.control_panel.record_body_reading"
  @request_timeout 3_000

  @doc "The subject yearning is reported on."
  def yearning_subject, do: @yearning_subject

  @doc "The subject a body reading is reported on."
  def body_subject, do: @body_subject

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

  def line(%{confirmed?: true} = tap),
    do: "logged — the reading that came back is #{tap.what} today."

  def line(%{reading: reading} = tap),
    do: "the bot took #{tap.what}, but its reading shows #{reading} — showing what it reports."

  def line(tap), do: "logged #{tap.what} — reading it back…"

  @doc "An error line is not a reading; it must not be styled like one."
  def class(%{error: _}), do: "unreported"
  def class(_tap), do: "dim"

  # ── the two cards ───────────────────────────────────────────────────────────

  @doc """
  Both report cards, with their own styles and their own result lines.

  `report` is the built panel payload (`HouseholdHUDPayload.build/2`); while it
  is `nil` the block says the read has not landed rather than drawing an empty
  scale.
  """
  attr(:report, :map, default: nil)
  attr(:tap, :map, default: nil)

  def cards(assigns) do
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

    <%!-- Below the timer card, so it needs room for the fixed nav bar rather
         than hiding its last line under it. --%>
    <div style="padding-bottom: 78px">
      <%= if @report do %>
        <%= yearning_card(assigns) %>
        <%= body_card(assigns) %>
      <% else %>
        <div class="report-card">
          <div class="card-title">Your own numbers</div>
          <p class="unreported">nothing from the panel yet — the two cards appear when the read lands</p>
        </div>
      <% end %>
    </div>
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

  defp body_card(assigns) do
    ~H"""
    <div class="report-card">
      <div class="card-title">The body — five channels  ·  tap a point to log it</div>
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

  # The result line belongs to the card the tap was made in. Two cards are on
  # screen at once, and a line under the wrong one is a lie about where the
  # reading went.
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
