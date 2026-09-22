defmodule BotArmyDashboardLiveview.SurfaceShellTest do
  use ExUnit.Case, async: true

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

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
