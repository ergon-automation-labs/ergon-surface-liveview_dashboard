defmodule BotArmyDashboardLiveview.ErrorHTML do
  def render("500.html", _assigns) do
    """
    <div style="padding: 20px; color: #e0e0e0;">
      <h1>Internal Server Error</h1>
      <p>Something went wrong. Please try again.</p>
    </div>
    """
  end

  def render("404.html", _assigns) do
    """
    <div style="padding: 20px; color: #e0e0e0;">
      <h1>Page Not Found</h1>
    </div>
    """
  end

  def render(_template, _assigns) do
    """
    <div style="padding: 20px; color: #e0e0e0;">
      <h1>Error</h1>
      <p>Unknown error.</p>
    </div>
    """
  end
end
