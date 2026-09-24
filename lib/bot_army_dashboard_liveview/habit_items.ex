defmodule BotArmyDashboardLiveview.HabitItems do
  @moduledoc """
  Turns the bot's hygiene reading into the shape a habits screen draws.

  Two things this module refuses to do, because both of them were lies the
  screens used to tell:

    * **order the items.** The bot already returns them for reading (overdue
      first, then never logged, then in rhythm), and a second opinion here could
      only disagree with the source of truth. The screens used to sort by
      `days_overdue` descending, which put every never-logged item *first*:
      `nil` is an atom, atoms order after every number, and `:desc` reverses
      that. On a fresh install — after the bot stopped calling "never logged"
      overdue — that is every item.
    * **show a reading as a verdict.** `days_since` becomes a phrase in felt
      units ("last logged 3 days ago"), never a countdown, a percentage or a
      score. An item nobody has logged yet says exactly that, and says nothing
      about whether it was due.

  The wire item is the bot's: `{"event", "kind", "recorded", "days_since",
  "is_overdue", "days_overdue", "threshold", "last_occurred"}`.
  """

  @doc """
  Maps the bot's items to `%{"id", "name", "category", "logged"}` in the order
  the bot sent them.
  """
  def to_habits(items) when is_list(items) do
    Enum.map(items, fn item ->
      %{
        "id" => item["event"],
        "name" => humanize(item["event"]),
        "category" => item["kind"] || "hygiene",
        "logged" => logged_phrase(item)
      }
    end)
  end

  defp humanize(event) when is_binary(event) do
    event
    |> String.split("_")
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp humanize(_event), do: "Unnamed item"

  # `recorded: false` is the bot saying it has no reading — not that the thing is
  # late. The screens had no way to tell those apart when `days_since` was a
  # 999.0 sentinel; now it is nil and the phrase is honest.
  defp logged_phrase(%{"recorded" => false}), do: "not logged yet"

  defp logged_phrase(%{"days_since" => days}) when is_number(days) do
    cond do
      days < 1 -> "logged today"
      days < 2 -> "last logged yesterday"
      true -> "last logged #{round(days)} days ago"
    end
  end

  defp logged_phrase(_item), do: "not logged yet"
end
