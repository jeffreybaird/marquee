defmodule Bobine.AdminTest do
  use Bobine.DataCase, async: true

  alias Bobine.Admin
  alias Bobine.Accounts.Membership
  alias Bobine.Branding

  describe "list_organizations/1" do
    test "returns all organizations" do
      org_a = insert(:organization)
      org_b = insert(:organization)

      %{results: result} = Admin.list_organizations()
      ids = Enum.map(result, & &1.id)

      assert org_a.id in ids
      assert org_b.id in ids
    end

    test "filters by name with search option" do
      insert(:organization, name: "Alpha Studio", slug: "alpha-studio")
      insert(:organization, name: "Beta Channel", slug: "beta-channel")

      %{results: result} = Admin.list_organizations(search: "Alpha")
      assert length(result) == 1
      assert hd(result).name == "Alpha Studio"
    end

    test "filters by slug with search option" do
      insert(:organization, name: "Alpha Studio", slug: "alpha-studio")
      insert(:organization, name: "Beta Channel", slug: "beta-channel")

      %{results: result} = Admin.list_organizations(search: "beta-channel")
      assert length(result) == 1
      assert hd(result).slug == "beta-channel"
    end

    test "returns empty list when no orgs match search" do
      insert(:organization, name: "Alpha Studio", slug: "alpha-studio")
      assert %{results: []} = Admin.list_organizations(search: "zzz-no-match")
    end
  end

  describe "get_organization!/1" do
    test "returns org with themes preloaded" do
      org = insert(:organization)
      insert(:theme, organization: org)

      result = Admin.get_organization!(org.id)
      assert result.id == org.id
      assert length(result.themes) == 1
    end

    test "raises for nonexistent ID" do
      assert_raise Ecto.NoResultsError, fn ->
        Admin.get_organization!(Ecto.UUID.generate())
      end
    end
  end

  describe "create_organization/1" do
    test "creates org and default theme with valid attrs" do
      attrs = %{name: "New Org", slug: "new-org"}
      assert {:ok, org} = Admin.create_organization(attrs)
      assert org.name == "New Org"
      assert org.slug == "new-org"

      # Default theme created in same transaction
      assert Branding.get_theme_by_org(org) != nil
    end

    test "returns error changeset for missing name" do
      assert {:error, :validation, changeset} = Admin.create_organization(%{slug: "no-name"})
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "returns error changeset for duplicate slug" do
      insert(:organization, slug: "taken-slug")

      assert {:error, :validation, changeset} =
               Admin.create_organization(%{name: "Other", slug: "taken-slug"})

      assert %{slug: [_]} = errors_on(changeset)
    end
  end

  describe "update_organization/2" do
    test "updates name and custom_domain" do
      org = insert(:organization, name: "Old Name")

      assert {:ok, updated} =
               Admin.update_organization(org, %{name: "New Name", custom_domain: "example.com"})

      assert updated.name == "New Name"
      assert updated.custom_domain == "example.com"
    end

    test "returns error for duplicate slug" do
      insert(:organization, slug: "taken")
      org = insert(:organization)
      assert {:error, :validation, changeset} = Admin.update_organization(org, %{slug: "taken"})
      assert %{slug: [_]} = errors_on(changeset)
    end
  end

  describe "delete_organization/1" do
    test "soft-deletes the organization" do
      org = insert(:organization)
      assert {:ok, deleted} = Admin.delete_organization(org)
      assert deleted.deleted_at != nil
      # Still fetchable by ID
      assert Admin.get_organization!(org.id).deleted_at != nil
      # Excluded from default list
      assert org.id not in Enum.map(Admin.list_organizations().results, & &1.id)
    end

    test "list_organizations with include_deleted returns soft-deleted orgs" do
      org = insert(:organization)
      {:ok, _deleted} = Admin.delete_organization(org)
      %{results: orgs} = Admin.list_organizations(include_deleted: true)
      assert org.id in Enum.map(orgs, & &1.id)
    end
  end

  describe "restore_organization/1" do
    test "restores a soft-deleted organization" do
      org = insert(:organization)
      {:ok, deleted} = Admin.delete_organization(org)
      assert {:ok, restored} = Admin.restore_organization(deleted)
      assert restored.deleted_at == nil
    end
  end

  describe "create_owner_membership/2" do
    test "creates owner membership when org has no owner" do
      org = insert(:organization)
      user = insert(:user)

      assert {:ok, membership} = Admin.create_owner_membership(org, user)
      assert membership.role == :owner
      assert membership.organization_id == org.id
      assert membership.user_id == user.id
    end

    test "returns error when org already has an owner" do
      org = insert(:organization)
      existing_owner = insert(:user)
      insert(:membership, organization: org, user: existing_owner, role: :owner)

      new_user = insert(:user)
      assert {:error, :already_has_owner} = Admin.create_owner_membership(org, new_user)
    end
  end

  describe "platform_stats/0" do
    test "returns correct counts" do
      org = insert(:organization)
      insert(:user)
      insert(:video, organization: org)
      insert(:subscription, organization: org, status: :active)

      stats = Admin.platform_stats()
      assert stats.total_organizations >= 1
      assert stats.total_users >= 1
      assert stats.total_videos >= 1
      assert stats.total_subscribers >= 1
    end

    test "does not count cancelled subscriptions" do
      org = insert(:organization)
      insert(:subscription, organization: org, status: :canceled)

      stats = Admin.platform_stats()
      # cancelled subscription should not be counted
      # (we only check the count doesn't include the cancelled one,
      # without assuming what other tests may have inserted)
      cancelled_count =
        Bobine.Repo.aggregate(
          Ecto.Query.from(s in Bobine.Billing.Subscription, where: s.status == :active),
          :count
        )

      assert stats.total_subscribers == cancelled_count
    end
  end

  describe "grant_super_admin/1 and revoke_super_admin/1" do
    test "grant sets is_super_admin to true" do
      user = insert(:user, is_super_admin: false)
      assert {:ok, updated} = Admin.grant_super_admin(user)
      assert updated.is_super_admin == true
    end

    test "revoke sets is_super_admin to false" do
      user = insert(:super_admin)
      assert {:ok, updated} = Admin.revoke_super_admin(user)
      assert updated.is_super_admin == false
    end
  end

  describe "list_super_admins/0" do
    test "returns only super admins" do
      super_admin = insert(:super_admin)
      _regular = insert(:user, is_super_admin: false)

      result = Admin.list_super_admins()
      ids = Enum.map(result, & &1.id)

      assert super_admin.id in ids
      refute Enum.any?(result, &(!&1.is_super_admin))
    end
  end
end
