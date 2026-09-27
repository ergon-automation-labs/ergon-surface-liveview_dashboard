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

  A path this module does not know is a 404 and says so. That is not a screen either,
  but it is not a lie about one.
  """

  import Plug.Conn

  @moved %{
    "/hypnosis-phone" => "/party-phone?moved=shelf"
  }

  def init(opts), do: opts

  def call(conn, _opts) do
    case Map.fetch(@moved, normalize(conn.request_path)) do
      {:ok, to} ->
        conn
        |> put_resp_header("location", to)
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

  @doc """
  Where a retired path goes, for the tests and for anything that has to name it.
  """
  def moved_to(path), do: Map.get(@moved, normalize(path))
end
