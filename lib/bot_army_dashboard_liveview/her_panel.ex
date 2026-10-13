defmodule BotArmyDashboardLiveview.HerPanel do
  @moduledoc """
  Where her own control panel is — one place that knows, for every screen here that
  has to point at it.

  The household runs two instances of one wife-care release: the authority's panel
  and hers. This dashboard is the phone she carries, so when it points anywhere it
  points at *hers*. That address was written into the house screen alone until this
  module existed, which was fine while one screen pointed at it and wrong the moment
  a second one did — the retirement map now sends a bookmarked wardrobe address
  across to her closet, and two copies of a host and a port are two places to forget.

  ## The host is this request's host, and that is the whole point

  From a phone or a second machine, `localhost` is the *viewer's* machine, where no
  panel runs. A link built that way is how a working panel came to look like one that
  did not exist. So both entry points take the host the surface was reached on:
  `url/1` from a LiveView's `socket.host_uri`, `url_from_host/1` from a Plug
  connection's `host` string. A request that arrived with no usable host falls back
  to `localhost`, which is right when the surface *is* localhost and merely useless
  otherwise — and useless is the honest failure for a link, where raising would take
  down the screen that was only trying to point somewhere.

  ## `WIFE_CARE_CONTROL_PANEL_URL` overrides both

  For a deployment where the panel is reached under a name or a proxy the dashboard
  cannot infer from the request it got. It replaces host *and* port together, because
  a value that only replaced the port could not express `https://…`.

  ## Eight groups, because one place now answers several paths

  The closet's address was the first one a screen needed, the reports' address is the
  second — five screens on this dashboard used to *make* her reports, and all five are
  retired into her panel's **How I am** group — and the tasks' address is the third: the
  GTD screen here drew a list, a defer and a done over `bridge.task.*`, and her panel's
  **Tasks** group is the same box with the same verbs. The reflect screens are the fourth:
  they wrote her own words into her journal, with no identity in the write at all, and her
  panel's **Reflect** group is where that write belongs now. The energy screen is the fifth,
  and the smallest of the five: it drew the last reading and filed a check-in by *publishing*
  `events.context.updated` — a byte on a socket that no subscriber had to receive — so the
  "Context saved" it showed confirmed nothing, and when the panel was asked instead it
  answered honestly. Her panel's **Energy** group asks `wife_care.energy.record` and reads
  the reading back off the bot's own reply (§49).

  The timer and the quest make seven, and they are the pair this map's shape argued *against*.
  Neither screen had the reports' defect: the timer's write carried `slave` and the quest's
  was a read, so nothing was filed under the wrong hand and no journal was written from an
  open surface. What they cost was the other half of the same coin — the timer screen filed
  its session through a publish nobody had to read (the energy defect exactly, in a second
  place), and the quest screen drew a progress bar and a streak over the box her tasks live
  in, which is the board-shaped view the panel refuses (the GTD defect). So both are moves
  and not gates: her panel's **Timers** group holds the session **in the bridge** rather than
  in a browser tab (§51), and its **Quest** group draws the open steps as a count (§50). A
  group has an address on her panel (§39/§44/§45/§47/§49/§50/§51 of the bot's control surface
  contract), so a bookmarked path hands the bookmark to the screen it was really about rather
  than to the panel's front door.

  The fitness pair makes eight, and it is the one group whose defect is a **word** rather than
  a write. The two screens here carried their own list of what a workout is — `@workout_types`
  and `@intensity_levels`, hard-coded in the phone view — a sixth copy of a vocabulary the bot
  itself had already retired five times over. A screen with its own list can send the bot a
  word it folds onto `"other"` and then draw the row back under the name it invented, so the
  surface and the bot disagree about what she did while both are showing her the same log. Her
  panel's **Fitness** group asks `fitness.workout.options` and draws the activities, the
  intensities **and the bot's own words for them** off the wire (§46), so the picker can only
  offer what the bot accepts and a stored row can only be named as the bot named it. That is
  the eighth group, and the only one whose fix had to reach the bot rather than the screen.
  """

  # The panel's port on this household's machines. `docs/wife_care/PANELS.md` in the
  # elixir_bots monorepo has the three-surface map, and the 30014 row is this one.
  @port 30_014

  # The closet group inside her panel. A group has an address there (§39 of the bot's
  # control surface contract), which is what lets a retired path hand a bookmark to the
  # screen it was really about rather than to the panel's front door.
  @closet "/?tab=closet"

  # The group her own reports are made in. Same reason as the closet's: each retired
  # report screen hands a bookmark to the card it was about.
  @how_i_am "/?tab=how_i_am"

  # The group her tasks are worked in. Same rule as the reports': the GTD screen here was
  # a list, a defer and a done, and the panel's Tasks group is that box.
  @tasks "/?tab=tasks"

  # The group her journal is written in. The reflect screens here wrote her words from an
  # open surface with no identity on the write; the panel's Reflect group holds that write
  # under her own login (§47), so a bookmarked path hands the bookmark to the question, the
  # box, and the journal it was about.
  @reflect "/?tab=reflect"

  # The group she gives an energy reading from. The screen here drew the last reading and
  # filed a check-in through a publish nobody had to read, so the confirmation was a byte
  # that left the socket; the panel's Energy group asks the subject and reads the reading
  # back, which is the confirmation (§49).
  @energy "/?tab=energy"

  # The group a session is run from. The screen here filed the session with a publish and
  # kept the id in the page, so a reload lost a running session and the id with it; the panel
  # asks the bridge for the list and asks it to end the one she names, and the bridge holds
  # the session itself (§51).
  @timer "/?tab=timer"

  # The group the open steps are worked from. The screen here drew a progress bar and a streak
  # over the box her tasks live in; the panel's Quest group is that same box as the quest it is
  # a window on, and counts the rows it drew rather than a percentage (§50).
  @quest "/?tab=quest"

  # The group the log is written from. The screens here carried their own vocabulary for what
  # a workout is — a sixth copy of a list the bot had already retired five times — and the panel
  # draws the bot's own words over the wire instead (§46).
  @fitness "/?tab=fitness"

  @doc "Her panel's base URL, off the host this request arrived on."
  @spec url(URI.t() | nil) :: String.t()
  def url(%URI{} = host_uri), do: base(host_of(host_uri))
  def url(_host_uri), do: base("localhost")

  @doc "The same, for a Plug connection, which carries a host string and no URI."
  @spec url_from_host(String.t() | nil) :: String.t()
  def url_from_host(host) when is_binary(host) and host != "", do: base(host)
  def url_from_host(_host), do: base("localhost")

  @doc "Her closet inside that panel, as an absolute URL — a different origin, so it must be one."
  @spec closet_url(URI.t() | nil) :: String.t()
  def closet_url(host_uri), do: url(host_uri) <> @closet

  @doc "The same, for a Plug connection."
  @spec closet_url_from_host(String.t() | nil) :: String.t()
  def closet_url_from_host(host), do: url_from_host(host) <> @closet

  @doc """
  The group her own reports are made in, as an absolute URL — a different origin, like
  the closet, so it must be one.
  """
  @spec how_i_am_url(URI.t() | nil) :: String.t()
  def how_i_am_url(host_uri), do: url(host_uri) <> @how_i_am

  @doc "The same, for a Plug connection."
  @spec how_i_am_url_from_host(String.t() | nil) :: String.t()
  def how_i_am_url_from_host(host), do: url_from_host(host) <> @how_i_am

  @doc """
  The group her tasks are worked in, as an absolute URL — a different origin, like the
  reports', so it must be one.
  """
  @spec tasks_url(URI.t() | nil) :: String.t()
  def tasks_url(host_uri), do: url(host_uri) <> @tasks

  @doc "The same, for a Plug connection."
  @spec tasks_url_from_host(String.t() | nil) :: String.t()
  def tasks_url_from_host(host), do: url_from_host(host) <> @tasks

  @doc """
  The group her reflections are written in, as an absolute URL — a different origin, like
  the reports', so it must be one.
  """
  @spec reflect_url(URI.t() | nil) :: String.t()
  def reflect_url(host_uri), do: url(host_uri) <> @reflect

  @doc "The same, for a Plug connection."
  @spec reflect_url_from_host(String.t() | nil) :: String.t()
  def reflect_url_from_host(host), do: url_from_host(host) <> @reflect

  @doc """
  The group she gives an energy reading from, as an absolute URL — a different origin, like
  the other four, so it must be one.
  """
  @spec energy_url(URI.t() | nil) :: String.t()
  def energy_url(host_uri), do: url(host_uri) <> @energy

  @doc "The same, for a Plug connection."
  @spec energy_url_from_host(String.t() | nil) :: String.t()
  def energy_url_from_host(host), do: url_from_host(host) <> @energy

  @doc """
  The group a session is run from, as an absolute URL — a different origin, like the other
  five, so it must be one.
  """
  @spec timer_url(URI.t() | nil) :: String.t()
  def timer_url(host_uri), do: url(host_uri) <> @timer

  @doc "The same, for a Plug connection."
  @spec timer_url_from_host(String.t() | nil) :: String.t()
  def timer_url_from_host(host), do: url_from_host(host) <> @timer

  @doc """
  The group the open steps are worked from, as an absolute URL — a different origin, like the
  other six, so it must be one.
  """
  @spec quest_url(URI.t() | nil) :: String.t()
  def quest_url(host_uri), do: url(host_uri) <> @quest

  @doc "The same, for a Plug connection."
  @spec quest_url_from_host(String.t() | nil) :: String.t()
  def quest_url_from_host(host), do: url_from_host(host) <> @quest

  @doc """
  The group the fitness log is written from, as an absolute URL — a different origin, like
  the other seven, so it must be one.
  """
  @spec fitness_url(URI.t() | nil) :: String.t()
  def fitness_url(host_uri), do: url(host_uri) <> @fitness

  @doc "The same, for a Plug connection."
  @spec fitness_url_from_host(String.t() | nil) :: String.t()
  def fitness_url_from_host(host), do: url_from_host(host) <> @fitness

  defp base(host) do
    System.get_env("WIFE_CARE_CONTROL_PANEL_URL") || "http://#{host}:#{@port}"
  end

  defp host_of(%URI{host: host}) when is_binary(host) and host != "", do: host
  defp host_of(_host_uri), do: "localhost"
end
