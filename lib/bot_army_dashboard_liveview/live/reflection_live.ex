defmodule BotArmyDashboardLiveview.ReflectionLive do
  @moduledoc """
  The reflection desk: write a line, and see what became of it.

  This screen used to publish `events.reflection.captured` and print "✓ Reflection
  captured. The story continues." on the broker's `:ok` — a claim about the store
  made by a screen that had only watched the bytes leave. It could not show her that
  her words landed, could not show the companion's answer, and could not tell a
  refusal from a success.

  It now goes through the store's own request subjects, through `ReflectionWindow`
  for every interpretation, and shows the confirmation that comes back: the row the
  store wrote, the re-read of that row, and the recent list. A refusal keeps her
  words and says what the store said. A read that failed says it failed.
  """

  use Phoenix.LiveView

  import BotArmyDashboardLiveview.ReadError

  alias BotArmyDashboardLiveview.BotRead
  alias BotArmyDashboardLiveview.ReflectionWindow
  alias Phoenix.PubSub

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

  # The store answers on the database; ten seconds is what the phone allows, and the
  # desk is the same lane.
  @call_timeout 10_000

  @impl true
  def mount(_params, _session, socket) do
    :ok = PubSub.subscribe(BotArmyDashboardLiveview.PubSub, "gamepad")

    # The bell for a finished answer. It carries the job, never the words.
    :ok = PubSub.subscribe(BotArmyDashboardLiveview.PubSub, "dashboard:reflections")

    # The first read: what the store already holds, so the desk can show her that her
    # earlier words are still there.
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
        reflection_text: "",
        prompt: Enum.random(@prompts),
        message: nil,
        character_intro: "Let's capture this moment.",
        # The confirmation card: `nil` until a draft is reviewed, `:confirmed` while
        # the words wait for the second press.
        confirm: nil,
        # The row the store wrote, read back. The success line is drawn from this,
        # never from the write's own ok.
        saved: nil,
        # The recent list: `nil` until a read comes back, a list when it does.
        recent: nil,
        # The store's own refusals, kept apart: one for the write, one for the list.
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

  # Two presses, because her words cannot be retyped from memory: the first press
  # puts them on a confirmation card, the second writes. Nothing is sent on a
  # keystroke.
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
  def handle_event("update-reflection", %{"reflection" => text}, socket) do
    {:noreply, assign(socket, reflection_text: text, message: nil)}
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
  # waits for a human, because a reflection written twice is worse than one that has
  # to be written again.
  defp save_reflection(socket) do
    BotRead.async(
      self(),
      :capture,
      ReflectionWindow.capture_subject(),
      ReflectionWindow.capture_payload(socket.assigns.reflection_text, socket.assigns.prompt),
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
           message: "Saved — the store has your words."
         )
         |> next_prompt()
         |> reread()
         |> schedule_message_clear(4_000)}

      {:refused, sentence} ->
        # The card stays up: the words are still in the box, and the store's own
        # refusal is shown where the confirmation was.
        {:noreply, assign(socket, confirm: :confirmed, refusal: sentence, message: nil)}
    end
  end

  # The list read answered: rows, or the store's refusal. `[]` is a reading; a
  # refusal is not a list and is never drawn as one.
  @impl true
  def handle_info({:recent, answer}, socket) do
    case ReflectionWindow.recent(answer) do
      {:recent, rows} ->
        {:noreply, socket |> assign(recent: rows, list_refusal: nil) |> start_poll_if_owed()}

      {:refused, sentence} ->
        {:noreply, assign(socket, recent: nil, list_refusal: sentence)}
    end
  end

  # The single re-read of the row just saved — the diff that confirms the write. A
  # refusal here is not news about the store: the list read is the reading, and a
  # single row that is not there yet does not take the saved card away.
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

  @impl true
  def handle_info(:tick, socket) do
    {:noreply, schedule_tick(socket)}
  end

  @impl true
  def handle_info(:clear_message, socket) do
    {:noreply, assign(socket, message: nil)}
  end

  # The same read that was asked at mount, asked again: the desk's own answer is
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
    assign(socket, prompt: Enum.random(@prompts))
  end

  defp schedule_message_clear(socket, delay_ms) do
    Process.send_after(self(), :clear_message, delay_ms)
    socket
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="handheld-container reflection">
      <div class="reflection-card">
        <div class="view-title">📝 Reflection · Y: save · B: clear</div>

        <div class="character-intro">
          <p><%= @character_intro %></p>
        </div>

        <div class="prompt-section">
          <div class="prompt"><%= @prompt %></div>
        </div>

        <div class="input-section">
          <textarea
            id="reflection-input"
            class="reflection-input"
            phx-change="update-reflection"
            phx-value-reflection={@reflection_text}
            placeholder="Write your reflection here..."
            autocomplete="off"
          ><%= @reflection_text %></textarea>
        </div>

        <div class="char-count">
          <span><%= String.length(@reflection_text) %> characters</span>
        </div>

        <div class="controls">
          <div class="control-hint">
            <span class="key">Y</span>
            <span class="action"><%= if @confirm, do: "Save it now", else: "Save Reflection" %></span>
          </div>
          <div class="control-hint">
            <span class="key">B</span>
            <span class="action"><%= if @confirm, do: "Back", else: "Clear" %></span>
          </div>
        </div>

        <%= if @read_error do %>
          <.read_error reason={@read_error} />
        <% end %>

        <%= if @confirm do %>
          <div class="confirm-card" role="status">
            <p class="confirm-title">Save this reflection?</p>
            <p class="confirm-body"><%= @reflection_text %></p>
            <p class="confirm-hint">Y saves it. B goes back to it.</p>
          </div>
        <% end %>

        <%= if @refusal do %>
          <div class="refusal-card" role="status">
            <p class="refusal-title">Nothing was saved</p>
            <p class="refusal-body"><%= @refusal %></p>
          </div>
        <% end %>

        <%= if @saved do %>
          <div class="saved-card">
            <p class="saved-title">Just saved</p>
            <p class="saved-text"><%= @saved.text %></p>
            <p class="saved-answer"><%= ReflectionWindow.answer_line(@saved.answer) %></p>
          </div>
        <% end %>

        <div class="earlier">
          <p class="earlier-title">
            Earlier <%= if is_list(@recent), do: "(#{length(@recent)})", else: "" %>
            <span class="earlier-refresh" phx-click="reread">↻ re-read</span>
          </p>

          <%= if @list_refusal do %>
            <div class="refusal-card" role="status">
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

        <div class="hint-text">
          <p>✨ Your reflections shape the narrative</p>
        </div>
      </div>

      <%= if @message do %>
        <div class="message"><%= @message %></div>
      <% end %>
    </div>

    <style>
      .handheld-container {
        width: 100%;
        height: 100vh;
        background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        color: #ecf0f1;
        font-family: "Courier New", monospace;
        padding: 20px;
        box-sizing: border-box;
        overflow-y: auto;
      }

      .reflection-card {
        background: rgba(0, 0, 0, 0.5);
        border: 2px solid #6b7fd7;
        border-radius: 8px;
        padding: 30px;
        width: 100%;
        max-width: 500px;
        box-shadow: 0 8px 32px rgba(107, 127, 215, 0.1);
        display: flex;
        flex-direction: column;
        gap: 20px;
      }

      .view-title {
        font-size: 22px;
        font-weight: bold;
        color: #6b7fd7;
        text-align: center;
      }

      .character-intro {
        background: rgba(107, 127, 215, 0.1);
        border-left: 3px solid #6b7fd7;
        padding: 12px 15px;
        border-radius: 4px;
        font-size: 14px;
        color: #b0b0b0;
        font-style: italic;
      }

      .character-intro p {
        margin: 0;
        line-height: 1.5;
      }

      .prompt-section {
        margin: 10px 0;
      }

      .prompt {
        font-size: 18px;
        font-weight: bold;
        color: #ecf0f1;
        text-align: center;
        line-height: 1.6;
      }

      .input-section {
        flex-grow: 1;
        display: flex;
        flex-direction: column;
      }

      .reflection-input {
        background: rgba(0, 0, 0, 0.3);
        border: 1px solid #6b7fd7;
        border-radius: 4px;
        padding: 15px;
        color: #ecf0f1;
        font-family: "Courier New", monospace;
        font-size: 14px;
        resize: vertical;
        min-height: 120px;
        max-height: 300px;
        line-height: 1.5;
      }

      .reflection-input::placeholder {
        color: #606060;
      }

      .reflection-input:focus {
        outline: none;
        border-color: #8a9eff;
        background: rgba(107, 127, 215, 0.1);
      }

      .char-count {
        font-size: 12px;
        color: #707070;
        text-align: right;
        margin: -5px 0 5px 0;
      }

      .controls {
        border-top: 1px solid #333;
        border-bottom: 1px solid #333;
        padding: 15px 0;
      }

      .control-hint {
        display: flex;
        justify-content: space-between;
        align-items: center;
        margin: 10px 0;
        font-size: 14px;
      }

      .control-hint .key {
        background: #6b7fd7;
        color: #1a1a2e;
        padding: 4px 8px;
        border-radius: 4px;
        font-weight: bold;
        min-width: 40px;
        text-align: center;
      }

      .control-hint .action {
        flex-grow: 1;
        text-align: right;
        color: #ecf0f1;
        margin-right: 10px;
      }

      .confirm-card,
      .saved-card,
      .earlier {
        background: rgba(0, 0, 0, 0.3);
        border: 1px solid #6b7fd7;
        border-radius: 6px;
        padding: 15px;
      }

      .confirm-card {
        border-color: #e0b341;
      }

      .confirm-title,
      .saved-title,
      .earlier-title {
        margin: 0 0 8px 0;
        font-size: 13px;
        text-transform: uppercase;
        letter-spacing: 1px;
        color: #8a9eff;
      }

      .confirm-title {
        color: #e0b341;
      }

      .earlier-title {
        display: flex;
        justify-content: space-between;
        align-items: center;
      }

      .confirm-body,
      .saved-text,
      .earlier-text {
        margin: 0;
        font-size: 15px;
        color: #ecf0f1;
        line-height: 1.5;
        white-space: pre-wrap;
        word-break: break-word;
      }

      .confirm-hint {
        margin: 10px 0 0 0;
        font-size: 12px;
        color: #707070;
      }

      .saved-answer,
      .earlier-answer {
        margin: 8px 0 0 0;
        font-size: 13px;
        color: #9fd7c1;
        line-height: 1.5;
        white-space: pre-wrap;
        word-break: break-word;
      }

      .earlier-refresh {
        font-size: 12px;
        color: #8a9eff;
        cursor: pointer;
        text-transform: none;
        letter-spacing: 0;
      }

      .earlier-row + .earlier-row {
        border-top: 1px solid #333;
        margin-top: 12px;
        padding-top: 12px;
      }

      .refusal-card {
        background: rgba(192, 57, 43, 0.15);
        border: 1px solid #c0392b;
        border-radius: 6px;
        padding: 15px;
      }

      .refusal-title {
        margin: 0 0 8px 0;
        font-size: 13px;
        text-transform: uppercase;
        letter-spacing: 1px;
        color: #e37b6f;
      }

      .refusal-body {
        margin: 0;
        font-size: 14px;
        color: #ecf0f1;
        line-height: 1.5;
      }

      .empty-state {
        margin: 0;
        font-size: 13px;
        color: #707070;
        font-style: italic;
      }

      .hint-text {
        text-align: center;
        font-size: 13px;
        color: #707070;
        font-style: italic;
      }

      .hint-text p {
        margin: 0;
      }

      .message {
        position: absolute;
        bottom: 20px;
        left: 50%;
        transform: translateX(-50%);
        background: rgba(107, 127, 215, 0.2);
        border: 1px solid #6b7fd7;
        padding: 12px 20px;
        border-radius: 4px;
        font-size: 14px;
        color: #ecf0f1;
        animation: slideUp 0.3s ease;
        max-width: 90%;
        text-align: center;
      }

      @keyframes slideUp {
        from {
          opacity: 0;
          transform: translateX(-50%) translateY(20px);
        }
        to {
          opacity: 1;
          transform: translateX(-50%) translateY(0);
        }
      }
    </style>
    """
  end
end
