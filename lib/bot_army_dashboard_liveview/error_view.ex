defmodule BotArmyDashboardLiveview.ErrorView do
  def render("500.html", _assigns) do
    "<h1>Internal Server Error</h1>"
  end

  def render("404.html", _assigns) do
    "<h1>Not Found</h1>"
  end

  def render(_template, _assigns) do
    "<h1>Error</h1>"
  end
end
