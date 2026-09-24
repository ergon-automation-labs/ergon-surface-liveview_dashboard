defmodule BotArmyDashboardLiveview.ReadError do
  @moduledoc """
  What a screen shows when a read failed.

  Deliberately not an empty state. An empty state is a claim about the world —
  "there is nothing" — and this is a claim about the dashboard: "nothing came
  back". The two looked identical on these screens for a long time, and the empty
  one was the lie.

  It also hides the view's own empty state while it is on screen. While a read
  has failed, any "nothing here" underneath it is unfounded, and showing both
  would leave the operator to guess which sentence to believe.
  """
  use Phoenix.Component

  attr(:reason, :string, required: true)

  def read_error(assigns) do
    ~H"""
    <style>
      .empty-state { display: none; }
    </style>
    <div class="read-error" role="status">
      <p class="read-error-title">Can&rsquo;t reach the bot</p>
      <p class="read-error-reason"><%= @reason %></p>
      <p class="read-error-hint">
        Whatever this screen usually shows has not arrived. Nothing below this line is a reading.
      </p>
    </div>
    """
  end
end
