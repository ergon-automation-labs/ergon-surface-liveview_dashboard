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
      live("/fitness-handheld", FitnessHandheldLive)
      live("/system-health-handheld", SystemHealthHandheldLive)
      live("/timer-handheld", TimerHandheldLive)
      live("/quest-status", QuestStatusLive)
      live("/timer-phone", TimerPhoneLive)
      live("/quest-phone", QuestPhoneLive)
      live("/fitness-phone", FitnessPhoneLive)
      live("/system-health-phone", SystemHealthPhoneLive)
      live("/session-history-phone", SessionHistoryPhoneLive)
    end

    # Thirteen paths here used to be screens. The shelf's own page is gone because the shelf is
    # drawn inside the window now, and it was never on the bar; the wardrobe's is gone
    # because the closet is hers, on her own panel behind her own link, and a screen on an
    # open surface that could put a set on her *and claim whose voice it was* was the wrong
    # half of that. The five report screens are gone for the same defect without even a
    # name: `record_body_reading`, `record_goddess_proximity`, `record_hygiene_event` and
    # the three cage writes are all filed by the bot under `:slave`, so the page that sent
    # the write was the only thing that knew whose hand was on the screen — and this
    # surface is open. Her panel makes all five reports behind her own link now.
    #
    # The GTD pair went the same way for the smaller half of that reason. `/gtd-phone` and
    # `/gtd-handheld` drew the box her tasks live in — a list, a defer and a done over
    # `bridge.task.*` — and her panel's Tasks group draws that box with the same verbs. Two
    # screens drawing one list are two answers to *what should I do next*, and the one on
    # the open surface is the one nobody is holding (§45).
    #
    # `/reflection` and `/reflect-phone` are the report screens' defect exactly, and the
    # worst of the set: both wrote `companion.reflections.capture` — her own words, in her
    # own journal — with **no identity in the write at all**. A reflection knows text, a
    # prompt and a `dedupe_key`; it has no notion of a person, so the page that sent the
    # write was the whole answer to *whose words are these*. Her panel holds that write
    # under her own login and draws the same question, box and journal (§47).
    #
    # `/energy-mood-phone` and `/energy-mood-handheld` are the narrowest defect of the set,
    # and the quietest. Their check-in was a `Gnat.pub/3` to `events.context.updated` — a
    # publish with no reply — so "Context saved" was drawn over a byte that only had to
    # reach the socket, and with no subscriber it reached nobody. The energy reading is
    # about her rather than a decision about her, so the fix is not a gate; it is asking
    # `wife_care.energy.record` and reading the reading back, which is what her panel's
    # Energy group does (§49), and where both paths now send their bookmarks.
    #
    # All of them are answered by `BotArmyDashboardLiveview.Retired`, which turns a
    # bookmark into the move rather than a 404. None is in `live_session`, because there
    # is no screen behind any one of them.
    get("/hypnosis-phone", Retired, [])
    get("/wardrobe-phone", Retired, [])
    get("/yearning-phone", Retired, [])
    get("/body-phone", Retired, [])
    get("/devotion-phone", Retired, [])
    get("/habits-phone", Retired, [])
    get("/habit-anchors", Retired, [])
    get("/gtd-phone", Retired, [])
    get("/gtd-handheld", Retired, [])
    get("/reflection", Retired, [])
    get("/reflect-phone", Retired, [])
    get("/energy-mood-phone", Retired, [])
    get("/energy-mood-handheld", Retired, [])
  end
end
