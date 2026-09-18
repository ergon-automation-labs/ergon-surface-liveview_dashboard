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
    live("/energy-mood-handheld", EnergyMoodHandheldLive)
    live("/timer-handheld", TimerHandheldLive)
    live("/habit-anchors", HabitAnchorsLive)
    live("/quest-status", QuestStatusLive)
    live("/reflection", ReflectionLive)
    live("/timer-phone", TimerPhoneLive)
    live("/habits-phone", HabitsPhoneLive)
    live("/quest-phone", QuestPhoneLive)
    live("/reflect-phone", ReflectPhoneLive)
    live("/energy-mood-phone", EnergyMoodPhoneLive)
    live("/fitness-phone", FitnessPhoneLive)
    live("/system-health-phone", SystemHealthPhoneLive)
    live("/gtd-phone", GtdPhoneLive)
    live("/session-history-phone", SessionHistoryPhoneLive)
  end
end
