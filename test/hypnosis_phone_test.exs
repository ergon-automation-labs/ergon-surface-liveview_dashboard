defmodule BotArmyDashboardLiveview.HypnosisPhoneTest do
  @moduledoc """
  The shelf screen: what it reads, what a tap sends, and what the sentence after a tap
  is allowed to claim.

  The live shelf is empty (nothing has been put on it yet), so the stub is the only thing
  that can put a page in front of this test at all. It is shaped like the live reply —
  `{"hypnosis": {phrases, put_away, rewritten, counts, …}, "narration_allowed": …}` —
  because the two shapes that matter here are the ones the bot actually sends: a refusal
  from the store, and a successful read.

  Two things this pins that only a tap can show. A tap this screen can route nowhere
  sends **nothing** — the refusal is the screen's, and it says so. And a write is never
  the sentence: every confirmation in here comes from a re-read the stub changed during
  the write, because a confirmation that came from the write's own ok is exactly the
  claim that can be wrong.
  """

  # The reads swap the broker transport for a stub and set process-wide application env,
  # so this module is not async.
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias BotArmyDashboardLiveview.BrokerStub

  @endpoint BotArmyDashboardLiveview.Endpoint
  @app :bot_army_dashboard_liveview

  @read "wife_care.control_panel.hypnosis"
  @write "wife_care.control_panel.hypnosis_phrase"

  @p1 "5f1a0f2e-1111-4000-8000-000000000001"
  @p2 "5f1a0f2e-1111-4000-8000-000000000002"
  @p3 "5f1a0f2e-1111-4000-8000-000000000003"

  @p1_text "you are worth the trouble"
  @p2_text "the house notices"
  @p3_text "you are a good girl"

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

  # A phrase in the shape the bot sends it, with the `on?` boolean the card draws from.
  defp phrase(opts \\ []) do
    on = Keyword.get(opts, :on, true)

    %{
      "id" => Keyword.get(opts, :id, @p1),
      "key" => "worth",
      "text" => Keyword.get(opts, :text, @p1_text),
      "person" => "i",
      "person_label" => "I",
      "intent" => "worth",
      "intent_label" => "Her worth",
      "detail" => Keyword.get(opts, :detail, "said when she is low"),
      "state" => if(on, do: "on", else: "off"),
      "state_label" => if(on, do: "in the air", else: "off the air"),
      "on?" => on,
      "removed?" => false,
      "authored_by" => "subject"
    }
  end

  # The envelope the bot actually sends, because the read path decodes it and unwraps the
  # `data` the same way it will in production.
  defp shelf_json(block \\ %{}, opts \\ []) do
    block =
      %{
        "phrases" => Keyword.get(opts, :phrases, []),
        "put_away" => Keyword.get(opts, :put_away, []),
        "rewritten" => Keyword.get(opts, :rewritten, []),
        "counts" => %{"on" => 0, "off" => 0, "put_away" => 0, "rewritten" => 0},
        "max_text" => 240
      }
      |> Map.merge(block)

    Jason.encode!(%{
      "ok" => true,
      "data" => %{
        "hypnosis" => block,
        "narration_allowed" => Keyword.get(opts, :narration, true)
      }
    })
  end

  defp write_ok do
    Jason.encode!(%{"ok" => true, "data" => %{"phrase" => %{"id" => @p1}, "hypnosis" => %{}}})
  end

  defp stub(reply), do: Application.put_env(@app, :broker_stub_reply, reply)

  defp stub_read(phrases \\ [], opts \\ []) do
    stub(%{@read => shelf_json(%{"phrases" => phrases}, opts), @write => write_ok()})
  end

  # A shelf that changes because the verb landed — the only honest way to test a screen
  # that re-reads after a write. The change happens in the write, which the screen makes
  # before it re-reads, so the re-read is never racing the test. `lands` is what the shelf
  # holds afterwards: `:off`, `:away`, or `:unchanged`.
  defp stub_verb_lands(lands) do
    {:ok, agent} = Agent.start_link(fn -> :not_yet end)

    stub(
      {:answers,
       fn
         @write ->
           Agent.update(agent, fn _state -> lands end)
           write_ok()

         @read ->
           case Agent.get(agent, & &1) do
             :not_yet ->
               shelf_json(%{"phrases" => [phrase(id: @p1, on: true)]})

             :off ->
               shelf_json(%{"phrases" => [phrase(id: @p1, on: false)]})

             :away ->
               shelf_json(%{
                 "phrases" => [],
                 "put_away" => [phrase(id: @p1, text: @p1_text, on: false)]
               })

             :unchanged ->
               shelf_json(%{"phrases" => [phrase(id: @p1, on: true)]})
           end
       end}
    )
  end

  # A settled page: the text waited for is the text the stub makes the screen show, so a
  # test never starts from the "nothing from the shelf yet" state.
  defp page(phrases \\ [], opts \\ []) do
    stub_read(phrases, opts)
    {:ok, view, _html} = live(build_conn(), "/hypnosis-phone")
    await(view, Keyword.get(opts, :settled, @p1_text))
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

  defp count_of(html, needle) do
    html |> String.split(needle) |> length() |> Kernel.-(1)
  end

  # ── the read ───────────────────────────────────────────────────────────────

  test "the screen opens on the shelf itself, and says what it is for" do
    html = render(page([phrase(id: @p1, on: true), phrase(id: @p2, on: false, text: @p2_text)]))

    assert html =~ "🌀 Her shelf"
    assert html =~ "what she has asked to hear"
    assert html =~ @p1_text
    assert html =~ @p2_text
    # The bot's own labels, not this screen's opinion of the phrase.
    assert html =~ "Her worth"
    assert html =~ "said when she is low"
    assert html =~ "1 in the air · 1 off the air"
    # The narration is stated in the bot's terms.
    assert html =~ "no stop is in place — the house may speak about her."
    # Its own page in the bar, and a tap cannot reach a second handler.
    assert html =~ ~s(href="/hypnosis-phone")
    assert html =~ ~s(class="nav-item active")
    refute html =~ "TouchCarousel"
  end

  # The reason the card does not offer three of the shelf's five verbs is part of the
  # card, not a footnote somewhere else: a screen that silently offers fewer verbs than
  # the domain has is a screen whose limits look like the domain's.
  test "the card says which verbs it is not offering, and why" do
    html = render(page([phrase(id: @p1, on: true)]))

    assert html =~ "Switch off"
    assert html =~ "Take away"
    assert html =~ "putting one back are hers"
    assert html =~ "claims no voice of hers"
  end

  test "a phrase that is already off is drawn without a switch, and says why" do
    html = render(page([phrase(id: @p2, on: false, text: @p2_text)], settled: @p2_text))

    assert html =~ "off the air"
    assert html =~ "it is off the air — only she can put it back in, so there is no switch here."
    assert count_of(html, ~s(phx-value-verb="switch_off")) == 0
    assert count_of(html, ~s(phx-value-verb="take_away")) == 1
  end

  test "a phrase that is in the air carries both reductions" do
    html = render(page([phrase(id: @p1, on: true)]))

    assert count_of(html, ~s(phx-value-verb="switch_off")) == 1
    assert count_of(html, ~s(phx-value-verb="take_away")) == 1
  end

  # The two history lists are drawn read-only: only her voice can put a phrase back, so
  # the card must not offer a button there.
  test "the away list and the earlier wording are drawn without buttons" do
    stub_read([], put_away: [phrase(id: @p3, text: @p3_text, on: false)])
    {:ok, view, _html} = live(build_conn(), "/hypnosis-phone")
    await(view, @p3_text)

    html = render(view)

    assert html =~ "Taken away"
    assert html =~ "only her voice can put one back — so there is no button here"
    assert count_of(html, ~s(phx-value-verb="switch_off")) == 0
    assert count_of(html, ~s(phx-value-verb="take_away")) == 0
  end

  test "a failed read is the read error, and not an empty shelf" do
    stub({:error, :no_broker})
    {:ok, view, _html} = live(build_conn(), "/hypnosis-phone")

    await(view, "the bot is not reachable right now")

    html = render(view)

    assert html =~ "Her shelf"
    assert html =~ "The shelf was not read"
    refute html =~ "nothing is in the air"
  end

  test "an answer that is not a shelf refuses the card rather than drawing an empty one" do
    stub(%{@read => Jason.encode!(%{"ok" => true, "data" => %{"hypnosis" => "nope"}})})
    {:ok, view, _html} = live(build_conn(), "/hypnosis-phone")

    await(view, "the bot answered with a shelf this screen cannot read")

    html = render(view)

    refute html =~ "nothing is in the air"
    assert html =~ "a shelf put together from a read that failed would be this screen inventing"
  end

  # The bot answers a store failure this way, and it arrives as a *successful* read: the
  # one shape that would be read as "she has asked to hear nothing".
  test "the bot refusing the read is a refusal, not an empty shelf" do
    stub(%{@read => Jason.encode!(%{"ok" => false, "error" => "the store is not reachable"})})
    {:ok, view, _html} = live(build_conn(), "/hypnosis-phone")

    await(view, "the store is not reachable")

    html = render(view)

    assert html =~ "Her shelf"
    refute html =~ "nothing is in the air"
    refute html =~ "the shelf is empty"
  end

  test "a shelf with nothing in it is the shelf's own empty state" do
    html = render(page([], settled: "nothing is in the air"))

    assert html =~ "the shelf is empty"
    assert html =~ "A phrase gets onto it in her own voice, which is not a voice this screen has."
    assert html =~ "0 in the air"
    refute html =~ "read error"
  end

  # ── the two taps ───────────────────────────────────────────────────────────

  test "switching a phrase off is written as the operator, and confirmed by the read back" do
    stub_verb_lands(:off)
    {:ok, view, _html} = live(build_conn(), "/hypnosis-phone")
    await(view, @p1_text)

    render_click(view, "act", %{"verb" => "switch_off", "id" => @p1})

    assert_received {:broker_stub_request, _conn, @write, body, _opts}

    assert Jason.decode!(body) == %{
             "action" => "switch",
             "id" => @p1,
             "state" => "off",
             "actor" => "operator"
           }

    await(view, "and it is out of the air")
    assert render(view) =~ "the shelf reads back #{@p1_text}, and it is out of the air"
  end

  test "taking a phrase away is written as the operator, and confirmed by the away list" do
    stub_verb_lands(:away)
    {:ok, view, _html} = live(build_conn(), "/hypnosis-phone")
    await(view, @p1_text)

    render_click(view, "act", %{"verb" => "take_away", "id" => @p1})

    assert_received {:broker_stub_request, _conn, @write, body, _opts}

    assert Jason.decode!(body) == %{
             "action" => "remove",
             "id" => @p1,
             "actor" => "operator"
           }

    await(view, "the record of it survives")
    assert render(view) =~ "the shelf reads back #{@p1_text}, taken away"
    assert render(view) =~ "Taken away"
  end

  # A write the shelf did not take is not a confirmation: the sentence reports what the
  # shelf still holds.
  test "a write the shelf did not take says what the shelf still holds" do
    stub_verb_lands(:unchanged)
    {:ok, view, _html} = live(build_conn(), "/hypnosis-phone")
    await(view, @p1_text)

    render_click(view, "act", %{"verb" => "switch_off", "id" => @p1})

    await(view, "sent — the shelf reads back")
    html = render(view)

    assert html =~ "still in the air"
    refute html =~ "and it is out of the air"
  end

  test "a tap this screen cannot route sends nothing, and says so" do
    # The phrase is on the page, and the tap names one the card is not drawing. The
    # dispatch is direct, so this is the route and not a DOM lookup.
    view = page([phrase(id: @p1, on: true)])
    render_click(view, "act", %{"verb" => "switch_off", "id" => "not-a-phrase-on-this-shelf"})

    refute_received {:broker_stub_request, _conn, @write, _body, _opts}
    assert render(view) =~ "not on this shelf"
    assert render(view) =~ "nothing was sent"

    # And a verb this screen does not do at all — including the three that are hers.
    render_click(view, "act", %{"verb" => "reword", "id" => @p1})

    refute_received {:broker_stub_request, _conn, @write, _body, _opts}
    assert render(view) =~ "not one of the two things this screen does"
  end

  test "a tap with no phrase on it is refused, and sends nothing" do
    view = page([phrase(id: @p1, on: true)])

    render_click(view, "act", %{"verb" => "take_away"})

    refute_received {:broker_stub_request, _conn, @write, _body, _opts}
    assert render(view) =~ "no phrase on it"
  end

  # The bot's refusals name the phrase, and this screen does not improve on them.
  test "a refusal from the bot keeps the bot's own sentence" do
    stub(%{
      @read => shelf_json(%{"phrases" => [phrase(id: @p1, on: true)]}),
      @write => Jason.encode!(%{"ok" => false, "error" => "that phrase is not on her shelf"})
    })

    {:ok, view, _html} = live(build_conn(), "/hypnosis-phone")
    await(view, @p1_text)

    render_click(view, "act", %{"verb" => "take_away", "id" => @p1})

    await(view, "that phrase is not on her shelf")
    assert render(view) =~ "that phrase is not on her shelf"
  end

  # A dead broker is not a refusal, and the log line names the reason without the screen
  # pretending the bot said no.
  test "a broker that never carried the write says nothing was recorded" do
    stub(%{
      @read => shelf_json(%{"phrases" => [phrase(id: @p1, on: true)]}),
      @write => {:error, :no_broker}
    })

    {:ok, view, _html} = live(build_conn(), "/hypnosis-phone")
    await(view, @p1_text)

    log =
      capture_log(fn ->
        render_click(view, "act", %{"verb" => "switch_off", "id" => @p1})
        assert render(view) =~ "nothing was recorded"
      end)

    assert log =~ "[HypnosisShelf] a write answered nothing: the broker is not reachable"
    refute render(view) =~ "the shelf reads back"
  end
end
