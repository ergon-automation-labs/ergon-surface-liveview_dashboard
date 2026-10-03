defmodule BotArmyDashboardLiveview.ReflectionDeskReadTest do
  @moduledoc """
  The reflection desk reads as well as writes.

  Same lane as the phone, same store, same law: the desk's success line is drawn from
  the row the store returned and the re-read after it, never from the write's own ok.
  It used to publish `events.reflection.captured` and print a tick on the broker's
  `:ok`, which told her nothing about whether her words were kept.

  `async: false` because the stub is installed through application env.
  """

  use ExUnit.Case, async: false

  @moduletag :core

  @endpoint BotArmyDashboardLiveview.Endpoint

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias BotArmyDashboardLiveview.BrokerStub

  @app :bot_army_dashboard_liveview

  @line "the desk remembers"
  @answer "It said: it does."

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

  defp row(overrides \\ %{}) do
    Map.merge(
      %{
        "id" => "5f1a0f2e-3333-4000-8000-000000000001",
        "text" => @line,
        "chars" => String.length(@line),
        "stored_at" => "2026-10-03T21:00:00Z",
        "answer" => %{"state" => "pending"}
      },
      overrides
    )
  end

  defp list_body(rows),
    do: Jason.encode!(%{"reflections" => rows, "count" => length(rows)})

  defp await(view, text, tries \\ 80) do
    if render(view) =~ text do
      :ok
    else
      if tries == 0, do: flunk("the desk never showed #{inspect(text)}")
      Process.sleep(10)
      await(view, text, tries - 1)
    end
  end

  defp write(view, text) do
    render_change(view, "update-reflection", %{"reflection" => text})
    render_hook(view, "gamepad-a", %{})
    render_hook(view, "gamepad-a", %{})
  end

  test "the desk shows the reflections the store already holds" do
    install_reply(list_body([row()]))

    {:ok, view, _html} = live(build_conn(), "/reflection")

    await(view, @line)
    assert render(view) =~ "Eir is reading it"
    refute render(view) =~ "Nothing written yet"
  end

  test "a store that refuses to list is a refusal, never an empty desk" do
    install_reply(
      Jason.encode!(%{
        "ok" => false,
        "code" => "unavailable",
        "error" => "the reflection store could not be reached"
      })
    )

    {:ok, view, _html} = live(build_conn(), "/reflection")

    await(view, "Your earlier reflections are not shown")
    assert render(view) =~ "the reflection store could not be reached"
    refute render(view) =~ "Nothing written yet"
  end

  test "one press is the confirmation card, and it sends nothing" do
    install_reply(list_body([]))

    {:ok, view, _html} = live(build_conn(), "/reflection")

    render_change(view, "update-reflection", %{"reflection" => @line})
    render_hook(view, "gamepad-a", %{})

    assert render(view) =~ "Save this reflection?"
    refute_receive {:broker_stub_request, _, "companion.reflections.capture", _, _}, 50
  end

  test "the second press writes to the store and the confirmation is the re-read" do
    install_reply(
      {:answers,
       fn
         "companion.reflections.capture" ->
           Jason.encode!(%{"reflection" => row()})

         "companion.reflections.list" ->
           list_body([row(%{"answer" => %{"state" => "answered", "text" => @answer}})])

         "companion.reflections.read" ->
           Jason.encode!(%{
             "reflection" => row(%{"answer" => %{"state" => "answered", "text" => @answer}})
           })

         _other ->
           "{}"
       end}
    )

    {:ok, view, _html} = live(build_conn(), "/reflection")

    write(view, @line)

    assert_receive {:broker_stub_request, _, "companion.reflections.capture", payload, _opts}
    assert Jason.decode!(payload)["text"] == @line
    refute Jason.decode!(payload) |> Map.has_key?("timestamp")

    await(view, @answer)
    refute render(view) =~ "Reflection captured"
    refute_receive {:broker_stub_request, _, "companion.reflections.capture", _, _}, 50
  end

  test "a write the store refused is never drawn as a save" do
    install_reply(
      {:answers,
       fn
         "companion.reflections.capture" ->
           Jason.encode!(%{"ok" => false, "error" => "a reflection needs words in it"})

         _other ->
           list_body([])
       end}
    )

    {:ok, view, _html} = live(build_conn(), "/reflection")

    write(view, @line)

    await(view, "Nothing was saved")
    assert render(view) =~ "a reflection needs words in it"
    assert render(view) =~ @line
  end

  test "an empty page is refused without asking the store" do
    install_reply(list_body([]))

    {:ok, view, _html} = live(build_conn(), "/reflection")

    render_hook(view, "gamepad-a", %{})

    assert render(view) =~ "nothing to save"
    refute_receive {:broker_stub_request, _, "companion.reflections.capture", _, _}, 50
  end
end
