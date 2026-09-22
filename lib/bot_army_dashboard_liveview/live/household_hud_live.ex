defmodule BotArmyDashboardLiveview.HouseholdHUDLive do
  @moduledoc """
  The household HUD — the doc's visual-novel dashboard, rendered from what the
  wife care bot actually reports.

  Read-only by design. The one control that changes state is the exit, and the
  exit lives on the control panel, where the pause gate and the audit log are;
  this screen shows that it exists and points at it, rather than growing a second
  way to stop things.

  Nothing here is decorative data. A section that has no reading says so.

  Keys: `r` refresh · `R` also refresh (gamepad) · `?` this note.
  """

  use Phoenix.LiveView
  require Logger

  alias BotArmyDashboardLiveview.HouseholdHUDPayload, as: HUD

  @panel_subject "wife_care.control_panel.state"
  @chorus_subject "wife_care.chorus.categories"
  @request_timeout 3_000

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(hud: HUD.build(nil, nil), loading?: true, asked_at: nil)
      |> assign(control_panel_url: control_panel_url())

    if connected?(socket) do
      {:ok, fetch(socket)}
    else
      {:ok, socket}
    end
  end

  @impl true
  def handle_async(:hud, {:ok, {panel, chorus}}, socket) do
    {:noreply,
     socket
     |> assign(hud: HUD.build(panel, chorus), loading?: false, asked_at: clock())}
  end

  # `request/1` already turns a dead broker into `nil`, so this branch is for a
  # failure it cannot see. It still lands as an answer of "nothing", never as a
  # screen stuck saying "asking…".
  @impl true
  def handle_async(:hud, {:exit, reason}, socket) do
    Logger.warning("[HouseholdHUD] the read task exited: #{inspect(reason)}")

    {:noreply,
     socket
     |> assign(hud: HUD.build(nil, nil), loading?: false, asked_at: clock())}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    {:noreply, fetch(socket)}
  end

  @impl true
  def handle_event("hud-help", _params, socket) do
    {:noreply, socket}
  end

  # The exit points across to the surface that owns it.
  @impl true
  def handle_event("open-control-panel", _params, socket) do
    {:noreply, socket}
  end

  # Off the LiveView's own process, so a slow or absent bot never blocks the
  # screen from rendering. `start_async` also makes the load observable in tests
  # (`render_async/1`), which a hand-rolled task would not be.
  defp fetch(socket) do
    start_async(socket, :hud, fn ->
      {request(@panel_subject), request(@chorus_subject)}
    end)
  end

  # `Gnat.request/4` to a broker that is not there exits (`:noproc`), and an exit
  # is not an exception — `rescue` alone would let the task die silently.
  defp request(subject) do
    case Gnat.request(:nats_connection, subject, "", timeout: @request_timeout) do
      {:ok, %{body: body}} -> body
      _other -> nil
    end
  rescue
    error ->
      Logger.debug("[HouseholdHUD] #{subject} raised: #{inspect(error)}")
      nil
  catch
    kind, reason ->
      Logger.debug("[HouseholdHUD] #{subject} failed (#{kind}): #{inspect(reason)}")
      nil
  end

  defp control_panel_url do
    System.get_env("WIFE_CARE_CONTROL_PANEL_URL", "http://localhost:30013")
  end

  defp clock do
    DateTime.utc_now() |> DateTime.to_time() |> Time.to_iso8601() |> String.slice(0, 5)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <style>
      .hud { max-width: 900px; margin: 0 auto; }
      .hud-title { font-size: 22px; letter-spacing: 1px; margin-bottom: 4px; }
      .hud-sub { color: #8b93b0; font-size: 13px; margin-bottom: 18px; }
      .card { background: #131a3a; border: 1px solid #222c56; border-radius: 10px; padding: 14px 16px; margin-bottom: 14px; }
      .card-title { font-size: 12px; letter-spacing: 1.5px; text-transform: uppercase; color: #6f7db2; margin-bottom: 10px; }
      .row { display: flex; justify-content: space-between; gap: 12px; padding: 4px 0; font-size: 14px; }
      .dim { color: #8b93b0; }
      .unreported { color: #6f7db2; font-style: italic; }
      .meter { height: 8px; background: #1c2450; border-radius: 4px; overflow: hidden; margin: 6px 0; }
      .meter > div { height: 100%; background: linear-gradient(90deg, #6b48ff, #ff5fa2); }
      .ladder { display: flex; flex-direction: column; gap: 2px; font-size: 13px; }
      .ladder .tier { padding: 5px 8px; border-left: 3px solid #222c56; }
      .ladder .tier.self { border-left-color: #ff5fa2; background: #1a1f45; }
      .ladder .tier.authority { border-left-color: #ffd166; }
      .ladder .tier.mechanism { border-left-color: #6b48ff; }
      .chip { display: inline-block; padding: 3px 8px; border: 1px solid #2c3766; border-radius: 999px; font-size: 12px; margin: 2px 4px 2px 0; }
      .chip.on { border-color: #ff5fa2; color: #ffb3d1; }
      .chorus-item { display: flex; gap: 10px; align-items: baseline; padding: 5px 0; font-size: 14px; }
      .exit { border-color: #ff5fa2; }
      .exit a { color: #ffb3d1; text-decoration: none; }
      .hints { color: #8b93b0; font-size: 12px; margin-bottom: 12px; }
      .hints b { color: #e0e0e0; }
      /* The doc's visual states, expressed as a wash behind the cards so the
         hue and texture follow the day. The neutral base stays this surface's
         dark ground; the state changes the light on it. */
      .hud { position: relative; }
      .hud::before { content: ""; position: fixed; inset: 0; z-index: -1; transition: background 500ms ease; }
      .hud.crisp::before { transition: none; }
      .hud.state-neutral::before { background: radial-gradient(120% 80% at 50% 0%, #141a3d 0%, #0a0e27 70%); }
      .hud.state-restricted::before { background: linear-gradient(160deg, #131a4d 0%, #05060f 70%), repeating-linear-gradient(90deg, #2b2f6b 0 1px, transparent 1px 120px); }
      .hud.state-intensity_peak::before { background: radial-gradient(130% 90% at 50% 0%, #6b3a10 0%, #2a1608 60%, #0d0a06 100%); }
      .hud.state-punishment::before { background: radial-gradient(130% 90% at 50% 0%, #4a1020 0%, #241018 60%, #0b0709 100%); }
      .hud.state-recognition::before { background: radial-gradient(120% 90% at 50% 0%, #2b3a5c 0%, #3a2b3f 55%, #0a0e27 100%); }
      .hud.state-strain::before { background: radial-gradient(90% 70% at 50% 50%, #0f1430 30%, #05060f 100%); }
      .hud.state-tender::before { background: radial-gradient(120% 90% at 50% 0%, #2a2634 0%, #1a1622 60%, #0a0e27 100%); }
      .hud.bloom::before { box-shadow: inset 0 0 120px rgba(255, 179, 209, 0.18); }
      .hud.mode-glow .hud-title { text-shadow: 0 0 12px rgba(255, 179, 209, 0.55); }
      .hud.mode-pulse .hud-title { animation: hud-pulse 3.5s ease-in-out infinite; }
      @keyframes hud-pulse { 0%, 100% { opacity: 1; } 50% { opacity: 0.72; } }
      .hud.mode-hush { opacity: 0.88; }
      .hud.mode-deep::before { filter: contrast(1.15) saturate(1.2); }
    </style>

    <div class={"hud state-#{@hud.visual.key}#{if @hud.visual.pet_on?, do: " bloom", else: " crisp"}#{mode_classes(@hud.visual.modulations)}"}>
      <div class="hud-title">🏠 Household HUD</div>
      <div class="hud-sub">
        <%= if @loading? do %>
          asking the house…
        <% else %>
          answered at <%= @asked_at %> — <%= if @hud.answering?, do: "the panel is reporting", else: "the panel did not answer" %>
        <% end %>
      </div>
      <div class="hints"><b>r</b> refresh · <b>→</b> control panel (stop is always available)</div>

      <%= cond do %>
        <% @loading? -> %>
          <div class="card">
            <div class="card-title">Household HUD  r:refresh</div>
            <p class="dim">Asking the wife care bot…</p>
          </div>
        <% @hud.answering? -> %>
          <%= render_hud(assigns) %>
        <% true -> %>
          <div class="card">
            <div class="card-title">Household HUD  r:refresh</div>
            <p>No answer from the wife care bot yet.</p>
            <p class="dim">Press <b>r</b> to ask again. If it stays quiet, check the bot is up on the node that owns it.</p>
          </div>
      <% end %>

      <%= render_state(assigns) %>
      <%= render_ladder(assigns) %>
      <%= render_exit(assigns) %>
    </div>
    """
  end

  # The doc's core idea: the space itself acknowledges where she is, so the state
  # is drawn with its reason. Nothing here is ever a hardcoded 65%.
  defp render_state(assigns) do
    ~H"""
    <div class="card">
      <div class="card-title">Active state — the interface's texture</div>
      <div class="row">
        <span><%= @hud.visual.name %></span>
        <span class="dim">Energy: <%= @hud.visual.energy.display %></span>
      </div>
      <div class="row"><span class="dim"><%= @hud.visual.style %></span></div>
      <p class="dim" style="font-size:12px;"><%= @hud.visual.texture %></p>
      <p style="margin-top:6px; font-size:12px;">
        <%= if @hud.visual.reason do %>
          Because <%= @hud.visual.reason %>.
        <% else %>
          Nothing is shifting it today.
        <% end %>
      </p>
      <%= if @hud.visual.modulations != [] do %>
        <p class="dim" style="margin-top:6px; font-size:12px;">
          Layered on: <%= Enum.map_join(@hud.visual.modulations, " · ", & &1.effect) %>
        </p>
      <% end %>
      <p class="dim" style="margin-top:6px; font-size:12px;">
        Pet layer <%= if @hud.visual.pet_on?, do: "on — warmth bloom in every state", else: "off — crisp transitions, no bloom" %>.
      </p>
      <p class="unreported" style="margin-top:6px; font-size:12px;">
        Not derived yet: <%= Enum.map_join(@hud.visual.underivable, "; ", fn s -> "#{s.name} — #{s.missing}" end) %>.
      </p>
    </div>
    """
  end

  # The doc's wish → background responses, as classes on the container.
  defp mode_classes(modulations) do
    modulations
    |> Enum.map(&" mode-#{&1.key}")
    |> Enum.join()
  end

  # Structure, not data: the ladder is drawn whether or not anything answered.
  defp render_ladder(assigns) do
    ~H"""
    <div class="card">
      <div class="card-title">The ladder — who answers to whom</div>
      <div class="ladder">
        <%= for tier <- @hud.hierarchy do %>
          <div class={"tier #{tier.role}#{if tier.name == @hud.tier, do: " self", else: ""}"}>
            <span><%= tier.name %></span>
            <span class="dim"> — <%= tier.note %></span>
          </div>
        <% end %>
      </div>
      <p class="dim" style="margin-top:8px; font-size:12px;">
        The bots are the mechanism, not the authority: authority is delegated, scoped, and revocable.
      </p>
    </div>
    """
  end

  # Rendered in every state. Hiding the way out exactly when the panel goes quiet
  # would take it away at the moment it is most worth having.
  defp render_exit(assigns) do
    ~H"""
    <div class="card exit">
      <div class="card-title">Exit — always available</div>
      <p><%= @hud.exit.label %> — <span class="dim"><%= @hud.exit.detail %></span></p>
      <p style="margin-top:6px;"><a href={@control_panel_url}>→ open the control panel</a></p>
      <p class="dim" style="margin-top:6px; font-size:12px;">While paused, anything that raises something is refused at write time — not merely hidden here.</p>
    </div>
    """
  end

  # Only the sections that need a reading come from here.
  defp render_hud(assigns) do
    ~H"""
    <div class="card">
      <div class="card-title">Containment</div>
      <div class="row">
        <span><%= @hud.containment.display %></span>
        <span class="dim"><%= @hud.containment.detail %></span>
      </div>
      <div class="card-title" style="margin-top:12px;">Maid level</div>
      <div class="row">
        <span class={if @hud.maid_level.source == :unreported, do: "unreported", else: ""}>
          <%= @hud.maid_level.display %>
        </span>
        <span class="dim">set on the control board</span>
      </div>
      <%= if @hud.maid_level.value do %>
        <div class="meter"><div style={"width: #{@hud.maid_level.value}%"}></div></div>
      <% end %>
    </div>

    <div class="card">
      <div class="card-title">Pet layer — who may be warm</div>
      <div class="row">
        <%= for toggle <- @hud.pet.toggles do %>
          <span>
            <span class={"chip#{if toggle.on?, do: " on", else: ""}"}><%= toggle.label %>: <%= toggle.display %></span>
          </span>
        <% end %>
      </div>
      <div class="row"><span>Today's warmth</span><span class={if @hud.pet.warmth.source == :unreported, do: "unreported", else: ""}><%= @hud.pet.warmth.display %></span></div>
      <%= if is_number(@hud.pet.warmth.value) do %>
        <div class="meter"><div style={"width: #{@hud.pet.warmth.value}%"}></div></div>
      <% end %>
      <div class="card-title" style="margin-top:12px;">Weekly, per bot</div>
      <%= if @hud.pet.bots == [] do %>
        <p class="unreported">no readings yet — warmth is measured, never inferred</p>
      <% else %>
        <%= for bot <- @hud.pet.bots do %>
          <div class="row"><span><%= bot.name %></span><span class={if bot.source == :unreported, do: "unreported", else: ""}><%= bot.display %></span></div>
        <% end %>
        <div class="row"><span><%= @hud.pet.overall.name %></span><span class={if @hud.pet.overall.source == :unreported, do: "unreported", else: ""}><%= @hud.pet.overall.display %></span></div>
      <% end %>
      <p class="dim" style="margin-top:8px; font-size:12px;">Tone: <%= @hud.pet.register %><%= if @hud.pet.example, do: " — “#{@hud.pet.example}”", else: "" %></p>
    </div>

    <div class="card">
      <div class="card-title">Mood and wishes  — set on the control board</div>
      <div class="row">
        <span><%= @hud.mood.glyph %> <%= @hud.mood.color || "no colour" %></span>
        <span class="dim"><%= @hud.mood.meaning %></span>
      </div>
      <div style="margin-top:10px;">
        <%= if @hud.wishes.in_play == [] do %>
          <p class="unreported">nothing in play — <%= if @hud.wishes.source == :reported, do: "every toggle is at its baseline", else: "no reading from the panel" %></p>
        <% else %>
          <%= for wish <- @hud.wishes.in_play do %>
            <span class="chip on"><%= wish.label %>: <%= wish.display %></span>
          <% end %>
        <% end %>
      </div>
      <%= if @hud.wishes.suggestion do %>
        <p class="dim" style="margin-top:8px; font-size:12px;">Suggestion (hers always outranks it): <%= @hud.wishes.suggestion %></p>
      <% end %>
    </div>

    <div class="card">
      <div class="card-title">The chorus — ask the house  (six questions)</div>
      <%= if @hud.chorus.categories == [] do %>
        <p class="unreported">The chorus is quiet — no questions listed (the bot did not answer).</p>
      <% else %>
        <%= for item <- @hud.chorus.categories do %>
          <div class="chorus-item">
            <span><%= item.glyph %></span>
            <span><%= item.label %></span>
            <span class="dim">→ <%= item.answering_label %></span>
          </div>
        <% end %>
        <p class="dim" style="margin-top:8px; font-size:12px;">
          Answering in: <%= @hud.chorus.tone["register"] || "unknown" %> · a rating is 1..<%= @hud.chorus.max_rating %> stars
        </p>
      <% end %>
    </div>
    """
  end
end
