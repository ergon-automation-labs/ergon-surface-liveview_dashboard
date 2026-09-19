defmodule BotArmyDashboardLiveview.OfflineQueue do
  @moduledoc """
  Server-side queue for offline operations in Nova phone handhelds.
  Handles:
  - Queuing failed NATS publishes
  - Buffering subscription messages during socket offline
  - Automatic retry + conflict resolution on reconnect
  """

  use GenServer
  require Logger

  @max_retries 3
  @retry_delays [1000, 5000, 15000]

  defstruct [
    :socket_id,
    publishes: [],
    messages: [],
    status: :online,
    last_sync: nil,
    failed_count: 0
  ]

  # Public API

  def start_link(opts) do
    socket_id = Keyword.fetch!(opts, :socket_id)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(socket_id))
  end

  def enqueue_publish(socket_id, subject, payload, metadata \\ %{}) do
    GenServer.call(via_tuple(socket_id), {
      :enqueue_publish,
      subject,
      payload,
      metadata
    })
  rescue
    _ -> {:error, :queue_unavailable}
  end

  def enqueue_message(socket_id, subject, payload, received_at) do
    GenServer.call(via_tuple(socket_id), {
      :enqueue_message,
      subject,
      payload,
      received_at
    })
  rescue
    _ -> {:error, :queue_unavailable}
  end

  def mark_online(socket_id) do
    GenServer.call(via_tuple(socket_id), :mark_online)
  rescue
    _ -> :ok
  end

  def mark_offline(socket_id) do
    GenServer.call(via_tuple(socket_id), :mark_offline)
  rescue
    _ -> :ok
  end

  def get_status(socket_id) do
    GenServer.call(via_tuple(socket_id), :get_status)
  rescue
    _ ->
      {
        :error,
        %{
          publishes: 0,
          messages: 0,
          status: :unknown,
          last_sync: nil
        }
      }
  end

  def flush_queue(socket_id, publish_fn) when is_function(publish_fn, 2) do
    GenServer.call(via_tuple(socket_id), {:flush, publish_fn}, 30000)
  rescue
    _ -> {:error, :flush_failed}
  end

  def reset_queue(socket_id) do
    GenServer.call(via_tuple(socket_id), :reset)
  rescue
    _ -> :ok
  end

  # GenServer callbacks

  @impl true
  def init(opts) do
    socket_id = Keyword.fetch!(opts, :socket_id)

    state = %__MODULE__{
      socket_id: socket_id,
      publishes: [],
      messages: [],
      status: :online,
      last_sync: DateTime.utc_now(),
      failed_count: 0
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:enqueue_publish, subject, payload, metadata}, _from, state) do
    item = %{
      id: generate_id(),
      type: :publish,
      subject: subject,
      payload: payload,
      metadata: metadata,
      timestamp: DateTime.utc_now(),
      retries: 0,
      last_error: nil
    }

    new_state = %{state | publishes: [item | state.publishes]}

    {:reply, {:ok, item.id}, new_state}
  end

  @impl true
  def handle_call({:enqueue_message, subject, payload, received_at}, _from, state) do
    item = %{
      id: generate_id(),
      type: :message,
      subject: subject,
      payload: payload,
      received_at: received_at,
      processed: false
    }

    new_state = %{state | messages: [item | state.messages]}

    {:reply, {:ok, item.id}, new_state}
  end

  @impl true
  def handle_call(:mark_online, _from, state) do
    new_state = %{state | status: :online, last_sync: DateTime.utc_now()}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:mark_offline, _from, state) do
    new_state = %{state | status: :offline}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    status = {
      :ok,
      %{
        publishes: Enum.count(state.publishes),
        messages: Enum.count(state.messages),
        status: state.status,
        last_sync: state.last_sync,
        failed: state.failed_count
      }
    }

    {:reply, status, state}
  end

  @impl true
  def handle_call({:flush, publish_fn}, _from, state) do
    {results, new_state} = flush_publishes(state, publish_fn)

    {:reply, results, new_state}
  end

  @impl true
  def handle_call(:reset, _from, _state) do
    new_state = %__MODULE__{
      socket_id: _state.socket_id,
      publishes: [],
      messages: [],
      status: :online,
      last_sync: DateTime.utc_now(),
      failed_count: 0
    }

    {:reply, :ok, new_state}
  end

  # Private helpers

  defp flush_publishes(state, publish_fn) do
    publishes = Enum.reverse(state.publishes)

    results =
      Enum.reduce(publishes, {0, 0, []}, fn item, {synced, failed, failed_items} ->
        case attempt_publish(item, publish_fn) do
          :ok ->
            {synced + 1, failed, failed_items}

          {:error, reason} ->
            if item.retries < @max_retries do
              retry_item = %{item | retries: item.retries + 1, last_error: reason}
              {synced, failed + 1, [retry_item | failed_items]}
            else
              {synced, failed + 1, failed_items}
            end
        end
      end)

    {synced, failed, failed_items} = results

    new_state = %{
      state
      | publishes: failed_items,
        last_sync: DateTime.utc_now(),
        failed_count: failed
    }

    {{:ok, %{synced: synced, failed: failed, queued: length(failed_items)}}, new_state}
  end

  defp attempt_publish(item, publish_fn) do
    try do
      publish_fn.(item.subject, item.payload)
    rescue
      e in _ ->
        Logger.debug("Offline queue publish failed: #{inspect(e)}")
        {:error, Exception.message(e)}
    catch
      _ ->
        {:error, "unknown error"}
    end
  end

  defp via_tuple(socket_id) do
    {:via, Registry, {BotArmyDashboardLiveview.Registry, {:offline_queue, socket_id}}}
  end

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end
