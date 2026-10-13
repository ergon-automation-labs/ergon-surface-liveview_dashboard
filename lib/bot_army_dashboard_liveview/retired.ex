defmodule BotArmyDashboardLiveview.Retired do
  @moduledoc """
  The paths that used to be a screen, and where they went.

  A screen is retired when the thing it drew is drawn somewhere better, and a path that
  stops existing is not retired — it is a 404. This dashboard is a phone app with a home
  screen and bookmarks on it, so a path that used to work still gets opened months after
  the screen behind it moved. Answering that with a 404 turns *the shelf is in the window
  now* into *you typed it wrong*, which is the wrong sentence and the wrong feeling.

  So the path stays, and it answers with the one thing it still knows: where the screen
  went. The destination carries `moved=shelf`, and the screen that receives it says in
  its own words what moved and why — a redirect that lands somewhere unexplained is only
  a slightly nicer 404.

  ## A move does not have to stay on this surface

  The wardrobe's screen is retired too, and it went further than the window did: what it
  drew — the closet, what is on her, and the two ways a set can get there — is *hers*, on
  her own control panel, behind her own link. So this map has two kinds of destination,
  and the difference is not decoration. `{:same_host, path}` is a place on this dashboard,
  and it is relative on purpose: whichever host the bookmark arrived on is the host the
  screen behind it is served from. `:her_closet`, `:her_reports`, `:her_tasks`,
  `:her_reflect` and `:her_energy` are **different origins**, so they cannot be relative — a relative hop
  would land on this dashboard's own `/?tab=closet`, which no screen here holds. They are
  built from the arriving host by `HerPanel`, for the same reason the house screen's exit
  link is: `localhost` in an address a phone opened is the phone.

  ## The reports went the same way, for the same reason

  Five paths are retired into her panel's **How I am** group: `/yearning-phone`,
  `/body-phone` (which also carried the escape card), `/devotion-phone`, `/habits-phone`
  and `/habit-anchors`. Every one of them *made* one of her reports, and the bot files all
  of them under `:slave` without being told — so the page that sent the write was the only
  thing here that knew whose hand was on the screen, and this surface is open. The closet
  was the same defect with a name attached; these had none, which is the worse half.

  They all land on the same group, and that is deliberate rather than a shortcut: the
  distinction worth keeping is *where her own numbers live*, and one group she can
  recognise is a better answer to a bookmark than five addresses that have to be right.

  A path this module does not know is a 404 and says so. That is not a screen either,
  but it is not a lie about one.

  ## The GTD screen is the same move, and the smaller half of the same defect

  Two paths are retired into her panel's **Tasks** group: `/gtd-phone` and
  `/gtd-handheld`. What they drew was not one of her reports but the box her tasks live
  in — a list, a defer and a done over `bridge.task.*` — and her panel's Tasks group draws
  that box with those verbs, which is what makes this a move rather than a second copy.
  Their writes did carry an identity (`slave`, through the bridge), so this is the smaller
  half of the reports' defect rather than the same one. What remains is the count: two
  screens drawing one list are two answers to *what should I do next*, and the one on the
  open surface is the one nobody is holding.

  ## The reflect screens are the reports' defect exactly, and the worst of them

  Two paths are retired into her panel's **Reflect** group: `/reflection` (the desk screen)
  and `/reflect-phone`. These are not the smaller half of anything. Both screens wrote
  `companion.reflections.capture` — her own words, in her own journal — from a surface
  anyone on the network can reach, and neither one carries an identity at all: the store
  knows a reflection's text, its prompt and a `dedupe_key`, and it has **no notion of a
  person** (the only handle on a row is that key). So the page that sent the write was the
  entire answer to *whose words are these*, and it was the page on the open surface. The
  five report screens at least had a name on the wire; these had none.

  Her panel holds that write under her session's own identity (`slave`, the hand she uses
  it with — §47 of the bot's control surface contract), and it draws the same three things
  the retired pair drew: the prompt she is asked, the journal as the confirmation of a
  write, and the companion's answer when it lands. Both paths therefore answer with a move
  into that group. Nothing about the reading is lost: the two screens *read* the same
  subjects the panel reads, and the panel's own group is one she is holding.

  ## The energy screens confirmed nothing, which is why they cannot stay

  Two paths are retired into her panel's **Energy** group: `/energy-mood-phone` and
  `/energy-mood-handheld`. They are not the reports' defect — they carried an identity on
  the wire, and the reading they sent was about her rather than a decision about her — and
  they are not the GTD pair either, where the cost was two answers to one question. Their
  own defect is narrower and worse for being invisible: the check-in was sent by
  `Gnat.pub/3` to `events.context.updated`, a publish with no reply. `:ok` from a publish
  means the bytes reached the socket, not that a bot received them and not that anything
  was stored — and with no subscriber that day the bytes reached nobody at all. The screen
  drew **"Context saved"** over that, so the one thing a check-in has to be able to say,
  *it was kept*, was the one thing this screen could not know.

  Her panel's Energy group asks `wife_care.energy.record` (§49) instead: the reply is the
  bot's own answer, a refusal arrives in the bot's words rather than as a silent no-op, and
  the card above is redrawn from the reading the bot now holds. The three ways of recording
  nothing are three different sentences there, which is the whole point: a failed read is
  not "no reading", and a word the bot has never been given is not a zero.

  ## The timer and the quest are the pair this map's shape argued against

  Four paths are retired into her panel's **Timers** and **Quest** groups: `/timer-phone`,
  `/timer-handheld`, `/quest-phone` and `/quest-status`. They are the first retires here that
  are *not* the reports' defect — and saying which defect they are is what keeps the map
  honest. The timer's write carried an identity (`events.timer.session_completed`, filed under
  the name the surface claimed) and the quest's was a read, so no journal was written from an
  open surface. Their cost is the other half of the same coin, twice over.

  The timer screens had the **energy** defect: the session was filed as a `events.timer.*`
  event — a `Gnat.pub/3` with no reply — so the confirmation was a byte that had reached the
  socket, and the running session's own id lived in the LiveView's state, where a reload
  took it. That is why the fix is not a gate either: her panel's Timers group holds the
  session **in the bridge** (`bridge.timer.list` and a 24h age-based sweep, §51), which is
  the only place a session can survive a page it is not in.

  The quest screens had the **GTD** defect, and the worst half of it: `/quest-phone` drew a
  progress bar and `/quest-status` a streak — a board-shaped view of how much is done, which
  is the view the panel refuses for exactly the reason a list of nineteen things is where a
  foggy person gives up. Her panel's Quest group draws the open steps and counts the rows it
  drew (§50). Both pairs are therefore moves rather than gates, and each path hands its
  bookmark to the group that holds what it was about.
  """

  import Plug.Conn

  alias BotArmyDashboardLiveview.HerPanel

  @moved %{
    "/hypnosis-phone" => {:same_host, "/party-phone?moved=shelf"},
    "/wardrobe-phone" => :her_closet,
    "/yearning-phone" => :her_reports,
    "/body-phone" => :her_reports,
    "/devotion-phone" => :her_reports,
    "/habits-phone" => :her_reports,
    "/habit-anchors" => :her_reports,
    "/gtd-phone" => :her_tasks,
    "/gtd-handheld" => :her_tasks,
    "/reflection" => :her_reflect,
    "/reflect-phone" => :her_reflect,
    "/energy-mood-phone" => :her_energy,
    "/energy-mood-handheld" => :her_energy,
    "/timer-phone" => :her_timer,
    "/timer-handheld" => :her_timer,
    "/quest-phone" => :her_quest,
    "/quest-status" => :her_quest
  }

  def init(opts), do: opts

  def call(conn, _opts) do
    case Map.fetch(@moved, normalize(conn.request_path)) do
      {:ok, destination} ->
        conn
        |> put_resp_header("location", location(destination, conn.host))
        |> put_resp_content_type("text/html")
        |> send_resp(302, "")
        |> halt()

      :error ->
        conn
        |> put_resp_content_type("text/html")
        |> send_resp(404, "")
        |> halt()
    end
  end

  # A trailing slash is the same path, and a bookmark may carry one.
  defp normalize(path), do: String.trim_trailing(path, "/")

  defp location({:same_host, path}, _host), do: path
  defp location(:her_closet, host), do: HerPanel.closet_url_from_host(host)
  defp location(:her_reports, host), do: HerPanel.how_i_am_url_from_host(host)
  defp location(:her_tasks, host), do: HerPanel.tasks_url_from_host(host)
  defp location(:her_reflect, host), do: HerPanel.reflect_url_from_host(host)
  defp location(:her_energy, host), do: HerPanel.energy_url_from_host(host)
  defp location(:her_timer, host), do: HerPanel.timer_url_from_host(host)
  defp location(:her_quest, host), do: HerPanel.quest_url_from_host(host)

  @doc """
  Where a retired path goes, for the tests and for anything that has to name it.

  A same-host destination is returned as the relative path it is. Hers are returned as
  the *kind*, not as a URL: they depend on the host the bookmark arrived on, so an answer
  computed with no request behind it would be an address for the wrong machine — the one
  thing this module exists to avoid. Callers that want the address have to supply a host.
  """
  def moved_to(path), do: Map.get(@moved, normalize(path))

  @doc "The address a bookmark to `path` is sent to, from the host it arrived on."
  def location_for(path, host), do: Map.fetch(@moved, normalize(path)) |> location_or_nil(host)

  defp location_or_nil({:ok, destination}, host), do: location(destination, host)
  defp location_or_nil(:error, _host), do: nil
end
