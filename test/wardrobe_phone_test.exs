defmodule BotArmyDashboardLiveview.WardrobePhoneTest do
  @moduledoc """
  The wardrobe screen: what it reads, what a tap sends, and what the sentence after a
  tap is allowed to claim.

  The stub is shaped like the live reply. The wardrobe that is on her right now was put
  on her by the house rather than chosen (`chosen: false`, and its `outfit_id` is null
  because it was built ad hoc rather than taken from the six sets), so the mark this
  screen draws for it is the one thing here that must never be rounded to a choice.
  """

  # The reads swap the broker transport for a stub and set process-wide application
  # env, so this module is not async.
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias BotArmyDashboardLiveview.BrokerStub

  @endpoint BotArmyDashboardLiveview.Endpoint
  @app :bot_army_dashboard_liveview

  @read "wife_care.control_panel.wardrobe.list"
  @write "wife_care.control_panel.wear_outfit"

  @maid "2a5f4b40-1111-4000-8000-000000000001"
  @secretary "2a5f4b40-1111-4000-8000-000000000002"

  @on_now "Unnamed outfit"

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

  defp now, do: DateTime.utc_now() |> DateTime.to_iso8601()

  defp maid do
    %{
      "id" => @maid,
      "name" => "Maid",
      "cage" => "standard",
      "plug" => "vibrating",
      "clothing" => "maid dress",
      "accessories" => ["collar"],
      "humiliation_level" => 6,
      "description" => "the one with the apron"
    }
  end

  defp secretary do
    %{
      "id" => @secretary,
      "name" => "Secretary",
      "cage" => "humiliating",
      "plug" => "standard",
      "clothing" => "pencil skirt",
      "accessories" => [],
      "humiliation_level" => 7,
      "description" => "for the days she is working at the desk"
    }
  end

  # The wardrobe that is on her now, in the shape the bot actually sends it: a wearing
  # built ad hoc, which is not one of the sets in the cupboard.
  defp on_now do
    %{
      "name" => @on_now,
      "outfit_id" => nil,
      "chosen" => false,
      "worn_by" => "louiza",
      "worn_at" => now(),
      "parts" => %{"humiliation_level" => 7, "accessories" => []}
    }
  end

  defp worn_set(chosen) do
    %{
      "name" => "Maid",
      "outfit_id" => @maid,
      "chosen" => chosen,
      "worn_by" => if(chosen, do: "subject", else: "louiza"),
      "worn_at" => now(),
      "parts" => %{"cage" => "standard", "humiliation_level" => 6, "accessories" => ["collar"]}
    }
  end

  defp closet_reply(opts \\ []) do
    Jason.encode!(%{
      "ok" => true,
      "data" => %{
        "sets" => Keyword.get(opts, :sets, [maid(), secretary()]),
        "worn" => Keyword.get(opts, :worn, on_now()),
        "catalogue" => %{
          "humiliation_level" => %{"min" => 1, "max" => 10},
          "clothing" => %{"options" => ["maid dress", "pencil skirt"]}
        }
      }
    })
  end

  defp write_ok, do: Jason.encode!(%{"ok" => true, "data" => %{"outfit" => %{"name" => "Maid"}}})

  defp stub(reply), do: Application.put_env(@app, :broker_stub_reply, reply)

  defp stub_read(opts \\ []), do: stub(%{@read => closet_reply(opts), @write => write_ok()})

  # A wardrobe that changes because the wear landed — the only honest way to test a
  # screen that re-reads after a write. The change happens in the write, which the
  # screen makes before it re-reads, so the re-read is never racing the test.
  defp stub_wear_lands_as(chosen) do
    {:ok, agent} = Agent.start_link(fn -> :not_yet end)

    stub(
      {:answers,
       fn
         @write ->
           Agent.update(agent, fn _state -> chosen end)
           write_ok()

         @read ->
           case Agent.get(agent, & &1) do
             :not_yet -> closet_reply(worn: nil)
             landed -> closet_reply(worn: worn_set(landed))
           end
       end}
    )
  end

  # A screen whose read has answered, so a test starts from a settled page rather than
  # from the "nothing from the wardrobe yet" state. The text waited for is the text the
  # stub makes the screen show.
  defp page(opts \\ [], settled \\ @on_now) do
    stub_read(opts)
    {:ok, view, _html} = live(build_conn(), "/wardrobe-phone")
    await(view, settled)
    view
  end

  # `render_async/1` only tracks `start_async` PIDs and this screen re-reads in a
  # hand-rolled task, so wait for the text instead of for a frame.
  defp await(view, text), do: await(view, text, 50)

  defp await(view, text, 0) do
    flunk(
      "the screen never showed #{inspect(text)}; it showed: #{render(view) |> String.split("</head>") |> List.last() |> String.slice(0, 900)}"
    )
  end

  defp await(view, text, tries) do
    if render(view) =~ text do
      :ok
    else
      Process.sleep(10)
      await(view, text, tries - 1)
    end
  end

  # ── the read ───────────────────────────────────────────────────────────────

  test "the screen opens on the wardrobe itself, not on a corner of the panel" do
    html = render(page())

    assert html =~ "👗 The wardrobe"
    assert html =~ "Maid"
    assert html =~ "Secretary"
    assert html =~ "humiliation 6 of 10"
    assert html =~ "humiliation 7 of 10"
    assert html =~ "cage standard"
    assert html =~ "the one with the apron"
    # It is its own page in the bar, and a tap on a set cannot reach a second handler.
    assert html =~ ~s(href="/wardrobe-phone")
    assert html =~ ~s(class="nav-item active")
    refute html =~ "TouchCarousel"
  end

  # The live wearing is the house's, and this is the whole reason the mark exists. The
  # chip is matched whole: "not chosen by her" is a substring of "chosen by her", so a
  # bare-word refutation here would pass on a page that says the opposite.
  test "a wearing the bot records as assigned is drawn as assigned, never as her choice" do
    html = render(page())

    assert html =~ @on_now
    assert html =~ ~s(<span class="chip assigned">assigned</span>)
    assert html =~ "put on her, not chosen by her"
    refute html =~ ~s(<span class="chip chosen">chosen by her</span>)
  end

  test "a failed read is the read error, and not an empty wardrobe" do
    stub({:error, :no_broker})
    {:ok, view, _html} = live(build_conn(), "/wardrobe-phone")

    await(view, "the bot is not reachable right now")

    html = render(view)

    assert html =~ "The wardrobe was not read"
    refute html =~ "nothing is on her"
    refute html =~ "no sets in it"
  end

  test "an answer that is not a wardrobe refuses the card rather than drawing an empty one" do
    stub(%{@read => Jason.encode!(%{"ok" => true, "data" => %{"sets" => "nope"}})})
    {:ok, view, _html} = live(build_conn(), "/wardrobe-phone")

    await(view, "the bot answered, but not with a wardrobe")

    refute render(view) =~ "Maid"
    refute render(view) =~ "no sets in it"
  end

  test "a wardrobe with no sets in it is the wardrobe's own empty state" do
    html = render(page([sets: []], "no sets in it"))

    assert html =~ "sets are added and archived on the control surface"
    refute html =~ "read error"
  end

  # ── the two taps ───────────────────────────────────────────────────────────

  test "wearing a set is sent in her voice, and confirmed by the read back" do
    stub_wear_lands_as(true)
    {:ok, view, _html} = live(build_conn(), "/wardrobe-phone")
    await(view, "nothing is on her")

    render_click(view, "wear_set", %{"id" => @maid})

    assert_received {:broker_stub_request, _conn, @write, body, _opts}
    assert Jason.decode!(body) == %{"outfit_id" => @maid, "by" => "subject"}

    await(view, "recorded as her choice")
    assert render(view) =~ "the wardrobe reads back Maid, recorded as her choice"
  end

  test "assigning a set is sent in the house's voice, and said to be an assignment" do
    stub_wear_lands_as(false)
    {:ok, view, _html} = live(build_conn(), "/wardrobe-phone")
    await(view, "nothing is on her")

    render_click(view, "assign_set", %{"id" => @maid})

    assert_received {:broker_stub_request, _conn, @write, body, _opts}
    assert Jason.decode!(body) == %{"outfit_id" => @maid, "by" => "louiza"}

    await(view, "recorded as assigned")
    assert render(view) =~ "put on her, not chosen by her"
  end

  # The write is never the sentence: the read is asked again around a tap, and the
  # sentence that follows it is the reading, not the acknowledgement. (The screen's
  # in-between state is pinned in `WardrobeTest` — the re-read can land before this
  # test can look, so asserting it here would be asserting on a race.)
  test "the read is asked again around a tap, and the sentence reports the reading" do
    stub_wear_lands_as(true)
    {:ok, view, _html} = live(build_conn(), "/wardrobe-phone")
    await(view, "nothing is on her")

    assert_received {:broker_stub_request, _conn, @read, _payload, _opts}

    render_click(view, "wear_set", %{"id" => @maid})

    await(view, "the wardrobe reads back")
    assert render(view) =~ "the wardrobe reads back Maid, recorded as her choice"
    assert_received {:broker_stub_request, _conn, @read, _payload, _opts}
  end

  # A tap on a set the card is not drawing is refused here: the bot would refuse it
  # too, and sending a write this screen knows is wrong is not something to delegate.
  test "a tap on a set that is not on the card never reaches the bot" do
    view = page()
    render_click(view, "wear_set", %{"id" => "not-a-set"})

    assert render(view) =~ "nothing was sent"
    refute_received {:broker_stub_request, _conn, @write, _body, _opts}
  end

  test "a tap with no set on it is refused, not a crash" do
    view = page()
    render_click(view, "assign_set", %{})

    assert render(view) =~ "that tap had no set on it"
    assert render(view) =~ "nothing was sent"
    refute_received {:broker_stub_request, _conn, @write, _body, _opts}
  end

  # The bot's sentence is printed as it arrives. It carries an apostrophe, and HEEx
  # escapes one to `&#39;`, so this asserts the halves rather than the phrase.
  test "a refusal from the bot keeps its own sentence, and claims no wear" do
    stub(%{
      @read => closet_reply(worn: nil),
      @write =>
        Jason.encode!(%{
          "ok" => false,
          "error" => "wearing a set is refused while the subject's stop is in place",
          "code" => "paused"
        })
    })

    {:ok, view, _html} = live(build_conn(), "/wardrobe-phone")
    await(view, "nothing is on her")

    render_click(view, "wear_set", %{"id" => @maid})

    await(view, "refused while the subject")
    assert render(view) =~ "stop is in place"
    assert render(view) =~ "&#39;"
    refute render(view) =~ "the wardrobe reads back"
  end

  test "a dead broker says nothing was recorded, and logs it" do
    stub(%{@read => closet_reply(worn: nil), @write => {:error, :no_broker}})

    {:ok, view, _html} = live(build_conn(), "/wardrobe-phone")
    await(view, "nothing is on her")

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        render_click(view, "wear_set", %{"id" => @maid})
        await(view, "nothing was recorded")
      end)

    assert log =~ "[Wardrobe]"
    assert log =~ "the broker is not reachable"
    refute render(view) =~ "the wardrobe reads back"
  end

  # A wear may have landed despite a timeout, so the honest sentence is not the same
  # one a dead broker gets.
  test "a write that may have landed says that is not known rather than that nothing was" do
    stub(%{@read => closet_reply(worn: nil), @write => {:error, :timeout}})

    {:ok, view, _html} = live(build_conn(), "/wardrobe-phone")
    await(view, "nothing is on her")

    render_click(view, "wear_set", %{"id" => @maid})

    await(view, "whether anything was recorded is not known")
    refute render(view) =~ "nothing was recorded"
  end
end
