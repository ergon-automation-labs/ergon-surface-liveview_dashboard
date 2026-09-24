defmodule BotArmyDashboardLiveview.ReflectionLive do
  use Phoenix.LiveView
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

  @impl true
  def mount(_params, _session, socket) do
    :ok = PubSub.subscribe(BotArmyDashboardLiveview.PubSub, "gamepad")

    socket =
      socket
      |> assign(
        reflection_text: "",
        prompt: Enum.random(@prompts),
        message: nil,
        character_intro: "Let's capture this moment."
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

  @impl true
  def handle_event("gamepad-a", _params, socket) do
    if String.trim(socket.assigns.reflection_text) != "" do
      publish_reflection(socket)
    else
      {:noreply, assign(socket, message: "Write something first")}
      |> then(fn s -> schedule_message_clear(s, 2000) end)
    end
  end

  @impl true
  def handle_event("gamepad-b", _params, socket) do
    {:noreply, assign(socket, reflection_text: "", message: nil)}
  end

  @impl true
  def handle_event("update-reflection", %{"reflection" => text}, socket) do
    {:noreply, assign(socket, reflection_text: text, message: nil)}
  end

  defp publish_reflection(socket) do
    parent = self()

    Task.start_link(fn ->
      try do
        payload = %{
          "text" => socket.assigns.reflection_text,
          "prompt" => socket.assigns.prompt,
          "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
        }

        case Gnat.pub(:nats_connection, "events.reflection.captured", Jason.encode!(payload)) do
          :ok ->
            send(parent, {:reflection_saved})

          _ ->
            send(parent, {:reflection_failed})
        end
      rescue
        _ -> send(parent, {:reflection_failed})
      end
    end)

    {:noreply,
     socket
     |> assign(message: "Saving reflection...")
     |> schedule_message_clear(2000)}
  end

  @impl true
  def handle_info({:reflection_saved}, socket) do
    {:noreply,
     socket
     |> assign(
       reflection_text: "",
       prompt: Enum.random(@prompts),
       message: "✓ Reflection captured. The story continues."
     )
     |> schedule_message_clear(4000)}
  end

  @impl true
  def handle_info({:reflection_failed}, socket) do
    {:noreply,
     socket
     |> assign(message: "✗ Could not save reflection")
     |> schedule_message_clear(2000)}
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
  def render(assigns) do
    ~H"""
    <div class="handheld-container reflection">
      <div class="reflection-card">
        <div class="view-title">📝 Reflection</div>

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
            <span class="action">Save Reflection</span>
          </div>
          <div class="control-hint">
            <span class="key">B</span>
            <span class="action">Clear</span>
          </div>
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
        font-size: 24px;
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
        min-height: 150px;
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
