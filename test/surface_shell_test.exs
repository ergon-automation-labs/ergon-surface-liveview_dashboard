defmodule BotArmyDashboardLiveview.SurfaceShellTest do
  use ExUnit.Case, async: true

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Plug.Conn, only: [get_resp_header: 2]

  @endpoint BotArmyDashboardLiveview.Endpoint

  # The shell every LiveView page on this surface is served inside. Two defects
  # lived here, and both were invisible from the server side: the pages rendered
  # 200 with the right HTML, and only a real browser showed the page frozen.

  # The CDN build of Phoenix LiveView defines the `LiveView` namespace, not a bare
  # `LiveSocket` global. Naming the wrong one throws "LiveSocket is not defined",
  # the socket never connects, and every page freezes at its first render — so a
  # screen that asks the bot a question can say "asking…" forever while the bot
  # answers. Asserting on the shell's script is the closest a hermetic test gets
  # to the browser.
  test "the shell builds its socket from a global that exists" do
    {:ok, _view, html} = live(build_conn(), "/household-hud")

    assert html =~ "LiveView.LiveSocket"
    refute html =~ "new LiveSocket("
  end

  # The bootstrap reads `Phoenix` and `LiveView`, which arrive in the two deferred
  # CDN scripts above it. `defer` is ignored on an inline script, so this block ran
  # during parsing, before either library existed, and threw "Phoenix is not
  # defined" — the same frozen page by a different route. Booting on
  # DOMContentLoaded is what makes the ordering a guarantee instead of a race.
  test "the shell waits for the libraries it depends on" do
    {:ok, _view, html} = live(build_conn(), "/household-hud")

    assert html =~ "DOMContentLoaded"
    refute html =~ ~s(<script defer type="text/javascript">)
  end

  # Phoenix's socket transport authenticates the websocket upgrade with BOTH a
  # `_csrf_token` connect param and the matching CSRF state inside the session
  # cookie. Without `protect_from_forgery` there is no token to publish and —
  # because Plug.Session only writes a cookie when the session changed — no
  # cookie either, so `connect_session/3` returns nil and every mount is refused
  # with "LiveView session was misconfigured". LiveView answers that by reloading
  # the page; the browser reloaded `/household-hud` 1060 times in fifteen minutes.
  test "the shell hands the socket a csrf token and a session to match it" do
    conn = get(build_conn(), "/household-hud")

    assert %{status: 200} = conn

    assert [_whole, token] =
             Regex.run(~r/<meta name="csrf-token" content="([^"]+)"/, conn.resp_body)

    assert byte_size(token) > 20

    assert cookie = get_resp_header(conn, "set-cookie") |> List.first()
    assert cookie =~ "_dashboard_key="

    # and the script actually forwards that meta tag to the socket
    assert conn.resp_body =~ ~s(meta[name='csrf-token'])
  end

  # The layout links two stylesheets out of `priv/static/css`, and `Plug.Static`'s
  # `only` list decides whether they can be served. It left `css` out, so both
  # links 404'd on every page: dead styling, plus console errors that masked a real
  # failure while debugging this surface.
  test "the stylesheets the shell links are actually served" do
    for path <- ["/css/carousel.css", "/css/phone_responsive.css"] do
      assert %{status: 200} = get(build_conn(), path),
             "#{path} is linked by the layout but not served"
    end
  end
end
