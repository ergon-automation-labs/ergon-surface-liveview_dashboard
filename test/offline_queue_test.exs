defmodule BotArmyDashboardLiveview.OfflineQueueTest do
  use ExUnit.Case

  setup do
    socket_id = "test-socket-#{System.unique_integer()}"

    # Registry should be started by application
    {:ok, _pid} =
      BotArmyDashboardLiveview.OfflineQueue.start_link(socket_id: socket_id)

    {:ok, socket_id: socket_id}
  end

  test "enqueues publish on demand", %{socket_id: socket_id} do
    {:ok, item_id} =
      BotArmyDashboardLiveview.OfflineQueue.enqueue_publish(
        socket_id,
        "test.subject",
        Jason.encode!(%{"data" => "test"}),
        %{}
      )

    assert is_binary(item_id)
    assert String.length(item_id) > 0
  end

  test "enqueues message on demand", %{socket_id: socket_id} do
    {:ok, item_id} =
      BotArmyDashboardLiveview.OfflineQueue.enqueue_message(
        socket_id,
        "test.subject",
        Jason.encode!(%{"event" => "test"}),
        DateTime.utc_now()
      )

    assert is_binary(item_id)
  end

  test "tracks online/offline status", %{socket_id: socket_id} do
    :ok = BotArmyDashboardLiveview.OfflineQueue.mark_offline(socket_id)

    {:ok, status} = BotArmyDashboardLiveview.OfflineQueue.get_status(socket_id)
    assert status.status == :offline

    :ok = BotArmyDashboardLiveview.OfflineQueue.mark_online(socket_id)

    {:ok, status} = BotArmyDashboardLiveview.OfflineQueue.get_status(socket_id)
    assert status.status == :online
  end

  test "counts queued items", %{socket_id: socket_id} do
    BotArmyDashboardLiveview.OfflineQueue.enqueue_publish(
      socket_id,
      "test.subject.1",
      Jason.encode!(%{"a" => 1}),
      %{}
    )

    BotArmyDashboardLiveview.OfflineQueue.enqueue_publish(
      socket_id,
      "test.subject.2",
      Jason.encode!(%{"b" => 2}),
      %{}
    )

    {:ok, status} = BotArmyDashboardLiveview.OfflineQueue.get_status(socket_id)
    assert status.publishes == 2
  end

  test "flushes queue with publish function", %{socket_id: socket_id} do
    BotArmyDashboardLiveview.OfflineQueue.enqueue_publish(
      socket_id,
      "test.subject",
      Jason.encode!(%{"test" => "data"}),
      %{}
    )

    published = []

    publish_fn = fn subject, payload ->
      send(self(), {:published, subject, payload})
      :ok
    end

    {:ok, result} = BotArmyDashboardLiveview.OfflineQueue.flush_queue(socket_id, publish_fn)

    assert result.synced == 1
    assert result.failed == 0
  end

  test "resets queue", %{socket_id: socket_id} do
    BotArmyDashboardLiveview.OfflineQueue.enqueue_publish(
      socket_id,
      "test.subject",
      Jason.encode!(%{"test" => "data"}),
      %{}
    )

    {:ok, status_before} = BotArmyDashboardLiveview.OfflineQueue.get_status(socket_id)
    assert status_before.publishes > 0

    :ok = BotArmyDashboardLiveview.OfflineQueue.reset_queue(socket_id)

    {:ok, status_after} = BotArmyDashboardLiveview.OfflineQueue.get_status(socket_id)
    assert status_after.publishes == 0
  end
end
