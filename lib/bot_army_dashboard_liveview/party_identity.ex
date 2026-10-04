defmodule BotArmyDashboardLiveview.PartyIdentity do
  @moduledoc """
  The one owner of the identity the party is read and written as: a tenant, and a user.

  ## A read is asked with no user; a write names one

  This is the whole reason the module exists, and it is a fact about the fleet rather
  than a preference of this surface. The bot's own way of opening a window
  (`rpg.session.start`) names no user, so a live session carries `user_id: nil`, and the
  window routes filter by the user they are given. A window read that names a user
  therefore answers *no window is open* while a window is open — an omission dressed as
  a reading. So **every read here names the tenant and no user**.

  The party routes are the opposite case: `rpg.party.get`, `rpg.party.add`,
  `rpg.party.remove` and `rpg.party.set_narrator` all resolve a user and refuse without
  one (`:missing_user_id`), and a party is keyed on the user it belongs to. A write that
  named nobody could read a party and never build one. So **every write here names the
  party's user** — the same literal the fleet's own `/quest-status` sends, so `"abby"`
  from this surface is the same person as `"abby"` in the window the party belongs to.

  ## The window's write names the user because the bot has to find the party from it

  A turn written into the window (`rpg.scene.fact.add`) carries this identity, and the bot
  reads the party back from it to find the narrator the line should be handed to. A turn
  written with no user resolves to no party, and the ask a line in the window is supposed
  to make is silently not made — the line lands wordless in a window that has a narrator,
  which is the failure this identity is written down to prevent. The user is a fact the
  *write* carries, so it is a fact a write may name.

  ## Two keys, one place

  The tenant is `config :bot_army_dashboard_liveview, :party_tenant_id`, and the party's
  user is `:party_user_id`. Both are overridable because a second tenant or a second
  operator is a configuration rather than a code change — and both are named *here*, once,
  so that the window screen and the party screen cannot come up with two answers to the
  same question (N+56).

  An empty or absent user names nobody rather than naming nothing: the identity is the
  parts that name something.
  """

  # The deployment is single-tenant and this dashboard has no auth to learn a different
  # tenant from, so it is named once, here, and is overridable in config.
  @default_tenant_id "00000000-0000-0000-0000-000000000001"

  # The user the party belongs to — see the module doc. `"abby"` is the same literal the
  # fleet's own party and quest screens send, and the bot resolves it through
  # `BotArmyRpg.Identity.resolve_user_id/2` to the same stable UUID.
  @default_user_id "abby"

  @doc "The tenant the party and the window belong to."
  @spec tenant_id() :: String.t()
  def tenant_id,
    do: Application.get_env(:bot_army_dashboard_liveview, :party_tenant_id, @default_tenant_id)

  @doc "The user whose party this is, or `nil` when the surface names none."
  @spec user_id() :: String.t() | nil
  def user_id,
    do: Application.get_env(:bot_army_dashboard_liveview, :party_user_id, @default_user_id)

  @doc """
  What a **read** is asked with: the tenant, and never a user.

  See the module doc: naming a user on a read is what makes a window answer *no window is
  open* while one is open.
  """
  @spec read_identity() :: %{required(String.t()) => term()}
  def read_identity, do: %{"tenant_id" => tenant_id()}

  @doc """
  What a **write** is asked with: the tenant, and the user the party belongs to.

  A `"user_id" => nil` is never sent — it would look like an identity on the wire and be
  read as one downstream. An empty user is the absence of one, so it is left out.
  """
  @spec write_identity() :: %{required(String.t()) => term()}
  def write_identity do
    case user_id() do
      id when is_binary(id) and id != "" -> Map.put(read_identity(), "user_id", id)
      _ -> read_identity()
    end
  end
end
