defmodule BotArmyDashboardLiveview.PartySelectPhoneLive do
  @moduledoc """
  Building the party from her phone: who is with her, who could be, and who writes the turns.

  `/party-phone` draws the *window* — the scene, the party in it, the turns so far — and with
  no party there is no window, so the screen correctly said "no window is open" and offered
  nothing to do about it. That is a screen that can show the party and cannot make one: the
  one thing the operator needed from it was the thing it did not have. This screen is the
  other half. It reads the party and the bot's characters, and it writes the three routes that
  build the party — `rpg.party.add`, `rpg.party.remove`, `rpg.party.set_narrator` — which have
  been registered on the bot since before this dashboard existed and which nothing here could
  reach.

  Reading, the three answers to a read, the identity the party routes need, the two presses
  before a structural write, and the reason the roster names no user: all of that is
  `BotArmyDashboardLiveview.PartySelect`'s, and it is documented there. This module is the
  screen around it.

  ## A write is picked, confirmed, then confirmed *again* by the re-read

  Nothing structural happens on a stray tap. A button draws the confirmation card, the card
  sends, and the send is followed by the same read that drew the party — settled against it.
  The bot's own `ok` is drawn as *sent*, never as *done*, because the only thing that can say
  a companion is with her is the party, read back. A write is never retried, and a refusal is
  drawn as a refusal.

  ## The screen re-reads; it does not pretend to be current

  There is no live subscription here, and that is deliberate rather than unfinished: the
  party changes when the operator changes it, from this screen, and the operator is looking at
  it while she does. A manual *read it again* is offered for everything else — a turn written
  from the desk, or a party built while the phone was in a pocket. A subscription would add a
  second source of change to a screen whose whole job is that one change is confirmed by the
  party it made.
  """

  use Phoenix.LiveView

  import BotArmyDashboardLiveview.ReadError

  alias BotArmyDashboardLiveview.BotRead
  alias BotArmyDashboardLiveview.PartySelect
  alias BotArmyDashboardLiveview.PartyWindow
  alias BotArmyDashboardLiveview.PhoneNav

  @call_timeout 3_000

  @impl true
  def mount(_params, _session, socket) do
    # Two reads, two answers, two failures: the party and the characters the bot has are
    # different questions, and a screen that cannot list characters is not a screen that
    # cannot find the party.
    BotRead.async(self(), :party, PartySelect.party_subject(), PartySelect.party_payload(),
      timeout: @call_timeout
    )

    BotRead.async(self(), :roster, PartySelect.roster_subject(), PartySelect.roster_payload(),
      timeout: @call_timeout
    )

    {:ok,
     socket
     |> assign(party: nil)
     |> assign(roster: nil)
     |> assign(narrator: nil)
     |> assign(act: nil)
     |> assign(bot_id: "")}
  end

  # The party answered. It is settled against any act that is waiting on it — this is the
  # confirmation — and the narrator is read from the same answer by its one owner.
  @impl true
  def handle_info({:party, answer}, socket) do
    party = PartySelect.party(answer)

    {:noreply,
     socket
     |> assign(party: party)
     |> assign(narrator: PartySelect.narrator(party))
     |> assign(act: PartySelect.settle(socket.assigns[:act], party))}
  end

  @impl true
  def handle_info({:roster, answer}, socket),
    do: {:noreply, assign(socket, roster: PartySelect.roster(answer))}

  # What is being typed into the box that names a bot. Nothing is sent on a keystroke; this
  # only keeps the box's own text so a re-render does not lose it.
  @impl true
  def handle_event("bot_id", %{"bot_id" => bot_id}, socket),
    do: {:noreply, assign(socket, bot_id: bot_id)}

  # Picking a thing to do is not doing it. Each of these draws the confirmation, and what
  # this screen already knows the bot cannot act on is refused here rather than sent and
  # refused — a confirmation card for something that cannot happen is a step leading nowhere.
  @impl true
  def handle_event("act", params, socket) do
    case verb_of(params["verb"]) do
      {:ok, verb} ->
        {:noreply, assign(socket, act: review(verb, params))}

      :error ->
        {:noreply,
         assign(socket, act: %{state: :refused, sentence: "This screen does not know that."})}
    end
  end

  # Backing out of the confirmation sends nothing.
  @impl true
  def handle_event("cancel", _params, socket), do: {:noreply, assign(socket, act: nil)}

  # The one kind of write on this screen, and it happens only from the confirmation card.
  @impl true
  def handle_event("send", _params, socket) do
    case socket.assigns[:act] do
      %{state: :review, verb: verb, target: target} = act ->
        {:noreply,
         socket
         |> assign(act: after_send(act, PartySelect.act(verb, target)))
         |> reread_party()}

      _other ->
        {:noreply,
         assign(socket, act: %{state: :refused, sentence: "There is nothing to do to the party."})}
    end
  end

  # Read it again, because the party changed somewhere this screen cannot see.
  @impl true
  def handle_event("refresh", _params, socket), do: {:noreply, reread(socket)}

  defp verb_of("recruit"), do: {:ok, :recruit}
  defp verb_of("dismiss"), do: {:ok, :dismiss}
  defp verb_of("narrate"), do: {:ok, :narrator}
  defp verb_of("unname"), do: {:ok, :clear}
  defp verb_of(_verb), do: :error

  defp review(verb, params) do
    target = params["character_id"] || params["bot_id"]
    label = params["who"] || params["bot_id"] || "that companion"

    case PartySelect.draft(verb, target) do
      {:ok, _draft} -> %{verb: verb, target: target, label: label, state: :review}
      {:refused, sentence} -> %{state: :refused, sentence: sentence}
    end
  end

  defp after_send(act, {:ok, :stored}) do
    # The write's own `ok` is an acknowledgement, not a result: what it did to the party is
    # only known from the re-read, so the act keeps the verb and the target it will be judged
    # by (`settle/2`), and is never marked confirmed here.
    act
    |> Map.put(:state, :sent)
    |> Map.delete(:confirmed?)
    |> Map.delete(:reading)
  end

  defp after_send(_act, {:refused, sentence}), do: %{state: :refused, sentence: sentence}
  defp after_send(_act, {:error, sentence}), do: %{state: :error, sentence: sentence}

  # The re-read after a write is the same read that drew the party, settled against it: the
  # confirmation comes from this, not from the write.
  defp reread_party(socket) do
    BotRead.async(self(), :party, PartySelect.party_subject(), PartySelect.party_payload(),
      timeout: @call_timeout
    )

    socket
  end

  defp reread(socket) do
    BotRead.async(self(), :roster, PartySelect.roster_subject(), PartySelect.roster_payload(),
      timeout: @call_timeout
    )

    reread_party(socket)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <%= if page_error(@read_error, @read_failed_tag) do %>
      <.read_error reason={@read_error} />
    <% end %>

    <style>
      .party-select .chip { display: inline-block; padding: 2px 8px; border: 1px solid #2c3766; border-radius: 999px; font-size: 11px; margin-left: 6px; }
      .party-select .chip.narrating { border-color: #ff5fa2; color: #ffb3d1; }
      .party-select .row-buttons { display: flex; gap: 6px; flex-wrap: wrap; margin: 4px 0 10px; }
      .party-select .bot-id { font-size: 11px; color: #8b93b0; }
      .party-select .roster-row { display: flex; justify-content: space-between; align-items: center; gap: 8px; padding: 6px 0; border-top: 1px solid #1d2440; }
      .party-select .who { color: #ecf0f1; }
    </style>

    <div class="handheld-container with-nav party-select">
      <div class="phone-card">
        <div class="view-title">🧭 Building the party</div>

        <div class="card">
          <p class="dim" style="margin:0 0 8px; font-size:12px;">
            Who is with her, who could be, and who writes the turns. Nothing is sent until you
            confirm it.
          </p>
          <a href="/party-phone" class="read-note">← back to the window</a>
        </div>

        <div class="card">
          <div class="card-title">The party  who is with her</div>

          <%= case @party do %>
            <% {:party, %{members: []} = party} -> %>
              <p class="unreported"><%= empty_party(party.message) %></p>
            <% {:party, %{members: members} = party} -> %>
              <%= if party.message do %>
                <p class="dim" style="margin:0 0 8px; font-size:12px;"><%= party.message %></p>
              <% end %>
              <%= for row <- members do %>
                <div class="party-member">
                  <span class="who"><%= row.who %></span><%= if PartyWindow.narrates?(@narrator, row) do %><span class="chip narrating">narrating</span><% end %>
                  <%= if detail(row) != "" do %>
                    <span class="dim" style="font-size:11px;"> — <%= detail(row) %></span>
                  <% end %>
                  <div class="row-buttons">
                    <%= if row.id do %>
                      <%= if PartyWindow.narrates?(@narrator, row) do %>
                        <button phx-click="act" phx-value-verb="unname" phx-value-who="that narrator">
                          Let the bot write the turns again
                        </button>
                      <% else %>
                        <button
                          phx-click="act"
                          phx-value-verb="narrate"
                          phx-value-character_id={row.id}
                          phx-value-who={row.who}
                        >
                          Let this one write the turns
                        </button>
                      <% end %>
                      <button
                        phx-click="act"
                        phx-value-verb="dismiss"
                        phx-value-character_id={row.id}
                        phx-value-who={row.who}
                      >
                        Take out of the party
                      </button>
                    <% else %>
                      <p class="unreported" style="font-size:11px; margin:0;">
                        the bot sent this member with no character id, so this screen cannot act
                        on them
                      </p>
                    <% end %>
                  </div>
                </div>
              <% end %>
              <p class="dim" style="margin:6px 0 0; font-size:12px;"><%= narrator_line(@narrator, members) %></p>
            <% {:unreported, sentence} -> %>
              <p class="unreported"><%= sentence %></p>
            <% nil -> %>
              <p class="dim">Reading the party…</p>
          <% end %>

          <div style="margin-top:10px;">
            <button phx-click="refresh">Read it again</button>
          </div>
        </div>

        <div class="card">
          <div class="card-title">Who could join  the characters the bot has</div>

          <%= if roster_error(@read_error, @read_failed_tag) do %>
            <.read_error reason={@read_error} />
          <% else %>
            <%= case PartySelect.candidates(@roster, @party) do %>
              <% {:candidates, []} -> %>
                <p class="dim">Everyone the bot has a character for is already with her.</p>
              <% {:candidates, rows} -> %>
                <%= for candidate <- rows do %>
                  <div class="roster-row">
                    <div>
                      <span class="who"><%= candidate.name %></span>
                      <%= if detail(candidate) != "" do %>
                        <span class="dim" style="font-size:11px;"> — <%= detail(candidate) %></span>
                      <% end %>
                      <div class="bot-id"><%= candidate.bot_id %></div>
                    </div>
                    <button
                      phx-click="act"
                      phx-value-verb="recruit"
                      phx-value-bot_id={candidate.bot_id}
                      phx-value-who={candidate.name}
                    >
                      Recruit
                    </button>
                  </div>
                <% end %>
              <% {:unreported, sentence} -> %>
                <p class="unreported"><%= sentence %></p>
              <% nil -> %>
                <p class="dim">Reading the characters the bot has…</p>
            <% end %>
          <% end %>

          <p class="dim" style="margin:12px 0 4px; font-size:12px;">
            Or name a bot id. The bot makes it a character if it does not have one yet, so this
            works for a bot the roster has never heard of.
          </p>
          <form phx-change="bot_id" phx-submit="act">
            <input type="hidden" name="verb" value="recruit" />
            <input
              type="text"
              name="bot_id"
              value={@bot_id}
              maxlength={PartySelect.max_bot_id()}
              placeholder="gtd_bot"
              autocomplete="off"
            />
            <button type="submit">Recruit this bot</button>
          </form>
        </div>

        <%= if @act && @act[:state] == :review do %>
          <div class="card reply-confirm">
            <div class="card-title">Do this?  Back out and nothing is sent</div>
            <p class="dim" style="margin:0 0 8px;"><%= PartySelect.ask(@act) %></p>
            <button phx-click="send" style="margin-right:6px;">Yes, do it</button>
            <button phx-click="cancel">Don't</button>
          </div>
        <% end %>

        <%= if @act && @act[:state] != :review do %>
          <div class="card">
            <p class={PartySelect.class(@act)} style="margin:0; font-size:12px;">
              <%= PartySelect.line(@act) %>
            </p>
          </div>
        <% end %>
      </div>
    </div>

    <PhoneNav.nav current_route="/party-select-phone" />
    """
  end

  # Two reads on one screen means a failure belongs to one of them: an unanswered question
  # about the party may not report the characters as unread, and the other way round. The tag
  # is what tells them apart, so one failure is reported once — in the card it belongs to.
  defp page_error(nil, _tag), do: nil
  defp page_error(error, tag) when tag in [nil, :party], do: error
  defp page_error(_error, _tag), do: nil

  defp roster_error(nil, _tag), do: nil
  defp roster_error(error, :roster), do: error
  defp roster_error(_error, _tag), do: nil

  # A party of nobody is a reading the bot made, and its own sentence is drawn rather than a
  # second one invented here for the same fact — the blank party carries the way out in it.
  defp empty_party(message) when is_binary(message), do: message

  defp empty_party(_message),
    do: "The bot answered with an empty party, and said nothing about how to fill it."

  # The narrator is held by the bot as the character who writes the turns, so the name on the
  # line comes from the member that character is — and a party that names a narrator it did
  # not describe says that rather than drawing an id at her.
  defp narrator_line({:narrator, character_id}, members) do
    case Enum.find(members, &(&1.id == character_id)) do
      nil -> "A companion the bot did not describe writes the turns for the party."
      row -> "The turns are written by #{row.who}."
    end
  end

  defp narrator_line({:no_narrator, _nil}, _members),
    do: "Nobody writes the turns for the party — the bot narrates its own moves."

  defp narrator_line({:unreported, sentence}, _members), do: sentence
  defp narrator_line(_narrator, _members), do: "Reading who writes the turns…"

  # The class and the level, said together when both are there and separately when one is.
  defp detail(row) do
    case {row.class, row.level} do
      {nil, nil} -> ""
      {class, nil} -> class
      {nil, level} -> "level #{level}"
      {class, level} -> "#{class} · level #{level}"
    end
  end
end
