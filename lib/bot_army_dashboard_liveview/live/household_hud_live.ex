defmodule BotArmyDashboardLiveview.HouseholdHUDLive do
  @moduledoc """
  The household HUD — the doc's visual-novel dashboard, rendered from what the
  wife care bot actually reports.

  It reads the house, and it writes nothing. The two things that are hers to
  say — the yearning reading (§19) and a body reading (§15) — are reported on
  her own screen, `/timer-phone`, where the timer she already uses lives. A
  reading screen and a reporting screen should not be the same screen: one is
  what the house is, the other is what she says about herself, and putting them
  together turns a report into something done for a display. What stays here is
  the *read* of both, as the house's own numbers.

  The one control that changes *the house* is still the exit, and the exit lives
  on the control panel, where the pause gate and the audit log are; this screen
  shows that it exists and points at it, rather than growing a second way to stop
  things.

  Nothing here is decorative data. A section that has no reading says so.


  There are no keys to press. It used to advertise "r refresh" and a "?" note,
  and it bound neither: this surface has no key handler at all, so the hint was a
  promise the page could not keep. The interactive things are the lens strip and
  the exit's button to the control panel — the two ladders that used to be here
  are on `/timer-phone`, where she reports, and this screen only reads their
  latest numbers. That
  button names the host this page was reached on, because `localhost` is the
  viewer's machine and the panel does not run there.

  That button asks the bot for a **one-time entry ticket** and follows the
  redirect, so the panel opens without anyone typing a code: the ticket is
  single-use, good for sixty seconds, and mintable only for `louiza`. If the bot
  does not answer, the button falls back to the plain panel address — which lands
  on the panel's own front door, where the code from another device works. The
  fast path failing costs a tap, never the way in. What a ticket is *not* is
  proof of who is pressing: this dashboard is ungated, and whoever can load it
  can obtain an entry. The bus the request travels on is the household network's,
  and the panel refuses a ticket naming any other identity.
  """

  use Phoenix.LiveView
  alias BotArmyDashboardLiveview.Broker
  alias BotArmyDashboardLiveview.PhoneNav
  require Logger

  alias BotArmyDashboardLiveview.HouseholdHUDPayload, as: HUD

  @panel_subject "wife_care.control_panel.state"
  @chorus_subject "wife_care.chorus.categories"
  @entry_ticket_subject "wife_care.control_panel.entry_ticket"
  @request_timeout 3_000
  @panel_port 30013

  # The screen answers all of this in one read; the strip only decides what is
  # drawn. Keeping the keys here means a typo cannot quietly add a sixth lens.
  @tab_keys ~w(now goddess house ask)
  @tabs [{"now", "Now"}, {"goddess", "Goddess"}, {"house", "The house"}, {"ask", "Ask"}]

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(hud: HUD.build(nil, nil), loading?: true, asked_at: nil)
      |> assign(tab: "now")
      |> assign(control_panel_url: control_panel_url(socket.host_uri))

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

  # Changing lenses never asks the bot again — all four are already on this
  # screen. An unknown key is left alone rather than guessed at.
  @impl true
  def handle_event("tab", %{"tab" => tab}, socket) when tab in @tab_keys do
    {:noreply, assign(socket, tab: tab)}
  end

  def handle_event("tab", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("refresh", _params, socket) do
    {:noreply, fetch(socket)}
  end

  @impl true
  def handle_event("open_panel", _params, socket) do
    {:noreply, redirect(socket, external: panel_entry_url(socket.assigns.control_panel_url))}
  end

  # `hud-help` and `open-control-panel` used to sit here as `{:noreply, socket}`
  # no-ops that no element ever fired. They are deleted rather than bound: this
  # screen has no keys and no clickable cards, and dead handlers pretending
  # otherwise are part of what made the hint line look true.
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
    case Broker.request(subject, "", timeout: @request_timeout) do
      {:ok, %{body: body}} -> body
      other -> unreachable(subject, other)
    end
  rescue
    error ->
      unreachable(subject, {:raised, error})
  catch
    kind, reason ->
      unreachable(subject, {kind, reason})
  end

  # Every way of getting nothing back leaves a trace. The screen says "no answer
  # from the wife care bot" whichever one it was, so without this line an
  # operator cannot tell a dead broker from a bot that stayed quiet — and a live
  # broker answering `{:error, :no_responders}` used to be swallowed with no log
  # at all. Debug level, like the rest of this surface's read path.
  defp unreachable(subject, reason) do
    Logger.debug("[HouseholdHUD] #{subject} answered nothing: #{inspect(reason)}")
    nil
  end

  # The link has to name the host this dashboard was reached on. From a phone or
  # a second machine, "localhost" is the *viewer's* machine, where the control
  # panel is not running — which is how a working panel came to look like one that
  # did not exist. `socket.host_uri` is this request's own host.
  defp control_panel_url(host_uri) do
    System.get_env("WIFE_CARE_CONTROL_PANEL_URL") ||
      "http://#{panel_host(host_uri)}:#{@panel_port}"
  end

  defp panel_host(%URI{host: host}) when is_binary(host) and host != "", do: host
  defp panel_host(_host_uri), do: "localhost"

  # One tap: mint a ticket, then follow the redirect into it. `Door` on the panel
  # is what recognises the `k_…` shape, so nothing here has to know the format.
  defp panel_entry_url(panel_url) do
    case Broker.request(@entry_ticket_subject, "{}", timeout: @request_timeout) do
      {:ok, %{body: body}} -> ticket_entry_url(panel_url, body)
      other -> plain_panel_url(panel_url, other)
    end
  rescue
    error -> plain_panel_url(panel_url, {:raised, error})
  catch
    kind, reason -> plain_panel_url(panel_url, {kind, reason})
  end

  defp ticket_entry_url(panel_url, body) do
    case Jason.decode(body) do
      {:ok, %{"ok" => true, "data" => %{"ticket" => ticket}}} when is_binary(ticket) ->
        panel_url <> "/enter?t=" <> URI.encode_www_form(ticket)

      {:ok, %{"ok" => false}} ->
        plain_panel_url(panel_url, :refused)

      {:ok, _decoded} ->
        plain_panel_url(panel_url, :unexpected_reply)

      {:error, _} ->
        plain_panel_url(panel_url, :not_json)
    end
  end

  # The whole point of the fallback: a bot that is down, or a build that predates
  # this subject, costs a tap — the panel still opens, on the page that carries
  # the code door. Nothing is swallowed silently, so an operator can tell the
  # three apart from the log.
  #
  # A reason and never a body: a mint reply's `data` holds a live ticket, and a
  # log line is the one place it must never be.
  defp plain_panel_url(panel_url, reason) do
    Logger.debug("[HouseholdHUD] no entry ticket: #{inspect(reason)}")
    panel_url
  end

  defp clock do
    DateTime.utc_now() |> DateTime.to_time() |> Time.to_iso8601() |> String.slice(0, 5)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <style>
      .hud { max-width: 900px; margin: 0 auto; padding-bottom: 78px; }
      .hud-title { font-size: 22px; letter-spacing: 1px; margin-bottom: 4px; }
      .hud-sub { color: #8b93b0; font-size: 13px; margin-bottom: 18px; }
      .card { background: #131a3a; border: 1px solid #222c56; border-radius: 10px; padding: 14px 16px; margin-bottom: 14px; }
      .card-title { font-size: 12px; letter-spacing: 1.5px; text-transform: uppercase; color: #6f7db2; margin-bottom: 10px; }
      /* Four lenses, one screen. They split the width evenly so a thumb or a dpad
         reaches any of them without aiming, and the exit stays below them. */
      .hud-tabs { display: flex; gap: 8px; margin: 0 0 14px; }
      .hud-tabs .tab { flex: 1; padding: 10px 8px; font: inherit; font-size: 13px; letter-spacing: 0.5px; color: #a9b4e0; background: #10162f; border: 1px solid #222c56; border-radius: 8px; cursor: pointer; }
      .hud-tabs .tab.on { color: #0a0e27; background: #ffb3d1; border-color: #ff5fa2; }
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
      .read-note { color: #6f7db2; font-size: 11px; line-height: 1.6; }
      .chorus-item { display: flex; gap: 10px; align-items: baseline; padding: 5px 0; font-size: 14px; }
      .exit { border-color: #ff5fa2; }
      .exit a { color: #ffb3d1; text-decoration: none; }
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
      /* §19: the doc's Devotion texture — soft golden light in place of the
         punishment wash, when she logged a yearning reading today. */
      .hud.state-goddess_mode::before { background: radial-gradient(120% 90% at 50% 0%, #6a5320 0%, #3a2c12 55%, #100c06 100%); }
      .hud.state-goddess_mode .hud-title { text-shadow: 0 0 16px rgba(255, 209, 102, 0.5); }
      .hud.state-strain::before { background: radial-gradient(90% 70% at 50% 50%, #0f1430 30%, #05060f 100%); }
      .hud.state-restoration::before { background: radial-gradient(120% 90% at 50% 0%, #16302a 0%, #0f2138 60%, #070c17 100%); }
      .hud.state-tender::before { background: radial-gradient(120% 90% at 50% 0%, #2a2634 0%, #1a1622 60%, #0a0e27 100%); }
      .hud.bloom::before { box-shadow: inset 0 0 120px rgba(255, 179, 209, 0.18); }
      .hud.mode-glow .hud-title { text-shadow: 0 0 12px rgba(255, 179, 209, 0.55); }
      .hud.mode-pulse .hud-title { animation: hud-pulse 3.5s ease-in-out infinite; }
      @keyframes hud-pulse { 0%, 100% { opacity: 1; } 50% { opacity: 0.72; } }
      .hud.mode-hush { opacity: 0.88; }
      .hud.mode-deep::before { filter: contrast(1.15) saturate(1.2); }
      /* The doc's energy bands that are not whole states: a capable day lifts the
         light on whatever state is in play, and strain keeps a grain under a
         stronger state so both facts stay visible at once. */
      .hud.mode-bright::before { filter: brightness(1.12) saturate(1.05); }
      .hud.mode-bright .hud-title { text-shadow: 0 0 14px rgba(214, 232, 255, 0.45); }
      .hud.mode-grain::before { filter: contrast(1.06) grayscale(0.08); }
      .hud.mode-grain .card { box-shadow: inset 0 0 24px rgba(0, 0, 0, 0.5); }
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
      <%= render_tabs(assigns) %>

      <%= cond do %>
        <% @loading? -> %>
          <div class="card">
            <div class="card-title">Household HUD</div>
            <p class="dim">Asking the wife care bot…</p>
          </div>
        <% @hud.answering? -> %>
          <%= render_hud(assigns) %>
        <% true -> %>
          <div class="card">
            <div class="card-title">Household HUD</div>
            <p>No answer from the wife care bot yet.</p>
            <p class="dim">Reload this page to ask again. If it stays quiet, check the bot is up on the node that owns it.</p>
          </div>
      <% end %>

      <%= render_state(assigns) %>
      <%= render_ladder(assigns) %>
      <%= render_exit(assigns) %>
    </div>

    <PhoneNav.nav current_route="/household-hud" />
    """
  end

  # The doc's core idea: the space itself acknowledges where she is, so the state
  # is drawn with its reason. Nothing here is ever a hardcoded 65%.
  defp render_state(assigns) do
    ~H"""
    <%= if @tab == "now" do %>
    <div class="card">
      <div class="card-title">Active state — the interface's texture</div>
      <div class="row">
        <span><%= @hud.visual.name %></span>
        <span class="dim">Energy: <%= @hud.visual.energy.display %></span>
      </div>
      <div class="row"><span class="dim"><%= @hud.visual.style %></span></div>
      <p class="dim" style="font-size:12px;"><%= @hud.visual.texture %></p>
      <p class="dim" style="margin-top:6px; font-size:12px;">
        <%= @hud.visual.energy.band_text %>
        <%= if @hud.visual.energy.readings > 0 do %>
          (<%= @hud.visual.energy.readings %> reading<%= if @hud.visual.energy.readings == 1, do: "", else: "s" %><%= if @hud.visual.energy.producer, do: " from #{@hud.visual.energy.producer}", else: "" %>)
        <% end %>
      </p>
      <%= if @hud.visual.energy.restoring do %>
        <p style="margin-top:6px; font-size:12px;">
          Recovery is underway — the reading is climbing, so the space softens with it.
        </p>
      <% end %>
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
    <% end %>
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
    <%= if @tab == "house" do %>
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
    <% end %>
    """
  end

  # A button, not a link: the lens is this screen's own state and there is no
  # second read to pay for. The exit is deliberately not one of these — it stays
  # under the strip in every lens.
  defp tabs, do: @tabs

  defp render_tabs(assigns) do
    ~H"""
    <nav class="hud-tabs">
      <%= for {key, label} <- tabs() do %>
        <button type="button" phx-click="tab" phx-value-tab={key} class={"tab#{if @tab == key, do: " on", else: ""}"}><%= label %></button>
      <% end %>
    </nav>
    """
  end

  # Rendered in every state. Hiding the way out exactly when the panel goes quiet
  # would take it away at the moment it is most worth having.
  defp render_exit(assigns) do
    ~H"""
    <div class="card exit">
      <div class="card-title">Exit — always available</div>
      <p><%= @hud.exit.label %> — <span class="dim"><%= @hud.exit.detail %></span></p>
      <p style="margin-top:6px;">
        <button type="button" phx-click="open_panel" phx-disable-with="opening…">→ open the control panel</button>
      </p>
      <p class="dim" style="margin-top:6px; font-size:12px;">
        It asks the wife care bot for one-time entry — good for a minute and a single use. If the bot does not answer, the panel opens on its own front door instead, where you can type the code from another device.
      </p>
      <p class="dim" style="margin-top:6px; font-size:12px;">While paused, anything that raises something is refused at write time — not merely hidden here.</p>
    </div>
    """
  end

  # Only the sections that need a reading come from here.
  defp render_hud(assigns) do
    ~H"""
    <%= if @tab == "now" do %>
    <div class="card">
      <div class="card-title">Containment</div>
      <div class="row">
        <span><%= @hud.containment.display %></span>
        <span class="dim"><%= @hud.containment.detail %></span>
      </div>
      <div class="card-title" style="margin-top:12px;">Intensity</div>
      <div class="row">
        <span class={if @hud.intensity.source == :unreported, do: "unreported", else: ""}>
          <%= @hud.intensity.display %>
        </span>
        <span class="dim">set on the control board</span>
      </div>
      <%= if @hud.intensity.percent do %>
        <div class="meter"><div style={"width: #{@hud.intensity.percent}%"}></div></div>
      <% end %>
    </div>
    <% end %>

    <%= if @tab == "house" do %>
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
    <% end %>

    <%= if @tab == "goddess" do %>
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
    <% end %>

    <%= if @tab == "now" do %>
    <div class="card">
      <div class="card-title">Yearning — the goddess-focus indicator</div>
      <%= if @hud.yearning.active? do %>
        <div class="row">
          <span class="chip on">Yearning Active</span>
          <span class="dim"><%= @hud.yearning.display %></span>
        </div>
      <% else %>
        <div class="row">
          <span class="chip">Yearning</span>
          <span class="dim">no reading today</span>
        </div>
      <% end %>
      <p class="dim" style="margin-top:6px; font-size:12px;"><%= @hud.yearning.line %></p>
      <p class="read-note" style="margin-top:6px;">Hers to say, and never measured. She taps it on her own screen — this one only reads it.</p>
    </div>

    <div class="card">
      <div class="card-title">The body — <%= HUD.channels_label(@hud.body.channels) %></div>
      <%= for channel <- @hud.body.channels do %>
        <div class="row" style="margin-top:10px;">
          <span><%= channel.label %></span>
          <span class={if channel.source == :unreported, do: "unreported", else: "dim"}>
            <%= channel.display %><%= if channel.source_label, do: " · #{channel.source_label}", else: "" %>
          </span>
        </div>
        <p class="dim" style="margin:2px 0 0; font-size:11px;"><%= channel.detail %></p>
      <% end %>
      <p class="read-note" style="margin-top:8px;">She logs these on her own screen. Nothing on record stays empty rather than reading as nothing at all.</p>
    </div>
    <% end %>

    <%= if @tab == "goddess" do %>
    <div class="card">
      <div class="card-title">Calls she has sent — seen and done stay separate</div>
      <%= cond do %>
        <% @hud.demands.source == :unreported -> %>
          <p class="unreported">The bot didn't report this just now — no count and no list, rather than a zero.</p>
        <% is_nil(@hud.demands.pending) -> %>
          <p class="unreported">Today's calls were reported, but not which are still open — so nothing here is shown as answered.</p>
        <% true -> %>
          <div class="row">
            <span><%= if is_integer(@hud.demands.today_count), do: "#{@hud.demands.today_count} today", else: "today's count not reported" %></span>
            <span class="dim"><%= if @hud.demands.pending == [], do: "nothing waiting", else: "#{length(@hud.demands.pending)} waiting" %></span>
          </div>
          <%= for demand <- @hud.demands.pending do %>
            <div class="row">
              <span><%= demand.label %></span>
              <span class="dim"><%= demand.state %></span>
            </div>
          <% end %>
          <%= if is_list(@hud.demands.pending) and @hud.demands.pending != [] do %>
            <p class="read-note" style="margin-top:8px;">
              A call is still open, so the shelf is offered —
              <a href="/party-phone">open the window it is offered in</a>.
            </p>
          <% end %>
          <%= if is_list(@hud.demands.recent_fulfilled) and @hud.demands.recent_fulfilled != [] do %>
            <p class="dim" style="margin-top:8px; font-size:12px;">
              Recently done: <%= Enum.map_join(@hud.demands.recent_fulfilled, " · ", &"#{&1.label} (#{&1.state})") %>
            </p>
          <% end %>
      <% end %>
    </div>
    <% end %>

    <%= if @tab == "ask" do %>
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
    <% end %>
    """
  end
end
