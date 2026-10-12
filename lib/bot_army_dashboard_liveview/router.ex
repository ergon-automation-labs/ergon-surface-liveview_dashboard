defmodule BotArmyDashboardLiveview.Router do
  use Phoenix.Router
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    # Seeds the CSRF token into the session and loads its state into the request
    # process. Two things depend on it and neither fails loudly without it:
    # the session cookie (Plug.Session writes one only when the session changed,
    # so without this no cookie is ever set) and the meta tag the layout exposes.
    # Phoenix's socket transport reads both back on the websocket upgrade —
    # `connect_session/3` requires a `_csrf_token` param AND the matching state in
    # the cookie's session, and returns `nil` ("session was misconfigured") when
    # either is missing, which LiveView answers by reloading the page forever.
    plug(:protect_from_forgery)
    plug(:put_root_layout, {BotArmyDashboardLiveview.Layouts, :root})
  end

  scope "/", BotArmyDashboardLiveview do
    pipe_through(:browser)

    # Every screen gets `assign(:read_error, nil)` and the one hook that reports a
    # failed read. All the routes are in one session so that navigating between
    # them stays a live navigation rather than a full page load.
    live_session :screens, on_mount: {BotArmyDashboardLiveview.ReadHooks, :default} do
      live("/", DashboardLive)
      live("/household-hud", HouseholdHUDLive)
      live("/party-phone", PartyPhoneLive)
      # The party built from her phone. `/party-phone` draws the window the party is in; with
      # no party there is no window, so this is the screen that makes one — and the link
      # between them goes both ways.
      live("/party-select-phone", PartySelectPhoneLive)
      live("/yearning-phone", YearningPhoneLive)
      live("/body-phone", BodyPhoneLive)
      live("/devotion-phone", DevotionPhoneLive)
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

    # Two paths here used to be screens. The shelf's own page is gone because the shelf is
    # drawn inside the window now, and it was never on the bar; the wardrobe's is gone
    # because the closet is hers, on her own panel behind her own link, and a screen on an
    # open surface that could put a set on her *and claim whose voice it was* was the wrong
    # half of that. Both are answered by `BotArmyDashboardLiveview.Retired`, which turns a
    # bookmark into the move rather than a 404. Neither is in `live_session`, because there
    # is no screen behind either one.
    get("/hypnosis-phone", Retired, [])
    get("/wardrobe-phone", Retired, [])
  end
end
