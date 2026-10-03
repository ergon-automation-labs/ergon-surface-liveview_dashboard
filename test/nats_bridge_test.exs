defmodule BotArmyDashboardLiveview.NATSBridgeTest do
  @moduledoc """
  The bridge's routing decision: which subject lands on which channel.

  A saying the house made is broadcast on `events.wife_care.hypnosis.said`, and the shelf
  screen listens on `dashboard:hypnosis`. Those two names are held together by one `cond`
  in this module and by nothing else, which is why it is worth a test of its own: a
  subject with no clause here is dropped silently, and a saying that never arrives looks
  exactly like a house that said nothing.

  The callback is called directly instead of starting the bridge and posting a message.
  Booting the bridge dials the hermetic test port and blocks in `handle_info(:connect)`
  while it retries, so the test would be measuring Gnat's reconnect backoff rather than
  the routing. What is being tested is the decision, and the decision lives in the
  callback — the socket is somebody else's subject.
  """

  use ExUnit.Case, async: false

  alias BotArmyDashboardLiveview.NATSBridge

  @topic "dashboard:hypnosis"
  @said "events.wife_care.hypnosis.said"
  @reflections "dashboard:reflections"
  @party "dashboard:party"

  setup do
    :ok = Phoenix.PubSub.subscribe(BotArmyDashboardLiveview.PubSub, @topic)
    :ok
  end

  # A message as the bridge's subscription would deliver it: the subject, and the body
  # exactly as it came off the wire.
  defp deliver(subject, body) do
    assert {:noreply, %{}} =
             NATSBridge.handle_info({:msg, %{topic: subject, body: body}}, %{})
  end

  test "the read subjects this surface asks the bot for are the ones it serves" do
    # Nothing here dials: what a test can hold is the port the bridge would use, and it is
    # the hermetic one, so no test run can join the live broker.
    assert NATSBridge.configured_port() == "42991"
  end

  test "a saying is routed to the shelf's channel, with the subject it came in on" do
    event = %{
      "event" => "wife_care.hypnosis.said",
      "payload" => %{"phrase_id" => "5f1a0f2e-1111-4000-8000-000000000001", "source" => "tick"}
    }

    deliver(@said, Jason.encode!(event))

    assert_receive {:hypnosis_event, @said, ^event}
  end

  test "another subject still lands where it always did, and not on the shelf's channel" do
    :ok = Phoenix.PubSub.subscribe(BotArmyDashboardLiveview.PubSub, "dashboard:tasks")

    deliver("events.gtd.task.created", Jason.encode!(%{"event" => "gtd.task.created"}))

    refute_receive {:hypnosis_event, _, _}, 50
    assert_receive {:task_event, "events.gtd.task.created", %{"event" => "gtd.task.created"}}
  end

  test "a saying that will not decode is carried raw rather than dropped" do
    deliver(@said, "not json at all")

    assert_receive {:hypnosis_event, @said, %{"raw" => "not json at all"}}
  end

  # The two lanes the reflect and party phones read back on. The bell for a
  # finished answer is `events.llm.job.completed` and the reflect screen listens on
  # `dashboard:reflections`; the tavern's scene events land on `dashboard:party`.
  # Both were silent before: a subject with no clause here is dropped, and the
  # screen it was meant for simply keeps waiting.

  test "a finished job is routed to the reflect screen's channel" do
    :ok = Phoenix.PubSub.subscribe(BotArmyDashboardLiveview.PubSub, @reflections)

    event = %{
      "event" => "llm.job.completed",
      "payload" => %{"job_id" => "7c0a1f2e-1111-4000-8000-000000000001", "status" => "completed"}
    }

    deliver("events.llm.job.completed", Jason.encode!(event))

    # The bell carries the job, never the words: what arrives is the body as it came
    # off the wire and nothing added to it.
    assert_receive {:answer_event, "events.llm.job.completed", ^event}
    refute_receive {:hypnosis_event, _, _}, 50
  end

  test "a tavern scene event is routed to the party screen's channel" do
    :ok = Phoenix.PubSub.subscribe(BotArmyDashboardLiveview.PubSub, @party)

    event = %{
      "event" => "rpg.scene.fact.added",
      "payload" => %{"fact_id" => "9f1a0f2e-2222-4000-8000-000000000001", "turn" => 3}
    }

    deliver("events.rpg.scene.fact.added", Jason.encode!(event))

    assert_receive {:party_event, "events.rpg.scene.fact.added", ^event}
    refute_receive {:hypnosis_event, _, _}, 50
  end

  test "every rpg scene subject under the wildcard lands on the party channel" do
    :ok = Phoenix.PubSub.subscribe(BotArmyDashboardLiveview.PubSub, @party)

    deliver("events.rpg.scene.narrated", Jason.encode!(%{"event" => "rpg.scene.narrated"}))

    deliver(
      "events.rpg.narration.your_turn",
      Jason.encode!(%{"event" => "rpg.narration.your_turn"})
    )

    assert_receive {:party_event, "events.rpg.scene.narrated", _}
    assert_receive {:party_event, "events.rpg.narration.your_turn", _}
  end

  test "a job event that will not decode is carried raw on the reflect channel" do
    :ok = Phoenix.PubSub.subscribe(BotArmyDashboardLiveview.PubSub, @reflections)

    deliver("events.llm.job.completed", "not json at all")

    assert_receive {:answer_event, "events.llm.job.completed", %{"raw" => "not json at all"}}
  end
end
