defmodule BotArmyDashboardLiveview.NATSBridge do
  @moduledoc """
  NATS bridge for real-time dashboard events.

  Subscribes to Bot Army events and broadcasts to Phoenix.PubSub for LiveView updates.
  """

  use GenServer
  require Logger

  alias Phoenix.PubSub

  @nats_host System.get_env("NATS_HOST", "localhost")
  @nats_port String.to_integer(System.get_env("NATS_PORT", "4222"))

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Logger.info("[NATSBridge] Starting, connecting to #{@nats_host}:#{@nats_port}")
    send(self(), :connect)

    {:ok,
     %{
       conn: nil,
       subscriptions: []
     }}
  end

  @impl true
  def handle_info(:connect, state) do
    # Kill any existing connection with the same name before starting a new one
    case GenServer.whereis(:nats_connection) do
      pid when is_pid(pid) ->
        Logger.info("[NATSBridge] Terminating existing connection...")
        GenServer.stop(pid)

      nil ->
        :ok
    end

    Process.sleep(100)

    try do
      connection_settings = %{host: @nats_host, port: @nats_port}

      case Gnat.start_link(connection_settings, name: :nats_connection) do
        {:ok, _pid} ->
          Logger.info("[NATSBridge] Connected to NATS at #{@nats_host}:#{@nats_port}")
          # Broadcast connection status to dashboard
          PubSub.broadcast(
            BotArmyDashboardLiveview.PubSub,
            "dashboard:status",
            {:status_update, true}
          )

          send(self(), :subscribe)
          {:noreply, state}

        {:error, reason} ->
          Logger.error("[NATSBridge] Failed to connect: #{inspect(reason)}")
          Logger.warning("[NATSBridge] Retrying in 5s...")
          Process.send_after(self(), :connect, 5000)
          {:noreply, state}
      end
    rescue
      e ->
        Logger.error("[NATSBridge] Exception during connect: #{inspect(e)}")
        Logger.error("[NATSBridge] #{Exception.format(e, __STACKTRACE__)}")
        Logger.warning("[NATSBridge] Retrying in 5s...")
        Process.send_after(self(), :connect, 5000)
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(:subscribe, state) do
    case GenServer.whereis(:nats_connection) do
      nil ->
        Logger.warning("[NATSBridge] NATS not available yet, retrying...")
        Process.send_after(self(), :subscribe, 5000)
        {:noreply, state}

      _conn ->
        subscriptions = subscribe_to_events()
        {:noreply, %{state | subscriptions: subscriptions}}
    end
  end

  @impl true
  def handle_info({:msg, msg}, state) do
    try do
      body = msg.body
      subject = msg.topic

      case Jason.decode(body) do
        {:ok, event} ->
          broadcast_event(subject, event)

        {:error, _} ->
          # Try to parse as raw string
          broadcast_event(subject, %{"raw" => body})
      end
    rescue
      e ->
        Logger.error("[NATSBridge] Error processing message: #{inspect(e)}")
    end

    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Private

  defp subscribe_to_events do
    conn = :nats_connection

    subjects = [
      "events.gtd.task.>",
      "events.gtd.decomposition.>",
      "system.health.>",
      "bot_army.registry.presence"
    ]

    Enum.map(subjects, fn subject ->
      case Gnat.sub(conn, self(), subject) do
        {:ok, sub} ->
          Logger.info("[NATSBridge] Subscribed to #{subject}")
          {subject, sub}

        {:error, reason} ->
          Logger.warning("[NATSBridge] Failed to subscribe to #{subject}: #{inspect(reason)}")
          {subject, nil}
      end
    end)
  end

  defp broadcast_event(subject, event) do
    # Broadcast to different channels based on subject
    cond do
      String.starts_with?(subject, "events.gtd.task.") ->
        broadcast_task_event(subject, event)

      String.starts_with?(subject, "events.gtd.decomposition.") ->
        broadcast_decomposition_event(subject, event)

      String.starts_with?(subject, "system.health.") ->
        broadcast_health_event(subject, event)

      String.starts_with?(subject, "bot_army.registry.presence") ->
        broadcast_presence_event(subject, event)

      true ->
        :ok
    end
  end

  defp broadcast_task_event(subject, event) do
    PubSub.broadcast(
      BotArmyDashboardLiveview.PubSub,
      "dashboard:tasks",
      {:task_event, subject, event}
    )
  end

  defp broadcast_decomposition_event(subject, event) do
    PubSub.broadcast(
      BotArmyDashboardLiveview.PubSub,
      "dashboard:decompositions",
      {:decomposition_event, subject, event}
    )
  end

  defp broadcast_health_event(subject, event) do
    PubSub.broadcast(
      BotArmyDashboardLiveview.PubSub,
      "dashboard:health",
      {:health_event, subject, event}
    )
  end

  defp broadcast_presence_event(subject, event) do
    PubSub.broadcast(
      BotArmyDashboardLiveview.PubSub,
      "dashboard:presence",
      {:presence_event, subject, event}
    )
  end
end
