defmodule BotArmyDashboardLiveview.PartyPhoneLive do
  @moduledoc """
  The window she is in with the party: what gathered, who joined, and what has been said.

  The handheld had screens for how she is and none for what she is *in*. The party,
  the scene and the turns were already on the wire — `bot_army_rpg` has kept them
  since before this dashboard existed — and nothing here drew them, so the shelf
  had a place to be offered and no room to be offered in. This screen is that room:
  the open window, the party in it, the turns so far, and one box for the operator
  to say something into it.

  Reading is `BotArmyDashboardLiveview.PartyWindow`'s job, and it reads two
  subjects because a window and its party are two answers: `rpg.session.gather_context`
  opens the window (scene, theme, turns) and `rpg.session.state` names the party
  from the session's joined characters. The second is asked only once a window is
  open, and its failure is its own: a screen that cannot list the party is not a
  screen that cannot find the window.

  ## The shelf lives here now

  A phrase in the air is a moment, and this is where the moments are — so the shelf
  is drawn **inside the window** rather than on a page of its own. A call being open
  is still the shelf's own condition (`HypnosisShelf.open_call/1`: `:open`, `:none`,
  `:unreported`, three answers and not two), and it is asked on the same subject the
  house screen asks, so the two cannot disagree. What the window adds is the place:
  with no window open there is nothing to offer the shelf inside of, and this page
  says that rather than drawing a shelf on an empty page.

  ## A window opens with the story so far

  Every window used to open cold, because the domain only ever read turns per session
  and `rpg.session.start` always begins a new one. The bot now carries the earlier
  turns on the same window question (`carry_history`), and this screen draws them
  above the window's own turns — *previously in this story* — so walking into a new
  conversation is not walking into a blank page.

  The carry has its own three answers (`PartyWindow.history/1`): the turns that came
  before, `[]` for a bot that looked and found none, and `nil` for a bot that did not
  report them. The card draws all three differently, because *nothing came before* is
  a reading the bot made and *the bot did not say* is not.

  ## A reply is confirmed by the window, not by the write

  Saying something into the window is a write, and it is the only write on this
  screen. It is confirmed the way every write in this suite is: the bot's
  acknowledgement is not the sentence — the re-read is. `PartyWindow.settle/2`
  reports the reply said only if the window reads back with it among the turns, and
  a read that does not carry it says exactly that.

  The reply goes through a confirmation step before it is sent. The dashboard is
  open and proves nothing about who is holding the phone, so a reply is written as
  `source: "operator"` — the operator said it, never *she* said it — and the step
  in between is there so a mistyped turn is not a turn.
  """

  use Phoenix.LiveView

  alias Phoenix.PubSub

  import BotArmyDashboardLiveview.ReadError

  alias BotArmyDashboardLiveview.BotRead
  alias BotArmyDashboardLiveview.HypnosisShelf
  alias BotArmyDashboardLiveview.PartyWindow
  alias BotArmyDashboardLiveview.PhoneNav

  @call_timeout 3_000

  @impl true
  def mount(_params, _session, socket) do
    :ok = PubSub.subscribe(BotArmyDashboardLiveview.PubSub, "dashboard:hypnosis")

    BotRead.async(
      self(),
      :window,
      PartyWindow.context_subject(),
      PartyWindow.context_payload(),
      timeout: @call_timeout
    )

    # Whether a call is open, asked on the same subject the house screen asks it on so
    # the two cannot disagree. The shelf's card is handed the answer, and a page that
    # draws the shelf without ever asking is a page claiming a gate it never checked.
    BotRead.async(self(), :open_call, HypnosisShelf.call_subject(), %{}, timeout: @call_timeout)

    {:ok,
     socket
     |> HypnosisShelf.start()
     |> assign(open_call: nil)
     |> assign(window: nil)
     |> assign(window_sentence: nil)
     |> assign(party: nil)
     |> assign(reply: nil)
     |> assign(draft: "")}
  end

  # The window answered. A window opens the party read, which is the only dependent
  # read on this screen — and it is asked here rather than at mount because there is
  # no session to ask about until the window says so.
  @impl true
  def handle_info({:window, answer}, socket) do
    case PartyWindow.window(answer) do
      {:open_window, window} ->
        BotRead.async(
          self(),
          :party,
          PartyWindow.state_subject(),
          PartyWindow.state_payload(window.id),
          timeout: @call_timeout
        )

        {:noreply,
         socket
         |> assign(window: window)
         |> assign(window_sentence: nil)
         |> assign(party: nil)
         |> assign(reply: PartyWindow.settle(socket.assigns[:reply], window))}

      {_kind, sentence} ->
        {:noreply,
         socket
         |> assign(window: nil)
         |> assign(window_sentence: sentence)
         |> assign(party: nil)}
    end
  end

  @impl true
  def handle_info({:party, answer}, socket),
    do: {:noreply, assign(socket, party: PartyWindow.party(answer))}

  @impl true
  def handle_info({:hypnosis, answer}, socket), do: {:noreply, HypnosisShelf.info(socket, answer)}

  @impl true
  def handle_info({:open_call, answer}, socket),
    do: {:noreply, assign(socket, open_call: HypnosisShelf.open_call(answer))}

  @impl true
  def handle_info({:hypnosis_event, _subject, event}, socket),
    do: {:noreply, HypnosisShelf.said(socket, event)}

  # What is being typed. Nothing is sent on a keystroke; this only keeps the box's
  # own text so a re-render does not lose it.
  @impl true
  def handle_event("draft", %{"text" => text}, socket),
    do: {:noreply, assign(socket, draft: text)}

  # The confirmation step. The draft is refused here if this screen knows it is not a
  # turn — an empty box, or a reply past the ceiling — so the card that asks "send
  # this?" is never drawn for something that cannot be sent.
  @impl true
  def handle_event("review", %{"text" => text}, socket) do
    case PartyWindow.draft(text) do
      {:ok, draft} ->
        {:noreply,
         assign(socket, reply: %{text: draft, state: :review, confirmed?: false}, draft: draft)}

      {:refused, sentence} ->
        {:noreply, assign(socket, reply: %{state: :refused, sentence: sentence}, draft: text)}
    end
  end

  def handle_event("review", _params, socket),
    do: {:noreply, assign(socket, reply: %{state: :refused, sentence: empty_reply()})}

  # Backing out of the confirmation sends nothing.
  @impl true
  def handle_event("cancel", _params, socket), do: {:noreply, assign(socket, reply: nil)}

  # The one write on this screen, and it happens only from the confirmation card.
  @impl true
  def handle_event("send", _params, socket) do
    case {socket.assigns[:window], socket.assigns[:reply]} do
      {%{id: session_id}, %{state: :review, text: text}} ->
        {:noreply, socket |> assign(reply: sent_or_refused(session_id, text)) |> reread()}

      _other ->
        {:noreply,
         assign(socket, reply: %{state: :refused, sentence: "There is nothing to send."})}
    end
  end

  @impl true
  def handle_event("act", %{"verb" => "switch_off", "id" => id}, socket),
    do: {:noreply, HypnosisShelf.click(socket, :switch_off, id)}

  def handle_event("act", %{"verb" => "take_away", "id" => id}, socket),
    do: {:noreply, HypnosisShelf.click(socket, :take_away, id)}

  def handle_event("act", %{"verb" => "switch_off"}, socket),
    do: {:noreply, HypnosisShelf.click(socket, :switch_off, nil)}

  def handle_event("act", %{"verb" => "take_away"}, socket),
    do: {:noreply, HypnosisShelf.click(socket, :take_away, nil)}

  def handle_event("act", _params, socket),
    do: {:noreply, HypnosisShelf.click(socket, :unknown, nil)}

  defp sent_or_refused(session_id, text) do
    case PartyWindow.reply(session_id, text) do
      {:ok, :stored} -> %{text: text, state: :sent, confirmed?: false}
      {:refused, sentence} -> %{state: :refused, sentence: sentence}
      {:error, sentence} -> %{state: :error, sentence: sentence}
    end
  end

  # The re-read after a write is the same read that opened the window, settled
  # against it: the confirmation comes from this, not from the write.
  defp reread(socket) do
    BotRead.async(
      self(),
      :window,
      PartyWindow.context_subject(),
      PartyWindow.context_payload(),
      timeout: @call_timeout
    )

    socket
  end

  defp empty_reply, do: "There is nothing to say — an empty reply is not a turn."

  @impl true
  def render(assigns) do
    ~H"""
    <%= if page_error(@read_error, @read_failed_tag) do %>
      <.read_error reason={@read_error} />
    <% end %>

    <div class="handheld-container with-nav party-phone">
      <div class="phone-card">
        <div class="view-title">🎭 The window</div>

        <%= if @window do %>
          <div class="card">
            <div class="card-title">What is in front of the party</div>
            <p class="dim" style="margin:0; font-size:12px;">
              <%= scene_line(@window) %>
            </p>
            <%= if theme_line(@window) != "" do %>
              <p class="dim" style="margin:6px 0 0; font-size:12px;"><%= theme_line(@window) %></p>
            <% end %>
            <%= if character_line(@window) != "" do %>
              <p class="dim" style="margin:6px 0 0; font-size:12px;"><%= character_line(@window) %></p>
            <% end %>
          </div>

          <div class="card">
            <div class="card-title">The party  who joined the window</div>
            <%= case @party do %>
              <% {:party, []} -> %>
                <p class="unreported">Nobody has joined this window yet.</p>
              <% {:party, rows} -> %>
                <div class="row">
                  <%= for row <- rows do %>
                    <span><%= row.who %></span>
                  <% end %>
                </div>
              <% {:unreported, sentence} -> %>
                <p class="unreported"><%= sentence %></p>
              <% nil -> %>
                <%= if @read_failed_tag == :party do %>
                  <p class="unreported"><%= @read_error %></p>
                <% else %>
                  <p class="dim">Reading who is in the window…</p>
                <% end %>
            <% end %>
          </div>

          <div class="card">
            <div class="card-title">🗝 Previously in this story  what came before this window</div>
            <%= case PartyWindow.history(@window) do %>
              <% nil -> %>
                <p class="unreported">The bot did not report what came before this window.</p>
              <% [] -> %>
                <p class="unreported">Nothing came before this window — the story starts here.</p>
              <% rows -> %>
                <%= for row <- rows do %>
                  <p class="dim" style="margin:0 0 6px; font-size:12px;">
                    <span class="carry-who"><%= row.who %></span>: <%= row.text %>
                  </p>
                <% end %>
                <p class="read-note" style="margin:6px 0 0; font-size:11px;">
                  carried from the windows before this one
                </p>
            <% end %>
          </div>

          <div class="card">
            <div class="card-title">What has been said  oldest first</div>
            <%= case PartyWindow.turns(@window) do %>
              <% nil -> %>
                <p class="unreported">The bot did not report what has been said in this window.</p>
              <% [] -> %>
                <p class="unreported">Nothing has been said in this window yet.</p>
              <% turns -> %>
                <%= for turn <- turns do %>
                  <p class="dim" style="margin:0 0 6px; font-size:12px;"><%= turn %></p>
                <% end %>
            <% end %>
          </div>

          <div class="card">
            <div class="card-title">Say something into the window  nothing is sent until you confirm</div>
            <form phx-change="draft" phx-submit="review" class="reply-form">
              <textarea name="text" rows="2" maxlength={PartyWindow.max_reply()} placeholder="Say something into the window…" class="reply-box"><%= @draft %></textarea>
              <button type="submit" class="reply-review">Review it — nothing is sent yet</button>
            </form>

            <%= if @reply && @reply[:state] == :review do %>
              <div class="card reply-confirm">
                <div class="card-title">Send this?  Back out and nothing is sent</div>
                <p class="dim" style="margin:0 0 8px;"><%= @reply.text %></p>
                <button phx-click="send" class="reply-send" style="margin-right:6px;">
                  Send it into the window
                </button>
                <button phx-click="cancel" class="reply-cancel">Don't send it</button>
              </div>
            <% end %>

            <%= if @reply && @reply[:state] != :review do %>
              <p class={PartyWindow.class(@reply)} style="margin:8px 0 0; font-size:12px;">
                <%= PartyWindow.line(@reply) %>
              </p>
            <% end %>
          </div>

          <div class="card">
            <%= if @open_call != :none do %>
              <div class="card-title">🌀 Her shelf  offered inside this window</div>
            <% end %>
            <HypnosisShelf.card
              shelf={@shelf}
              act={@act}
              read_error={shelf_error(@read_error, @read_failed_tag)}
              said={@said}
              open_call={@open_call}
            />
            <%= if window_line(@open_call, @read_error, @read_failed_tag) != "" do %>
              <p style="color:#8b93b0; font-size:12px; margin:8px 0 0; text-align:center;">
                <%= window_line(@open_call, @read_error, @read_failed_tag) %>
              </p>
            <% end %>
          </div>
        <% else %>
          <div class="card">
            <p class="unreported"><%= window_sentence(@window_sentence, @read_error, @read_failed_tag) %></p>
            <p class="read-note" style="margin-top:8px;">
              The shelf is offered inside an open window, so with no window open there is nothing
              here to offer it inside of.
            </p>
          </div>
        <% end %>
      </div>
    </div>

    <PhoneNav.nav current_route="/party-phone" />
    """
  end

  # Three reads on one screen means a failure belongs to one of them: an unanswered
  # question about the window may not report the shelf as unread, and the other way
  # round. The tag is what tells them apart — and each card carries the failure of
  # its own read, so one failure is reported once.
  defp page_error(nil, _tag), do: nil
  defp page_error(error, tag) when tag in [nil, :hypnosis], do: error
  defp page_error(_error, _tag), do: nil

  defp shelf_error(nil, _tag), do: nil
  defp shelf_error(error, tag) when tag in [nil, :hypnosis], do: error
  defp shelf_error(_error, _tag), do: nil

  # The window's own sentence: what the bot said, what the failure said, or that the
  # question is still out. A failed read is not still in flight.
  defp window_sentence(sentence, _read_error, _tag) when is_binary(sentence), do: sentence
  defp window_sentence(_sentence, read_error, :window) when not is_nil(read_error), do: read_error
  defp window_sentence(_sentence, _read_error, _tag), do: "Reading whether a window is open…"

  defp scene_line(%{scene: scene}) when is_binary(scene), do: scene

  defp scene_line(_window),
    do: "The window is open, but the bot did not send a scene description."

  defp theme_line(%{theme: %{setting: setting, tone: tone}}) do
    "Setting: " <> setting <> if(is_binary(tone), do: " · tone: " <> tone, else: "")
  end

  defp theme_line(_window), do: ""

  defp character_line(%{character: %{name: name} = character}) do
    class = if is_binary(character[:class]), do: " · " <> character[:class], else: ""

    level =
      if is_integer(character[:level]), do: " · level " <> to_string(character[:level]), else: ""

    "You are in it as " <> name <> class <> level
  end

  defp character_line(_window), do: ""

  defp window_line(:open, _read_error, _failed_tag),
    do: "A call is open, and the shelf is offered here while one is."

  defp window_line(:none, _read_error, _failed_tag), do: ""

  defp window_line(:unreported, _read_error, _failed_tag),
    do:
      "The bot did not say whether a call is open, so this screen is not claiming a window — it is showing the shelf it read."

  defp window_line(nil, read_error, :open_call) when not is_nil(read_error),
    do:
      "The question about an open call did not come back, so this screen is not claiming a window."

  defp window_line(nil, _read_error, _failed_tag), do: "Asking the house whether a call is open…"
end
