defmodule BotArmyDashboardLiveview.ReflectPhoneLive do
  use Phoenix.LiveView
  alias Phoenix.PubSub
  alias BotArmyDashboardLiveview.PhoneNav
  alias BotArmyDashboardLiveview.SyncStatus

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
        sync_status: SyncStatus.initial(),
        is_online: true,
        reflection_text: "",
        prompts: @prompts,
        prompt_index: Enum.random(0..(length(@prompts) - 1)),
        prompt: Enum.at(@prompts, Enum.random(0..(length(@prompts) - 1))),
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
    new_idx = Enum.random(0..(length(socket.assigns.prompts) - 1))
    new_prompt = Enum.at(socket.assigns.prompts, new_idx)

    {:noreply,
     socket
     |> assign(
       reflection_text: "",
       prompt_index: new_idx,
       prompt: new_prompt,
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
        <div class="view-title">📝 Reflection</div>

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
            <span class="action">Save</span>
          </div>
          <div class="control-hint">
            <span class="key">B</span>
            <span class="action">Clear</span>
          </div>
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
