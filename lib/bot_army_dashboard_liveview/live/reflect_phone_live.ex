defmodule BotArmyDashboardLiveview.ReflectPhoneLive do
  use Phoenix.LiveView
  alias Phoenix.PubSub
  alias BotArmyDashboardLiveview.BotRead
  alias BotArmyDashboardLiveview.PhoneNav
  alias BotArmyDashboardLiveview.ReflectionWindow
  alias BotArmyDashboardLiveview.SyncStatus

  import BotArmyDashboardLiveview.ReadError

  # How long a round trip to the companion may take. A reflection is a small
  # write and the store answers in milliseconds; this is a ceiling, not an
  # expectation. A write that times out is not retried — see `save_reflection/1`.
  @call_timeout 10_000

  @prompts [
    "What just happened?",
    "What did you finish?",
    "Key insight from this session?",
    "How are you feeling right now?",
    "What surprised you?",
    "One thing that went well?",
    "What's on your mind?",
    "What did you learn?",
    "How would you describe this moment?",
    "What's the story here?"
  ]

  @impl true
  def mount(_params, _session, socket) do
    :ok = PubSub.subscribe(BotArmyDashboardLiveview.PubSub, "gamepad")

    # The bell for a finished answer. It carries the job, never the words.
    :ok = PubSub.subscribe(BotArmyDashboardLiveview.PubSub, "dashboard:reflections")

    # The first read: what the store already holds. A screen that only reads after
    # a write has no way to show her that her earlier words are still there.
    BotRead.async(
      self(),
      :recent,
      ReflectionWindow.list_subject(),
      ReflectionWindow.list_payload(),
      timeout: @call_timeout
    )

    socket =
      socket
      |> assign(
        sync_status: SyncStatus.initial(),
        is_online: true,
        reflection_text: "",
        prompts: @prompts,
        prompt_index: Enum.random(0..(length(@prompts) - 1)),
        prompt: Enum.at(@prompts, Enum.random(0..(length(@prompts) - 1))),
        message: nil,
        character_intro: "Let's capture this moment.",
        # The confirmation card: `nil` until a draft is reviewed, `:confirmed`
        # when the words are on the card waiting for the second press.
        confirm: nil,
        # The row the store wrote, read back. The success line is drawn from this
        # and never from the write's own ok.
        saved: nil,
        # This draft's key. Held across sends so that a second press while the
        # first is still in flight is the same draft, not a second reflection;
        # a new one is minted only once the store says it holds the words.
        dedupe_key: ReflectionWindow.new_dedupe_key(),
        # The recent list: `nil` until a read comes back, a list when it does.
        recent: nil,
        # A refusal from the store, for the write and for the list, kept apart so
        # neither is reported as the other.
        refusal: nil,
        list_refusal: nil,
        # The waiting state: one poll chain while an answer is owed.
        polling: false,
        waiting_since: nil
      )
      |> schedule_tick()

    {:ok, socket}
  end

  defp schedule_tick(socket) do
    Process.send_after(self(), :tick, 500)
    socket
  end

  @impl true
  def handle_info(:tick, socket) do
    {:noreply, schedule_tick(socket)}
  end

  # Two presses, because her words are the one thing here that cannot be retyped
  # from memory: the first press puts them on a confirmation card, the second
  # writes them. Nothing is sent on a keystroke.
  @impl true
  def handle_event("gamepad-a", _params, socket) do
    case socket.assigns[:confirm] do
      nil -> review_draft(socket)
      :confirmed -> save_reflection(socket)
    end
  end

  @impl true
  def handle_event("gamepad-b", _params, socket) do
    case socket.assigns[:confirm] do
      nil -> {:noreply, assign(socket, reflection_text: "", message: nil, refusal: nil)}
      :confirmed -> {:noreply, assign(socket, confirm: nil, message: "Not saved.")}
    end
  end

  @impl true
  def handle_event("reread", _params, socket), do: {:noreply, reread(socket)}

  @impl true
  def handle_event("gamepad-up", _params, socket) do
    prompts = socket.assigns.prompts
    idx = socket.assigns.prompt_index
    new_idx = max(idx - 1, 0)
    new_prompt = Enum.at(prompts, new_idx)
    {:noreply, assign(socket, prompt_index: new_idx, prompt: new_prompt, message: nil)}
  end

  @impl true
  def handle_event("gamepad-down", _params, socket) do
    prompts = socket.assigns.prompts
    idx = socket.assigns.prompt_index
    new_idx = min(idx + 1, length(prompts) - 1)
    new_prompt = Enum.at(prompts, new_idx)
    {:noreply, assign(socket, prompt_index: new_idx, prompt: new_prompt, message: nil)}
  end

  @impl true
  def handle_event("update-reflection", %{"reflection" => text}, socket) do
    {:noreply, assign(socket, reflection_text: text, message: nil)}
  end

  # Touch handlers
  @impl true
  def handle_event("swipe-up", _params, socket) do
    handle_event("gamepad-up", %{}, socket)
  end

  @impl true
  def handle_event("swipe-down", _params, socket) do
    handle_event("gamepad-down", %{}, socket)
  end

  @impl true
  def handle_event("tap", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("long-press", _params, socket) do
    {:noreply, socket}
  end

  defp review_draft(socket) do
    case ReflectionWindow.draft(socket.assigns.reflection_text) do
      {:ok, text} ->
        {:noreply, assign(socket, confirm: :confirmed, reflection_text: text, message: nil)}

      {:refused, sentence} ->
        {:noreply,
         socket
         |> assign(confirm: nil, refusal: nil, message: sentence)
         |> schedule_message_clear(3_000)}
    end
  end

  # The one write on this screen, and it happens only past the confirmation card.
  # A write is never retried: if this does not come back, the screen says so and
  # waits for a human, because a reflection written twice is worse than one that
  # has to be written again.
  defp save_reflection(socket) do
    BotRead.async(
      self(),
      :capture,
      ReflectionWindow.capture_subject(),
      ReflectionWindow.capture_payload(
        socket.assigns.reflection_text,
        socket.assigns.prompt,
        socket.assigns.dedupe_key
      ),
      timeout: @call_timeout
    )

    {:noreply,
     socket
     |> assign(message: "Saving…")
     |> schedule_message_clear(2_000)}
  end

  # The write came back: with the row the store wrote, or with the store's own
  # refusal. "Saved" is drawn only for the first, and the box is cleared only once
  # the store holds the words.
  @impl true
  def handle_info({:capture, answer}, socket) do
    case ReflectionWindow.capture(answer) do
      {:stored, row} ->
        {:noreply,
         socket
         |> assign(
           saved: row,
           reflection_text: "",
           confirm: nil,
           refusal: nil,
           message: "Saved — the store has your words.",
           # These words are kept now, so the next draft is a different one and
           # needs its own key. A refusal keeps the old key on purpose: the words
           # are still on the card, and re-pressing is re-sending that draft.
           dedupe_key: ReflectionWindow.new_dedupe_key()
         )
         |> next_prompt()
         |> reread()
         |> schedule_message_clear(4_000)}

      {:refused, sentence} ->
        # The card stays up: the words are still in the box, and the store's
        # refusal is shown where the confirmation was.
        {:noreply, assign(socket, confirm: :confirmed, refusal: sentence, message: nil)}
    end
  end

  # The list read answered: rows, or the store's refusal. `[]` is a reading;
  # a refusal is not a list and is never drawn as one.
  @impl true
  def handle_info({:recent, answer}, socket) do
    case ReflectionWindow.recent(answer) do
      {:recent, rows} ->
        {:noreply, socket |> assign(recent: rows, list_refusal: nil) |> start_poll_if_owed()}

      {:refused, sentence} ->
        {:noreply, assign(socket, recent: nil, list_refusal: sentence)}
    end
  end

  # The single re-read of the row just saved — the diff that confirms the write.
  # A refusal here is not news about the store: the list read is the reading, and
  # a single row that is not there yet does not take the saved card away.
  @impl true
  def handle_info({:reflection, answer}, socket) do
    case ReflectionWindow.one(answer) do
      {:reflection, row} -> {:noreply, socket |> assign(saved: row) |> start_poll_if_owed()}
      {:refused, _sentence} -> {:noreply, socket}
    end
  end

  # A job finished. The bell carries the job, never the words; this only decides
  # whether re-reading is worth doing.
  @impl true
  def handle_info({:answer_event, _subject, _event}, socket) do
    if owes_answer?(socket), do: {:noreply, reread(socket)}, else: {:noreply, socket}
  end

  # The fallback cadence: only while an answer is owed, and only inside the lane's
  # own budget. A poll that finds nothing owed stops the chain.
  @impl true
  def handle_info(:poll, socket) do
    if owes_answer?(socket) and within_budget?(socket) do
      Process.send_after(self(), :poll, ReflectionWindow.poll_ms())
      {:noreply, reread(socket)}
    else
      {:noreply, assign(socket, polling: false, waiting_since: nil)}
    end
  end

  # The same read that was asked at mount, asked again: the screen's own answer is
  # whatever this comes back with.
  defp reread(socket) do
    BotRead.async(
      self(),
      :recent,
      ReflectionWindow.list_subject(),
      ReflectionWindow.list_payload(),
      timeout: @call_timeout
    )

    read_saved(socket)
  end

  defp read_saved(socket) do
    case socket.assigns[:saved] do
      %{id: id} when is_binary(id) ->
        BotRead.async(
          self(),
          :reflection,
          ReflectionWindow.read_subject(),
          ReflectionWindow.read_payload(id),
          timeout: @call_timeout
        )

        socket

      _other ->
        socket
    end
  end

  defp owes_answer?(socket) do
    ReflectionWindow.awaits_answer?(socket.assigns[:saved]) or
      ReflectionWindow.awaiting_any?(socket.assigns[:recent])
  end

  # One poll chain, and only while something is owed: starting again while it is
  # already running would double the cadence on every event.
  defp start_poll_if_owed(socket) do
    if owes_answer?(socket) do
      socket =
        if socket.assigns[:waiting_since] do
          socket
        else
          assign(socket, waiting_since: System.monotonic_time(:millisecond))
        end

      if socket.assigns[:polling] do
        socket
      else
        Process.send_after(self(), :poll, ReflectionWindow.poll_ms())
        assign(socket, polling: true)
      end
    else
      assign(socket, waiting_since: nil)
    end
  end

  defp within_budget?(socket) do
    case socket.assigns[:waiting_since] do
      nil ->
        true

      since ->
        System.monotonic_time(:millisecond) - since < ReflectionWindow.pending_budget_ms()
    end
  end

  defp next_prompt(socket) do
    new_idx = Enum.random(0..(length(socket.assigns.prompts) - 1))

    assign(socket,
      prompt_index: new_idx,
      prompt: Enum.at(socket.assigns.prompts, new_idx)
    )
  end

  defp schedule_message_clear(socket, delay_ms) do
    Process.send_after(self(), :clear_message, delay_ms)
    socket
  end

  @impl true
  def handle_info(:clear_message, socket) do
    {:noreply, assign(socket, message: nil)}
  end

  @impl true
  def handle_event("sync-queue-online", _params, socket) do
    {:noreply, assign(socket, is_online: true)}
  end

  @impl true
  def handle_event("sync-queue-offline", _params, socket) do
    {:noreply, assign(socket, is_online: false)}
  end

  @impl true
  def handle_event("sync-status-update", %{"status" => status}, socket) do
    {:noreply, assign(socket, sync_status: status)}
  end

  @impl true
  def handle_event("sync-queue-retry", _params, socket) do
    BotArmyDashboardLiveview.OfflineQueue.flush_queue(
      socket.assigns.socket_id,
      fn subject, payload ->
        Gnat.pub(:nats_connection, subject, payload)
      end
    )

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="reflect-phone-container" class="handheld-container reflect-phone" phx-hook="TouchCarousel">
      <div id="offline-hook" phx-hook="OfflineDetectionHook" style="display: none;"></div>
      <div id="sync-manager-hook" phx-hook="SyncManagerHook" style="display: none;"></div>
      <SyncStatus.sync_status status={@sync_status} is_online={@is_online} />
      <div class="phone-card reflection-card-phone">
        <div class="view-title">📝 Reflection · Y: save · B: clear</div>

        <%= if @read_error do %>
          <.read_error reason={@read_error} />
        <% end %>

        <div class="character-intro-phone">
          <p><%= @character_intro %></p>
        </div>

        <div class="prompt-carousel-phone">
          <div class="carousel-hint-small">swipe ↑ ↓ to change</div>
          <div class="prompt-phone"><%= @prompt %></div>
          <div class="prompt-indicator">
            <%= @prompt_index + 1 %> of <%= length(@prompts) %>
          </div>
        </div>

        <div class="input-section-phone">
          <textarea
            id="reflection-input-phone"
            class="reflection-input-phone"
            phx-change="update-reflection"
            phx-value-reflection={@reflection_text}
            placeholder="Write your reflection here..."
            autocomplete="off"
          ><%= @reflection_text %></textarea>
        </div>

        <div class="char-count-phone">
          <span><%= String.length(@reflection_text) %> characters</span>
        </div>

        <div class="controls">
          <div class="control-hint">
            <span class="key">Y</span>
            <span class="action"><%= if @confirm, do: "Confirm — save this", else: "Save" %></span>
          </div>
          <div class="control-hint">
            <span class="key">B</span>
            <span class="action"><%= if @confirm, do: "Back — don't save", else: "Clear" %></span>
          </div>
        </div>

        <%= if @confirm do %>
          <div class="confirm-card-phone">
            <p class="confirm-title">Save this reflection?</p>
            <p class="confirm-body"><%= @reflection_text %></p>
            <p class="confirm-hint">Y to save · B to go back</p>
          </div>
        <% end %>

        <%= if @refusal do %>
          <div class="refusal-phone" role="status">
            <p class="refusal-title">Nothing was saved</p>
            <p class="refusal-body"><%= @refusal %></p>
          </div>
        <% end %>

        <%= if @saved do %>
          <div class="saved-card-phone">
            <p class="saved-title">Just saved</p>
            <p class="saved-text"><%= @saved.text %></p>
            <p class="saved-answer"><%= ReflectionWindow.answer_line(@saved.answer) %></p>
          </div>
        <% end %>

        <div class="earlier-phone">
          <p class="earlier-title">
            Earlier <%= if is_list(@recent), do: "(#{length(@recent)})", else: "" %>
            <span class="earlier-refresh" phx-click="reread">↻ re-read</span>
          </p>

          <%= if @list_refusal do %>
            <div class="refusal-phone" role="status">
              <p class="refusal-title">Your earlier reflections are not shown</p>
              <p class="refusal-body"><%= @list_refusal %></p>
            </div>
          <% else %>
            <%= if @recent == [] do %>
              <p class="empty-state">Nothing written yet — write a line above and it lands here.</p>
            <% end %>
            <%= for row <- @recent || [] do %>
              <div class="earlier-row">
                <p class="earlier-text"><%= row.text %></p>
                <p class="earlier-answer"><%= ReflectionWindow.answer_line(row.answer) %></p>
              </div>
            <% end %>
          <% end %>
        </div>

        <div class="hint-text-phone">
          <p>✨ Your reflections shape the narrative</p>
        </div>
      </div>

      <%= if @message do %>
        <div class="message"><%= @message %></div>
      <% end %>
    </div>

    <PhoneNav.nav current_route="/reflect-phone" />

    <style>
      .reflect-phone {
        background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
      }

      .reflection-card-phone {
        background: rgba(0, 0, 0, 0.5);
        border: 2px solid #6b7fd7;
        border-radius: 12px;
        padding: 20px;
        display: flex;
        flex-direction: column;
        gap: 15px;
      }

      .view-title {
        font-size: 20px;
        font-weight: bold;
        color: #6b7fd7;
        text-align: center;
      }

      .character-intro-phone {
        background: rgba(107, 127, 215, 0.1);
        border-left: 3px solid #6b7fd7;
        padding: 12px 15px;
        border-radius: 4px;
        font-size: 13px;
        color: #b0b0b0;
        font-style: italic;
      }

      .character-intro-phone p {
        margin: 0;
        line-height: 1.5;
      }

      .prompt-carousel-phone {
        text-align: center;
      }

      .carousel-hint-small {
        font-size: 11px;
        color: #606060;
        text-transform: uppercase;
        letter-spacing: 1px;
        margin-bottom: 8px;
      }

      .prompt-phone {
        font-size: 20px;
        font-weight: bold;
        color: #ecf0f1;
        margin: 15px 0;
        line-height: 1.5;
        word-wrap: break-word;
        animation: fadeIn 0.3s ease;
      }

      @keyframes fadeIn {
        from {
          opacity: 0;
        }
        to {
          opacity: 1;
        }
      }

      .prompt-indicator {
        font-size: 11px;
        color: #707070;
      }

      .input-section-phone {
        flex-grow: 1;
        display: flex;
        flex-direction: column;
      }

      .reflection-input-phone {
        background: rgba(0, 0, 0, 0.3);
        border: 1px solid #6b7fd7;
        border-radius: 6px;
        padding: 12px;
        color: #ecf0f1;
        font-family: "Courier New", monospace;
        font-size: 14px;
        resize: vertical;
        min-height: 120px;
        line-height: 1.5;
      }

      .reflection-input-phone::placeholder {
        color: #606060;
      }

      .reflection-input-phone:focus {
        outline: none;
        border-color: #8a9eff;
        background: rgba(107, 127, 215, 0.1);
      }

      .char-count-phone {
        font-size: 11px;
        color: #707070;
        text-align: right;
      }

      .controls {
        display: flex;
        flex-direction: column;
        gap: 8px;
        border-top: 1px solid #333;
        border-bottom: 1px solid #333;
        padding: 12px 0;
      }

      .control-hint {
        display: flex;
        justify-content: space-between;
        align-items: center;
        padding: 10px;
        font-size: 13px;
        min-height: 44px;
      }

      .control-hint .key {
        background: #6b7fd7;
        color: #1a1a2e;
        padding: 6px 10px;
        border-radius: 4px;
        font-weight: bold;
        min-width: 45px;
        text-align: center;
      }

      .control-hint .action {
        flex-grow: 1;
        text-align: right;
        color: #ecf0f1;
        margin-right: 10px;
      }

      .hint-text-phone {
        text-align: center;
        font-size: 12px;
        color: #707070;
        font-style: italic;
      }

      .hint-text-phone p {
        margin: 0;
      }

      .message {
        position: fixed;
        bottom: 20px;
        left: 10px;
        right: 10px;
        background: rgba(107, 127, 215, 0.2);
        border: 1px solid #6b7fd7;
        padding: 12px;
        border-radius: 4px;
        color: #ecf0f1;
        text-align: center;
        font-size: 13px;
        animation: slideUp 0.3s ease;
      }

      @keyframes slideUp {
        from {
          opacity: 0;
          transform: translateY(20px);
        }
        to {
          opacity: 1;
          transform: translateY(0);
        }
      }

      .confirm-card-phone,
      .saved-card-phone,
      .earlier-phone {
        background: rgba(107, 127, 215, 0.12);
        border-left: 3px solid #6b7fd7;
        border-radius: 6px;
        padding: 12px 14px;
        display: flex;
        flex-direction: column;
        gap: 8px;
      }

      .confirm-title,
      .saved-title,
      .earlier-title {
        font-size: 12px;
        font-weight: bold;
        color: #6b7fd7;
        text-transform: uppercase;
        letter-spacing: 1px;
        margin: 0;
      }

      .confirm-body {
        font-size: 15px;
        color: #ecf0f1;
        margin: 0;
        word-wrap: break-word;
      }

      .confirm-hint,
      .earlier-refresh {
        font-size: 11px;
        color: #8a9eff;
        margin: 0;
      }

      .earlier-title {
        display: flex;
        justify-content: space-between;
        align-items: center;
      }

      .earlier-refresh {
        cursor: pointer;
        text-transform: none;
        letter-spacing: 0;
      }

      .saved-text,
      .earlier-text {
        font-size: 14px;
        color: #ecf0f1;
        margin: 0;
        word-wrap: break-word;
      }

      .saved-answer,
      .earlier-answer {
        font-size: 13px;
        color: #b0b0b0;
        font-style: italic;
        margin: 0;
      }

      .earlier-row {
        border-top: 1px solid rgba(107, 127, 215, 0.3);
        padding-top: 8px;
        display: flex;
        flex-direction: column;
        gap: 4px;
      }

      .refusal-phone {
        background: rgba(215, 107, 107, 0.12);
        border-left: 3px solid #d76b6b;
        border-radius: 6px;
        padding: 12px 14px;
      }

      .refusal-title {
        font-size: 12px;
        font-weight: bold;
        color: #d76b6b;
        text-transform: uppercase;
        letter-spacing: 1px;
        margin: 0 0 4px 0;
      }

      .refusal-body {
        font-size: 13px;
        color: #ecf0f1;
        margin: 0;
      }

      @media (max-width: 768px) {
        .reflection-card-phone {
          padding: 15px;
        }

        .prompt-phone {
          font-size: 18px;
        }

        .reflection-input-phone {
          min-height: 100px;
          font-size: 16px; /* Prevents iOS zoom */
        }

        .control-hint {
          min-height: 48px;
        }
      }
    </style>
    """
  end
end
