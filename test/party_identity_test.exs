defmodule BotArmyDashboardLiveview.PartyIdentityTest do
  use ExUnit.Case, async: false

  @moduletag :core

  alias BotArmyDashboardLiveview.PartyIdentity

  @app :bot_army_dashboard_liveview
  @tenant "00000000-0000-0000-0000-000000000001"

  setup do
    on_exit(fn ->
      Application.delete_env(@app, :party_tenant_id)
      Application.delete_env(@app, :party_user_id)
    end)

    :ok
  end

  describe "read_identity/0 — a read names the tenant and no user" do
    test "the tenant is named once, here, and a read carries no user" do
      assert PartyIdentity.read_identity() == %{"tenant_id" => @tenant}
    end

    test "the party's user is named by default, and a read still carries none of it" do
      # The whole point of the read/write split: this is the identity the party and the
      # window are keyed on, and naming it on a read is what makes the window answer "no
      # window is open" while one is open. So it is named on writes, and never here.
      assert PartyIdentity.user_id() == "abby"
      refute Map.has_key?(PartyIdentity.read_identity(), "user_id")
    end
  end

  describe "write_identity/0 — a write names the user the party belongs to" do
    test "the party's user is on the write, because the bot finds the party from it" do
      assert PartyIdentity.write_identity() == %{"tenant_id" => @tenant, "user_id" => "abby"}
    end

    test "an empty pinned user id names nobody rather than naming nothing" do
      # `"user_id" => ""` would look like an identity on the wire and be read as one
      # downstream. An empty user is the absence of one, so it is left out.
      Application.put_env(@app, :party_user_id, "")

      assert PartyIdentity.write_identity() == %{"tenant_id" => @tenant}
    end

    test "a pinned user id is named, and the tenant rides with it" do
      Application.put_env(@app, :party_user_id, "11111111-1111-1111-1111-111111111111")

      assert PartyIdentity.write_identity() == %{
               "tenant_id" => @tenant,
               "user_id" => "11111111-1111-1111-1111-111111111111"
             }
    end
  end

  describe "the deployment is a configuration, not an assumption" do
    test "a second tenant is a config change" do
      Application.put_env(@app, :party_tenant_id, "22222222-2222-2222-2222-222222222222")

      assert PartyIdentity.tenant_id() == "22222222-2222-2222-2222-222222222222"
      assert PartyIdentity.read_identity()["tenant_id"] == "22222222-2222-2222-2222-222222222222"
      assert PartyIdentity.write_identity()["tenant_id"] == "22222222-2222-2222-2222-222222222222"
    end
  end
end
