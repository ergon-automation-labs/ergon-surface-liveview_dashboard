defmodule BotArmyDashboardLiveview.QuestPayload do
  @moduledoc """
  Parses a `bridge.quest.current` reply into the quest map the quest views render.

  The bridge answers with an **envelope**, not a bare quest:

      {"ok": true,  "quest": {…}}   # or "quest": null
      {"ok": false, "quest": null, "error": "…"}

  Matching that envelope as if it were the quest is a real failure mode — the
  wrapper map is truthy, so a view would render a quest card with a nil title
  and "0 of 0 tasks complete" instead of its empty state. Anything that is not a
  present quest is `nil` here, which every caller renders as "no active quest".
  """

  @spec parse(term()) :: map() | nil
  def parse(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> parse(decoded)
      _ -> nil
    end
  end

  def parse(%{"ok" => true, "quest" => quest}) when is_map(quest), do: quest
  def parse(_other), do: nil
end
