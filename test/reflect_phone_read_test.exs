defmodule BotArmyDashboardLiveview.ReflectPhoneReadTest do
  @moduledoc """
  The reflect phone reads as well as writes.

  The screen this file is about used to publish `events.reflection.captured` and, on
  the broker's `:ok`, print "✓ Reflection captured" — a claim about the store made by
  a screen that had only heard the bytes leave. It never read a reflection back, so
  it could not show her that her words landed, could not show the companion's answer,
  and could not tell a refusal from a success.

  What is pinned here: the write goes to the store's own request subject (not the
  event subject), nothing leaves the box on one press, the confirmation card is drawn
  from the row the store returned and from the re-read that follows it, a refusal is
  never drawn as a save, and a store that refuses to list is never drawn as an empty
  store.

  `async: false` because the stub is installed through application env.
  """

  use ExUnit.Case, async: false

  @moduletag :core

  @endpoint BotArmyDashboardLiveview.Endpoint

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias BotArmyDashboardLiveview.BrokerStub

  @app :bot_army_dashboard_liveview

  @id "8f1a0f2e-1111-4000-8000-000000000001"
  @line "the moon was loud tonight"
  @answer "It said: keep going."

  setup do
    Application.put_env(@app, :broker_transport, BrokerStub)
    Application.put_env(@app, :broker_stub_listener, self())

    on_exit(fn ->
      for key <- [:broker_transport, :broker_stub_reply, :broker_stub_listener] do
        Application.delete_env(@app, key)
      end
    end)

    :ok
  end

  defp install_reply(body), do: Application.put_env(@app, :broker_stub_reply, body)

  defp list_body(rows) do
    Jason.encode!(%{"reflections" => rows, "count" => length(rows)})
  end

  # The row the store holds. `held` is the test's switch: 0 while the companion is
  # still reading, 1 once it has an answer to report.
  defp row(held) when is_integer(held) do
    case held do
      1 -> row(%{"answer" => %{"state" => "answered", "text" => @answer}})
      _ -> row(%{})
    end
  end

  defp row, do: row(0)

  defp row(overrides) when is_map(overrides) do
    Map.merge(
      %{
        "id" => @id,
        "text" => @line,
        "prompt" => "What did the night say?",
        "chars" => String.length(@line),
        "stored_at" => "2026-10-03T21:00:00Z",
        "answer" => %{"state" => "pending"}
      },
      overrides
    )
  end

  defp await(view, text), do: await(view, text, 80)

  defp flush_requests do
    receive do
      {:broker_stub_request, _, _, _, _} -> flush_requests()
    after
      0 -> :ok
    end
  end

  defp await(_view, text, 0),
    do:
      flunk(
        "the screen never showed #{inspect(text)}. It showed:\n" <>
          String.slice(render(_view), 0, 3000)
      )

  defp await(view, text, tries) do
    if render(view) =~ text do
      :ok
    else
      Process.sleep(10)
      await(view, text, tries - 1)
    end
  end

  # ── reading back what the store already holds ───────────────────────────────

  test "the screen shows the reflections the store already holds" do
    install_reply(list_body([row(), row(%{"id" => "r2", "text" => "an older line"})]))

    {:ok, view, _html} = live(build_conn(), "/reflect-phone")

    await(view, @line)
    assert render(view) =~ "an older line"
    refute render(view) =~ "Nothing written yet"
  end

  test "the screen asks the store for the recent reflections, on the store's own subject" do
    install_reply(list_body([]))

    {:ok, view, _html} = live(build_conn(), "/reflect-phone")

    assert_receive {:broker_stub_request, _, "companion.reflections.list", payload, _opts}
    assert Jason.decode!(payload) == %{"limit" => 5}
    await(view, "Nothing written yet")
  end

  test "a pending answer is drawn as owed, not as silence" do
    install_reply(list_body([row()]))

    {:ok, view, _html} = live(build_conn(), "/reflect-phone")

    await(view, "Eir is reading it")
  end

  test "an answered reflection carries the store's words" do
    install_reply(list_body([row(%{"answer" => %{"state" => "answered", "text" => @answer}})]))

    {:ok, view, _html} = live(build_conn(), "/reflect-phone")

    await(view, @answer)
  end

  # The lie this file exists for: a store that refused a read used to look exactly
  # like an empty store.
  test "a store that refuses to list is a refusal, never an empty store" do
    install_reply(
      Jason.encode!(%{
        "ok" => false,
        "code" => "unavailable",
        "error" => "the reflection store could not be reached"
      })
    )

    {:ok, view, _html} = live(build_conn(), "/reflect-phone")

    await(view, "Your earlier reflections are not shown")
    assert render(view) =~ "the reflection store could not be reached"
    refute render(view) =~ "Nothing written yet"
  end

  test "a read that never came back says so instead of showing an empty store" do
    install_reply({:error, :timeout})

    {:ok, view, _html} = live(build_conn(), "/reflect-phone")

    await(view, "Can\u2019t reach the bot")
    assert render(view) =~ "the bot did not answer in time"
    refute render(view) =~ "Nothing written yet"
  end

  # ── writing ─────────────────────────────────────────────────────────────────

  test "nothing leaves the box on one press — the first press is the confirmation card" do
    install_reply(list_body([]))

    {:ok, view, _html} = live(build_conn(), "/reflect-phone")

    render_change(view, "update-reflection", %{"reflection" => @line})
    render_hook(view, "gamepad-a", %{})

    assert render(view) =~ "Save this reflection?"
    refute_receive {:broker_stub_request, _, "companion.reflections.capture", _, _}, 50
  end

  # Backing out of the card sends nothing.
  test "the second key backs out of the confirmation without writing" do
    install_reply(list_body([]))

    {:ok, view, _html} = live(build_conn(), "/reflect-phone")

    render_change(view, "update-reflection", %{"reflection" => @line})
    render_hook(view, "gamepad-a", %{})
    render_hook(view, "gamepad-b", %{})

    refute render(view) =~ "Save this reflection?"
    refute_receive {:broker_stub_request, _, "companion.reflections.capture", _, _}, 50
  end

  test "an empty page is refused without asking the store" do
    install_reply(list_body([]))

    {:ok, view, _html} = live(build_conn(), "/reflect-phone")

    render_hook(view, "gamepad-a", %{})

    assert render(view) =~ "nothing to save"
    refute_receive {:broker_stub_request, _, "companion.reflections.capture", _, _}, 50
  end

  # The whole point: the write goes to the store's request subject, and the success
  # line is drawn from the store's own row and the re-read after it — never from the
  # write's ok, and never from the old fire-and-forget event.
  test "the write is a request to the store and the confirmation is the re-read" do
    install_reply({:answers,
     fn
       "companion.reflections.capture" ->
         # The write's own reply says pending: the answer is not there yet.
         Jason.encode!(%{"reflection" => row()})

       "companion.reflections.list" ->
         list_body([row(%{"answer" => %{"state" => "answered", "text" => @answer}})])

       "companion.reflections.read" ->
         Jason.encode!(%{
           "reflection" => row(%{"answer" => %{"state" => "answered", "text" => @answer}})
         })

       _other ->
         "{}"
     end})

    {:ok, view, _html} = live(build_conn(), "/reflect-phone")

    fill_and_save(view, @line)

    assert_receive {:broker_stub_request, _, "companion.reflections.capture", payload, _opts}
    assert Jason.decode!(payload)["text"] == @line

    # The answer can only have come from the re-read: the write reply carried none.
    await(view, @answer)
    assert render(view) =~ "Just saved"
    refute render(view) =~ "Reflection captured"

    # And exactly one write went out. A screen that re-sends on the re-render is the
    # duplicate-reflection machine this lane must not be.
    refute_receive {:broker_stub_request, _, "companion.reflections.capture", _, _}, 50
  end

  test "the old fire-and-forget event subject is not used at all" do
    install_reply(list_body([]))

    {:ok, view, _html} = live(build_conn(), "/reflect-phone")

    fill_and_save(view, @line)

    assert_receive {:broker_stub_request, _, "companion.reflections.capture", _, _}, 200
    refute_receive {:broker_stub_request, _, "events.reflection.captured", _, _}, 50
  end

  # A double tap is the phone's mistake, not a second reflection. On 2026-10-05 one
  # press produced two rows 30 ms apart and asked the model twice; the two sends
  # carried no way to tell that they were one draft. They do now: the key is held
  # until the store says it holds the words.
  test "a second press while the first is in flight is the same draft" do
    # The write is answered by nothing at all, so it is still in flight while the
    # next presses happen — the same moment the duplicate was born in.
    install_reply(
      {:answers,
       fn
         "companion.reflections.capture" -> {:error, :timeout}
         _other -> list_body([])
       end}
    )

    {:ok, view, _html} = live(build_conn(), "/reflect-phone")

    render_change(view, "update-reflection", %{"reflection" => @line})

    # The first press is the card; the next three are writes that never came back, so
    # each is still in flight when the one after it leaves.
    render_hook(view, "gamepad-a", %{})
    render_hook(view, "gamepad-a", %{})
    render_hook(view, "gamepad-a", %{})
    render_hook(view, "gamepad-a", %{})

    keys = [next_capture(), next_capture(), next_capture()]

    assert Enum.uniq(keys) == [hd(keys)]
    assert is_binary(hd(keys)) and hd(keys) != ""
  end

  # Once the store has the words, the next draft is a different one — otherwise a
  # second reflection written later from the same screen would be deduped away.
  test "the next draft gets its own key once the store holds the words" do
    install_reply(
      {:answers,
       fn
         "companion.reflections.capture" -> Jason.encode!(%{"reflection" => row()})
         "companion.reflections.list" -> list_body([])
         _other -> "{}"
       end}
    )

    {:ok, view, _html} = live(build_conn(), "/reflect-phone")

    fill_and_save(view, @line)
    assert_receive {:broker_stub_request, _, "companion.reflections.capture", first, _opts}

    # The barrier: the store's own row has been drawn, so the write is finished and
    # the key has been rotated.
    await(view, "Just saved")

    render_change(view, "update-reflection", %{"reflection" => "a second line"})
    render_hook(view, "gamepad-a", %{})
    render_hook(view, "gamepad-a", %{})

    assert_receive {:broker_stub_request, _, "companion.reflections.capture", second, _opts}, 200
    refute Jason.decode!(first)["dedupe_key"] == Jason.decode!(second)["dedupe_key"]
    assert Jason.decode!(second)["text"] == "a second line"
  end

  # A refusal is a refusal: the store's sentence, no "saved" anywhere, and her words
  # still in the box rather than thrown away.
  test "a write the store refused is never drawn as a save" do
    install_reply(
      {:answers,
       fn
         "companion.reflections.capture" ->
           Jason.encode!(%{
             "ok" => false,
             "code" => "validation_error",
             "error" => "a reflection needs words in it"
           })

         _other ->
           list_body([])
       end}
    )

    {:ok, view, _html} = live(build_conn(), "/reflect-phone")

    fill_and_save(view, @line)

    await(view, "Nothing was saved")
    assert render(view) =~ "a reflection needs words in it"
    refute render(view) =~ "Saved — the store has your words."
    # The words are still on the confirmation card, not cleared.
    assert render(view) =~ @line
  end

  # A write that never came back is not a write that failed: the screen says the read
  # failed, and it does not claim either way.
  test "a write that never came back neither saves nor clears the box" do
    install_reply(
      {:answers,
       fn
         "companion.reflections.capture" -> {:error, :timeout}
         _other -> list_body([])
       end}
    )

    {:ok, view, _html} = live(build_conn(), "/reflect-phone")

    fill_and_save(view, @line)

    await(view, "Can\u2019t reach the bot")
    refute render(view) =~ "Saved — the store has your words."
    assert render(view) =~ @line
  end

  # ── the bell and the cadence ────────────────────────────────────────────────

  # The bell is an accelerator: the screen is waiting on a pending answer, the llm
  # bot says a job ended, and the screen re-reads and finds the words. The store
  # holds no answer until the bell, so what appears can only be the re-read's.
  #
  # The flag is flipped by the test rather than by a call count because a
  # `live/2` mounts twice: the router's dead render runs `mount/3` too, and its
  # read goes out on the wire before the connected one. That is how every screen
  # in this app already mounts, so the test cannot count reads to know where it is.
  test "a finished job rings the screen and the owed answer is re-read" do
    held = :counters.new(1, [])

    install_reply(
      {:answers,
       fn
         "companion.reflections.list" -> list_body([row(:counters.get(held, 1))])
         _other -> "{}"
       end}
    )

    {:ok, view, _html} = live(build_conn(), "/reflect-phone")

    await(view, "Eir is reading it")
    refute render(view) =~ @answer

    :counters.put(held, 1, 1)
    send_pubsub({:answer_event, "events.llm.job.completed", %{"job_id" => "j1"}})

    await(view, @answer)
  end

  # The cadence is the guarantee under the bell, so it is tested by its own message:
  # a poll re-reads while an answer is owed, and does nothing at all once none is left.
  test "the poll cadence re-reads while an answer is owed, and stops once none is" do
    held = :counters.new(1, [])

    install_reply(
      {:answers,
       fn
         "companion.reflections.list" -> list_body([row(:counters.get(held, 1))])
         _other -> "{}"
       end}
    )

    {:ok, view, _html} = live(build_conn(), "/reflect-phone")

    await(view, "Eir is reading it")
    flush_requests()

    # The store has the answer now, so the next read is the one that finds it.
    :counters.put(held, 1, 1)
    send(view.pid, :poll)
    assert_receive {:broker_stub_request, _, "companion.reflections.list", _, _}, 500
    await(view, @answer)

    # Nothing is owed now, so the chain stops rather than re-reading a settled store.
    flush_requests()
    send(view.pid, :poll)
    refute_receive {:broker_stub_request, _, "companion.reflections.list", _, _}, 200
  end

  defp send_pubsub(message) do
    Phoenix.PubSub.broadcast(BotArmyDashboardLiveview.PubSub, "dashboard:reflections", message)
  end

  # The box is a form; a test types into it the same way the browser does, then
  # presses Y twice: the first press is the confirmation card, the second writes.
  # One capture request, off the wire, with the body the screen sent.
  defp next_capture do
    assert_receive {:broker_stub_request, _, "companion.reflections.capture", payload, _opts},
                   2_000

    assert Jason.decode!(payload)["text"] == @line
    Jason.decode!(payload)["dedupe_key"]
  end

  defp fill_and_save(view, text) do
    render_change(view, "update-reflection", %{"reflection" => text})
    render_hook(view, "gamepad-a", %{})
    render_hook(view, "gamepad-a", %{})
  end
end
