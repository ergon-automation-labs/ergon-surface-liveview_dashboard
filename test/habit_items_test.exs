defmodule BotArmyDashboardLiveview.HabitItemsTest do
  use ExUnit.Case, async: true

  alias BotArmyDashboardLiveview.HabitItems

  # The bot's wire item, as the deployed 0.1.40 answers it: never logged means
  # recorded: false and days_since: nil — not a 999.0 sentinel.
  defp item(event, attrs \\ %{}) do
    Map.merge(
      %{
        "event" => event,
        "kind" => "compliance",
        "recorded" => false,
        "days_since" => nil,
        "is_overdue" => false,
        "days_overdue" => nil,
        "threshold" => 1,
        "last_occurred" => nil
      },
      attrs
    )
  end

  # The regression: sorting by days_overdue descending put nil (an atom, which
  # orders after every number) first, so a recorded item that was actually due
  # came after every never-logged item. The bot's order is the only order.
  test "keeps the bot's reading order instead of sorting a nil to the top" do
    items = [
      item("teeth_brushed", %{"recorded" => true, "days_since" => 0.2, "days_overdue" => 0.0}),
      item("meds_morning"),
      item("shower", %{"recorded" => true, "days_since" => 9.0, "days_overdue" => 7.0})
    ]

    assert Enum.map(HabitItems.to_habits(items), & &1["id"]) == [
             "teeth_brushed",
             "meds_morning",
             "shower"
           ]
  end

  test "an item nobody logged says so, and does not read as late" do
    [habit] = HabitItems.to_habits([item("meds_evening")])

    assert habit["logged"] == "not logged yet"
    assert habit["id"] == "meds_evening"
    assert habit["name"] == "Meds Evening"
    assert habit["category"] == "compliance"
  end

  test "a reading becomes felt units, not a number" do
    cases = [
      {0.0, "logged today"},
      {0.7, "logged today"},
      {1.2, "last logged yesterday"},
      {3.4, "last logged 3 days ago"},
      {9.0, "last logged 9 days ago"}
    ]

    for {days, phrase} <- cases do
      [habit] =
        HabitItems.to_habits([item("shower", %{"recorded" => true, "days_since" => days})])

      assert habit["logged"] == phrase, "#{days} days should read as #{phrase}"
    end
  end

  test "wellness keeps its own label rather than borrowing hygiene's" do
    [habit] = HabitItems.to_habits([item("face_shaved_electric", %{"kind" => "wellness"})])

    assert habit["category"] == "wellness"
    assert habit["name"] == "Face Shaved Electric"
  end

  test "an item with no name is unnamed, not a crash" do
    [habit] = HabitItems.to_habits([%{"event" => nil}])

    assert habit["name"] == "Unnamed item"
    assert habit["logged"] == "not logged yet"
  end

  test "an empty reading maps to an empty list" do
    assert HabitItems.to_habits([]) == []
  end
end
