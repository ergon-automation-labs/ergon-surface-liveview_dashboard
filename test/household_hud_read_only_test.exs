defmodule BotArmyDashboardLiveview.HouseholdHUDReadOnlyTest do
  # The household HUD reads; her own numbers are reported on `/timer-phone`. That
  # split is a design decision (a reading screen and a reporting screen are not
  # the same screen), and a decision nobody can break by accident is a pin.
  #
  # The stub harness is the same one the two moved report tests use: one reply
  # answers every subject, so this module is not async.
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias BotArmyDashboardLiveview.BrokerStub

  @endpoint BotArmyDashboardLiveview.Endpoint
  @app :bot_army_dashboard_liveview
  @hud "lib/bot_army_dashboard_liveview/live/household_hud_live.ex"
  @words ["none", "a little", "some", "a lot", "a great deal", "as much as it gets"]

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

  defp bot_scale do
    @words
    |> Enum.with_index()
    |> Enum.map(fn {word, level} -> %{"level" => level, "label" => word} end)
  end

  defp state_reply do
    body = %{
      "kinds" =>
        Enum.map(~w(arousal breathing hands pulse cage), fn key ->
          %{"key" => key, "label" => String.capitalize(key)}
        end),
      "scale" => bot_scale(),
      "max_level" => 5,
      "latest" => %{
        "arousal" => nil,
        "breathing" => nil,
        "hands" => nil,
        "pulse" => nil,
        "cage" => nil
      },
      "recent" => [],
      "any_reported?" => false
    }

    Jason.encode!(%{
      "ok" => true,
      "data" => %{
        "louiza" => %{
          "yearning" => %{
            "level" => 3,
            "reported_today" => true,
            "occurred_on" => "2026-09-25"
          }
        },
        "body" => body
      }
    })
  end

  defp hud do
    Application.put_env(@app, :broker_stub_reply, state_reply())
    {:ok, view, _html} = live(build_conn(), "/household-hud")
    await(view, "The body")
    view
  end

  defp await(view, text), do: await(view, text, 50)

  defp await(_view, text, 0), do: flunk("the screen never showed #{inspect(text)}")

  defp await(view, text, tries) do
    if render(view) =~ text do
      :ok
    else
      Process.sleep(10)
      await(view, text, tries - 1)
    end
  end

  # The read stays: the house's own numbers for both, which is what a view of the
  # house is for.
  test "still reads both: the yearning indicator and the body channels" do
    html = render(hud())

    assert html =~ "Yearning Active"
    assert html =~ "3 of 5"
    assert html =~ "The body — 5 channels"

    for key <- ~w(arousal breathing hands pulse cage) do
      assert html =~ String.capitalize(key)
    end
  end

  # The write goes: no ladder, no legend, no button that claims to log anything.
  # A button that opens a write this screen no longer owns is worse than no
  # button, because it would appear to work.
  test "offers no tap, and no six-point ladder" do
    html = render(hud())

    refute html =~ ~s(phx-click="record_yearning")
    refute html =~ ~s(phx-click="record_body_reading")
    refute html =~ "tap-row"
    refute html =~ "tap a point to log it"
    refute html =~ ~s(phx-value-level="4")
  end

  # Both cards say where the reporting happens, so the absence reads as a
  # decision rather than as a screen that lost a feature.
  test "says where the reporting happens" do
    html = render(hud())

    assert html =~ "She taps it on her own screen"
    assert html =~ "She logs these on her own screen"
  end

  # The source-level half: the screen must not even know the write subjects, so a
  # future edit cannot quietly grow a write path back onto the view.
  test "the screen does not carry the write subjects at all" do
    source = File.read!(@hud)

    refute source =~ "record_goddess_proximity"
    refute source =~ "record_body_reading"
    refute source =~ "record_yearning"
  end
end
