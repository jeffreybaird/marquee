defmodule Marquee.Accounts.AdminNudgeDismissalTest do
  use Marquee.DataCase, async: true

  alias Marquee.Accounts

  doctest Marquee.Accounts.AdminNudgeDismissal

  setup do
    membership = insert(:membership)
    %{user: membership.user, org: membership.organization}
  end

  describe "list_dismissed_nudge_keys/2" do
    test "returns the keys this user dismissed for this org", %{user: user, org: org} do
      {:ok, _} = Accounts.dismiss_nudge(user, org, "connect_stripe")
      {:ok, _} = Accounts.dismiss_nudge(user, org, "create_plan")

      assert Enum.sort(Accounts.list_dismissed_nudge_keys(user, org)) ==
               ["connect_stripe", "create_plan"]
    end

    test "returns [] when nothing dismissed", %{user: user, org: org} do
      assert Accounts.list_dismissed_nudge_keys(user, org) == []
    end

    test "is scoped per user", %{user: user, org: org} do
      other = insert(:membership, organization: org).user
      {:ok, _} = Accounts.dismiss_nudge(user, org, "connect_stripe")

      assert Accounts.list_dismissed_nudge_keys(other, org) == []
    end

    test "is scoped per organization", %{user: user, org: org} do
      other_org = insert(:organization)
      {:ok, _} = Accounts.dismiss_nudge(user, org, "connect_stripe")

      assert Accounts.list_dismissed_nudge_keys(user, other_org) == []
    end
  end

  describe "dismiss_nudge/3" do
    test "is idempotent — re-dismissing the same key does not duplicate",
         %{user: user, org: org} do
      {:ok, _} = Accounts.dismiss_nudge(user, org, "connect_stripe")
      {:ok, _} = Accounts.dismiss_nudge(user, org, "connect_stripe")

      assert Accounts.list_dismissed_nudge_keys(user, org) == ["connect_stripe"]
    end
  end
end
