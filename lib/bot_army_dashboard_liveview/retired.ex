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
  screen behind it is served from. `:her_closet` and `:her_reports` are **different
  origins**, so they cannot be relative — a relative hop would land on this dashboard's
  own `/?tab=closet`, which no screen here holds. They are built from the arriving host by
  `HerPanel`, for the same reason the house screen's exit link is: `localhost` in an
  address a phone opened is the phone.

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
    "/habit-anchors" => :her_reports
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
