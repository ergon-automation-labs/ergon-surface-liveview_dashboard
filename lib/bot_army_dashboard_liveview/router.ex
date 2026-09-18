defmodule BotArmyDashboardLiveview.Router do
  use Phoenix.Router
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, {BotArmyDashboardLiveview.Layouts, :root})
  end

  scope "/", BotArmyDashboardLiveview do
    pipe_through(:browser)

    live("/", DashboardLive)
    live("/fitness-handheld", FitnessHandheldLive)
    live("/gtd-handheld", GTDHandheldLive)
    live("/system-health-handheld", SystemHealthHandheldLive)
  end
end
