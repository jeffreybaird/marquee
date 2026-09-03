defmodule Marquee.Accounts.PageTourCompletionTest do
  use Marquee.DataCase, async: true

  alias Marquee.Accounts

  doctest Marquee.Accounts.PageTourCompletion

  setup do
    membership = insert(:membership)
    %{user: membership.user, org: membership.organization}
  end

  describe "page_tour_completed?/3" do
    test "is false before the page has been seen", %{user: user, org: org} do
      refute Accounts.page_tour_completed?(user, org, "content")
    end

    test "is true once the page has been recorded", %{user: user, org: org} do
      {:ok, _} = Accounts.complete_page_tour(user, org, "content")

      assert Accounts.page_tour_completed?(user, org, "content")
    end

    test "is scoped per page key", %{user: user, org: org} do
      {:ok, _} = Accounts.complete_page_tour(user, org, "content")

      assert Accounts.page_tour_completed?(user, org, "content")
      refute Accounts.page_tour_completed?(user, org, "members")
    end

    test "is isolated per organization — org A completion does not leak to org B",
         %{user: user, org: org_a} do
      org_b = insert(:organization)
      {:ok, _} = Accounts.complete_page_tour(user, org_a, "content")

      assert Accounts.page_tour_completed?(user, org_a, "content")
      refute Accounts.page_tour_completed?(user, org_b, "content")
    end

    test "is isolated per user", %{user: user, org: org} do
      other = insert(:user)
      {:ok, _} = Accounts.complete_page_tour(user, org, "content")

      assert Accounts.page_tour_completed?(user, org, "content")
      refute Accounts.page_tour_completed?(other, org, "content")
    end

    test "treats a nil user or nil org as already seen", %{user: user, org: org} do
      assert Accounts.page_tour_completed?(nil, org, "content")
      assert Accounts.page_tour_completed?(user, nil, "content")
    end
  end

  describe "complete_page_tour/3" do
    test "records the completion", %{user: user, org: org} do
      assert {:ok, completion} = Accounts.complete_page_tour(user, org, "content")
      assert completion.page_key == "content"
      assert completion.user_id == user.id
      assert completion.organization_id == org.id
    end

    test "is idempotent and preserves the original seen timestamp", %{user: user, org: org} do
      {:ok, first} = Accounts.complete_page_tour(user, org, "content")
      seen_at = Repo.reload!(first).inserted_at

      assert {:ok, _} = Accounts.complete_page_tour(user, org, "content")

      # Still exactly one row, and its timestamp is unchanged.
      assert Repo.aggregate(
               from(c in Marquee.Accounts.PageTourCompletion,
                 where: c.user_id == ^user.id and c.page_key == "content"
               ),
               :count
             ) == 1

      assert Repo.reload!(first).inserted_at == seen_at
    end

    test "is a no-op for a nil user or nil org", %{user: user, org: org} do
      assert {:ok, nil} = Accounts.complete_page_tour(nil, org, "content")
      assert {:ok, nil} = Accounts.complete_page_tour(user, nil, "content")
    end
  end
end
