defmodule BotArmyDashboardLiveview.HerPanelTest do
  use ExUnit.Case, async: false

  alias BotArmyDashboardLiveview.HerPanel

  # The env override is read at call time, so a test that sets it has to put it back —
  # and `async: false` is not decoration: this is process-wide state, and a test that
  # changed it under another one's feet would fail somewhere else entirely.
  setup do
    previous = System.get_env("WIFE_CARE_CONTROL_PANEL_URL")

    on_exit(fn ->
      if previous, do: System.put_env("WIFE_CARE_CONTROL_PANEL_URL", previous)
      if is_nil(previous), do: System.delete_env("WIFE_CARE_CONTROL_PANEL_URL")
    end)

    :ok
  end

  test "the panel's address is built from the host the request arrived on" do
    # Not localhost: from a phone, localhost is the phone. That mistake is how a working
    # panel came to look like one that did not exist.
    assert HerPanel.url(URI.parse("http://192.168.1.50:30011/household-hud")) ==
             "http://192.168.1.50:30014"

    assert HerPanel.url_from_host("192.168.1.50") == "http://192.168.1.50:30014"
  end

  test "a request with no usable host falls back to localhost, which is right when it is local" do
    assert HerPanel.url(nil) == "http://localhost:30014"
    assert HerPanel.url(URI.parse("/household-hud")) == "http://localhost:30014"
    assert HerPanel.url_from_host(nil) == "http://localhost:30014"
    assert HerPanel.url_from_host("") == "http://localhost:30014"
  end

  test "the closet, the reports, the tasks, the reflect, the energy, the timer, the quest and the fitness are one address each, and absolute" do
    # A different port is a different origin, so none of these can ever be a relative path:
    # `/?tab=timer` on this dashboard is a group no screen here holds.
    for {url, tab} <- [
          {HerPanel.closet_url_from_host("192.168.1.50"), "closet"},
          {HerPanel.how_i_am_url_from_host("192.168.1.50"), "how_i_am"},
          {HerPanel.tasks_url_from_host("192.168.1.50"), "tasks"},
          {HerPanel.reflect_url_from_host("192.168.1.50"), "reflect"},
          {HerPanel.energy_url_from_host("192.168.1.50"), "energy"},
          {HerPanel.timer_url_from_host("192.168.1.50"), "timer"},
          {HerPanel.quest_url_from_host("192.168.1.50"), "quest"},
          {HerPanel.fitness_url_from_host("192.168.1.50"), "fitness"}
        ] do
      assert url == "http://192.168.1.50:30014/?tab=#{tab}"
      refute String.starts_with?(url, "/")
    end

    assert HerPanel.closet_url(URI.parse("http://192.168.1.50:30011/")) =~ ":30014/?tab=closet"
    assert HerPanel.timer_url(URI.parse("http://192.168.1.50:30011/")) =~ ":30014/?tab=timer"
    assert HerPanel.quest_url(URI.parse("http://192.168.1.50:30011/")) =~ ":30014/?tab=quest"
    assert HerPanel.fitness_url(URI.parse("http://192.168.1.50:30011/")) =~ ":30014/?tab=fitness"
  end

  test "WIFE_CARE_CONTROL_PANEL_URL replaces the host and the port together" do
    # Both, not just the port: a value that only replaced the port could not express
    # `https://`, and a deployment reached through a name or a proxy is exactly the case
    # the dashboard cannot infer from the request it got.
    System.put_env("WIFE_CARE_CONTROL_PANEL_URL", "https://panel.example.com")

    assert HerPanel.url_from_host("192.168.1.50") == "https://panel.example.com"
    assert HerPanel.url(URI.parse("http://192.168.1.50:30011/")) == "https://panel.example.com"

    assert HerPanel.closet_url_from_host("192.168.1.50") ==
             "https://panel.example.com/?tab=closet"
  end
end
