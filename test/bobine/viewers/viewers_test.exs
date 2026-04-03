defmodule Bobine.ViewersTest do
  use Bobine.DataCase

  alias Bobine.Accounts.Scope
  alias Bobine.Viewers
  alias Bobine.Viewers.Viewer

  defp build_scope(org) do
    %Scope{user: nil, organization: org, membership: nil}
  end

  setup do
    org = insert(:organization)
    %{org: org}
  end

  ## -----------------------------------------------------------------------
  ## Registration
  ## -----------------------------------------------------------------------

  describe "register_viewer/2" do
    test "creates a viewer with valid attributes", %{org: org} do
      attrs = %{email: "new@example.com", display_name: "New Viewer"}
      assert {:ok, %Viewer{} = viewer} = Viewers.register_viewer(org, attrs)
      assert viewer.email == "new@example.com"
      assert viewer.display_name == "New Viewer"
      assert viewer.organization_id == org.id
      assert viewer.status == :active
      assert viewer.subscription_status == "none"
    end

    test "normalizes email to lowercase", %{org: org} do
      attrs = %{email: "TEST@EXAMPLE.COM"}
      assert {:ok, %Viewer{} = viewer} = Viewers.register_viewer(org, attrs)
      assert viewer.email == "test@example.com"
    end

    test "sets display_name from email when not provided", %{org: org} do
      attrs = %{email: "alice@example.com"}
      assert {:ok, %Viewer{} = viewer} = Viewers.register_viewer(org, attrs)
      assert viewer.display_name == "alice"
    end

    test "returns error for duplicate email in same org", %{org: org} do
      attrs = %{email: "dupe@example.com"}
      assert {:ok, _viewer} = Viewers.register_viewer(org, attrs)
      assert {:error, :validation, changeset} = Viewers.register_viewer(org, attrs)
      assert "has already been taken" in errors_on(changeset).organization_id
    end

    test "allows same email in different org", %{org: org} do
      other_org = insert(:organization)
      attrs = %{email: "shared@example.com"}
      assert {:ok, _viewer} = Viewers.register_viewer(org, attrs)
      assert {:ok, viewer2} = Viewers.register_viewer(other_org, attrs)
      assert viewer2.organization_id == other_org.id
    end

    test "returns error when email is missing", %{org: org} do
      assert {:error, :validation, changeset} = Viewers.register_viewer(org, %{})
      assert %{email: ["can't be blank"]} = errors_on(changeset)
    end

    test "returns error for invalid email format", %{org: org} do
      attrs = %{email: "not valid"}
      assert {:error, :validation, changeset} = Viewers.register_viewer(org, attrs)
      assert "must have the @ sign and no spaces" in errors_on(changeset).email
    end
  end

  ## -----------------------------------------------------------------------
  ## Auth — email lookup
  ## -----------------------------------------------------------------------

  describe "get_viewer_by_email/2" do
    test "returns the viewer scoped to the org", %{org: org} do
      viewer = insert(:viewer, organization: org)
      found = Viewers.get_viewer_by_email(org, viewer.email)
      assert found.id == viewer.id
    end

    test "returns nil for a different org", %{org: org} do
      other_org = insert(:organization)
      viewer = insert(:viewer, organization: other_org)
      assert is_nil(Viewers.get_viewer_by_email(org, viewer.email))
    end

    test "returns nil for non-existent email", %{org: org} do
      assert is_nil(Viewers.get_viewer_by_email(org, "nobody@example.com"))
    end

    test "ignores email case", %{org: org} do
      viewer = insert(:viewer, organization: org, email: "alice@example.com")
      found = Viewers.get_viewer_by_email(org, "ALICE@EXAMPLE.COM")
      assert found.id == viewer.id
    end

    test "does not return soft-deleted viewers", %{org: org} do
      viewer = insert(:viewer, organization: org, deleted_at: DateTime.utc_now())
      assert is_nil(Viewers.get_viewer_by_email(org, viewer.email))
    end
  end

  ## -----------------------------------------------------------------------
  ## Auth — magic link
  ## -----------------------------------------------------------------------

  describe "deliver_viewer_magic_link/2" do
    test "returns {:ok, :sent} for an active viewer", %{org: org} do
      viewer = insert(:viewer, organization: org)
      assert {:ok, :sent} = Viewers.deliver_viewer_magic_link(org, viewer.email)
    end

    test "returns {:ok, :not_found} for non-existent email", %{org: org} do
      assert {:ok, :not_found} = Viewers.deliver_viewer_magic_link(org, "nobody@example.com")
    end

    test "returns {:ok, :not_found} for banned viewer", %{org: org} do
      viewer = insert(:viewer, organization: org, status: :banned)
      assert {:ok, :not_found} = Viewers.deliver_viewer_magic_link(org, viewer.email)
    end

    test "returns {:ok, :not_found} for suspended viewer", %{org: org} do
      viewer = insert(:viewer, organization: org, status: :suspended)
      assert {:ok, :not_found} = Viewers.deliver_viewer_magic_link(org, viewer.email)
    end
  end

  describe "verify_viewer_magic_link/1" do
    test "returns {:ok, viewer} for a valid magic link token", %{org: org} do
      viewer = insert(:viewer, organization: org)
      {token, viewer_token} = Bobine.Viewers.ViewerToken.build_magic_link_token(viewer)
      Repo.insert!(viewer_token)

      assert {:ok, verified} = Viewers.verify_viewer_magic_link(token)
      assert verified.id == viewer.id
    end

    test "sets confirmed_at on first verification", %{org: org} do
      viewer = insert(:viewer, organization: org, confirmed_at: nil)
      {token, viewer_token} = Bobine.Viewers.ViewerToken.build_magic_link_token(viewer)
      Repo.insert!(viewer_token)

      assert {:ok, verified} = Viewers.verify_viewer_magic_link(token)
      assert verified.confirmed_at != nil
    end

    test "does not overwrite confirmed_at on subsequent verifications", %{org: org} do
      original_confirmed = ~U[2025-01-01 00:00:00Z]
      viewer = insert(:viewer, organization: org, confirmed_at: original_confirmed)
      {token, viewer_token} = Bobine.Viewers.ViewerToken.build_magic_link_token(viewer)
      Repo.insert!(viewer_token)

      assert {:ok, verified} = Viewers.verify_viewer_magic_link(token)
      assert verified.confirmed_at == original_confirmed
    end

    test "returns error for invalid token" do
      assert {:error, :invalid_token} = Viewers.verify_viewer_magic_link("bogus")
    end

    test "returns error for expired token", %{org: org} do
      viewer = insert(:viewer, organization: org)
      {token, viewer_token} = Bobine.Viewers.ViewerToken.build_magic_link_token(viewer)

      # Insert with a timestamp far in the past to simulate expiry
      expired_token =
        viewer_token
        |> Map.put(:inserted_at, ~U[2020-01-01 00:00:00Z])

      Repo.insert!(expired_token)

      assert {:error, :invalid_token} = Viewers.verify_viewer_magic_link(token)
    end
  end

  ## -----------------------------------------------------------------------
  ## Auth — session tokens
  ## -----------------------------------------------------------------------

  describe "generate_viewer_session_token/1 and get_viewer_by_session_token/1" do
    test "generates and verifies a session token", %{org: org} do
      viewer = insert(:viewer, organization: org)
      token = Viewers.generate_viewer_session_token(viewer)

      assert is_binary(token)
      found = Viewers.get_viewer_by_session_token(token)
      assert found.id == viewer.id
    end

    test "returns nil for invalid session token" do
      assert is_nil(Viewers.get_viewer_by_session_token(:crypto.strong_rand_bytes(32)))
    end
  end

  describe "delete_viewer_session_token/1" do
    test "invalidates a session token", %{org: org} do
      viewer = insert(:viewer, organization: org)
      token = Viewers.generate_viewer_session_token(viewer)
      assert Viewers.get_viewer_by_session_token(token) != nil

      Viewers.delete_viewer_session_token(token)
      assert is_nil(Viewers.get_viewer_by_session_token(token))
    end
  end

  ## -----------------------------------------------------------------------
  ## CRUD
  ## -----------------------------------------------------------------------

  describe "get_viewer/2" do
    test "returns {:ok, viewer} scoped to the org", %{org: org} do
      viewer = insert(:viewer, organization: org)
      assert {:ok, found} = Viewers.get_viewer(org, viewer.id)
      assert found.id == viewer.id
    end

    test "returns {:error, :not_found} for a different org", %{org: org} do
      other_org = insert(:organization)
      viewer = insert(:viewer, organization: other_org)
      assert {:error, :not_found} = Viewers.get_viewer(org, viewer.id)
    end

    test "returns {:error, :not_found} for soft-deleted viewer", %{org: org} do
      viewer = insert(:viewer, organization: org, deleted_at: DateTime.utc_now())
      assert {:error, :not_found} = Viewers.get_viewer(org, viewer.id)
    end

    test "returns {:error, :not_found} for non-existent ID", %{org: org} do
      assert {:error, :not_found} = Viewers.get_viewer(org, Ecto.UUID.generate())
    end
  end

  describe "get_viewer!/2" do
    test "returns the viewer scoped to the org", %{org: org} do
      viewer = insert(:viewer, organization: org)
      found = Viewers.get_viewer!(org, viewer.id)
      assert found.id == viewer.id
    end

    test "raises for a different org", %{org: org} do
      other_org = insert(:organization)
      viewer = insert(:viewer, organization: other_org)

      assert_raise Ecto.NoResultsError, fn ->
        Viewers.get_viewer!(org, viewer.id)
      end
    end
  end

  describe "update_viewer_profile/3" do
    test "updates the viewer profile", %{org: org} do
      viewer = insert(:viewer, organization: org)
      scope = build_scope(org)

      assert {:ok, updated} =
               Viewers.update_viewer_profile(scope, viewer, %{display_name: "Updated Name"})

      assert updated.display_name == "Updated Name"
    end

    test "updates avatar_url", %{org: org} do
      viewer = insert(:viewer, organization: org)
      scope = build_scope(org)

      assert {:ok, updated} =
               Viewers.update_viewer_profile(scope, viewer, %{
                 avatar_url: "https://example.com/avatar.jpg"
               })

      assert updated.avatar_url == "https://example.com/avatar.jpg"
    end
  end

  describe "list_viewers/2" do
    test "returns paginated viewers for the org", %{org: org} do
      insert(:viewer, organization: org)
      insert(:viewer, organization: org)

      result = Viewers.list_viewers(org)
      assert length(result.results) == 2
      assert result.total == 2
    end

    test "excludes viewers from other orgs", %{org: org} do
      other_org = insert(:organization)
      insert(:viewer, organization: org)
      insert(:viewer, organization: other_org)

      result = Viewers.list_viewers(org)
      assert length(result.results) == 1
    end

    test "excludes soft-deleted viewers", %{org: org} do
      insert(:viewer, organization: org)
      insert(:viewer, organization: org, deleted_at: DateTime.utc_now())

      result = Viewers.list_viewers(org)
      assert length(result.results) == 1
    end

    test "paginates results", %{org: org} do
      for _ <- 1..5, do: insert(:viewer, organization: org)

      result = Viewers.list_viewers(org, page: 1, per_page: 2)
      assert length(result.results) == 2
      assert result.total == 5
      assert result.total_pages == 3
    end

    test "filters by status", %{org: org} do
      insert(:viewer, organization: org, status: :active)
      insert(:viewer, organization: org, status: :suspended)

      result = Viewers.list_viewers(org, status: :suspended)
      assert length(result.results) == 1
      assert hd(result.results).status == :suspended
    end

    test "filters by subscription_status", %{org: org} do
      insert(:viewer, organization: org, subscription_status: "active")
      insert(:viewer, organization: org, subscription_status: "none")

      result = Viewers.list_viewers(org, subscription_status: "active")
      assert length(result.results) == 1
      assert hd(result.results).subscription_status == "active"
    end

    test "filters by search term on email", %{org: org} do
      insert(:viewer, organization: org, email: "alice@example.com")
      insert(:viewer, organization: org, email: "bob@example.com")

      result = Viewers.list_viewers(org, search: "alice")
      assert length(result.results) == 1
      assert hd(result.results).email == "alice@example.com"
    end
  end

  describe "count_viewers/1" do
    test "counts active viewers for the org", %{org: org} do
      insert(:viewer, organization: org)
      insert(:viewer, organization: org)
      insert(:viewer, organization: org, deleted_at: DateTime.utc_now())

      assert Viewers.count_viewers(org) == 2
    end

    test "does not count viewers from other orgs", %{org: org} do
      other_org = insert(:organization)
      insert(:viewer, organization: org)
      insert(:viewer, organization: other_org)

      assert Viewers.count_viewers(org) == 1
    end
  end

  describe "count_viewers_by_status/1" do
    test "groups viewer counts by status", %{org: org} do
      insert(:viewer, organization: org, status: :active)
      insert(:viewer, organization: org, status: :active)
      insert(:viewer, organization: org, status: :suspended)
      insert(:viewer, organization: org, status: :banned)

      counts = Viewers.count_viewers_by_status(org)
      assert counts[:active] == 2
      assert counts[:suspended] == 1
      assert counts[:banned] == 1
    end

    test "excludes soft-deleted viewers", %{org: org} do
      insert(:viewer, organization: org, status: :active)
      insert(:viewer, organization: org, status: :active, deleted_at: DateTime.utc_now())

      counts = Viewers.count_viewers_by_status(org)
      assert counts[:active] == 1
    end
  end

  ## -----------------------------------------------------------------------
  ## Account actions
  ## -----------------------------------------------------------------------

  describe "suspend_viewer/2" do
    test "sets viewer status to :suspended", %{org: org} do
      viewer = insert(:viewer, organization: org, status: :active)
      scope = build_scope(org)

      assert {:ok, suspended} = Viewers.suspend_viewer(scope, viewer)
      assert suspended.status == :suspended
    end
  end

  describe "ban_viewer/2" do
    test "sets viewer status to :banned", %{org: org} do
      viewer = insert(:viewer, organization: org, status: :active)
      scope = build_scope(org)

      assert {:ok, banned} = Viewers.ban_viewer(scope, viewer)
      assert banned.status == :banned
    end
  end

  describe "reactivate_viewer/2" do
    test "reactivates a suspended viewer", %{org: org} do
      viewer = insert(:viewer, organization: org, status: :suspended)
      scope = build_scope(org)

      assert {:ok, reactivated} = Viewers.reactivate_viewer(scope, viewer)
      assert reactivated.status == :active
    end

    test "reactivates a banned viewer", %{org: org} do
      viewer = insert(:viewer, organization: org, status: :banned)
      scope = build_scope(org)

      assert {:ok, reactivated} = Viewers.reactivate_viewer(scope, viewer)
      assert reactivated.status == :active
    end
  end

  ## -----------------------------------------------------------------------
  ## Access management
  ## -----------------------------------------------------------------------

  describe "grant_access/3" do
    test "sets subscription_status to active", %{org: org} do
      viewer = insert(:viewer, organization: org, subscription_status: "none")
      scope = build_scope(org)

      assert {:ok, granted} = Viewers.grant_access(scope, viewer)
      assert granted.subscription_status == "active"
    end

    test "sets optional expires_at", %{org: org} do
      viewer = insert(:viewer, organization: org, subscription_status: "none")
      scope = build_scope(org)
      expires = DateTime.add(DateTime.utc_now(), 30, :day) |> DateTime.truncate(:second)

      assert {:ok, granted} = Viewers.grant_access(scope, viewer, expires)
      assert granted.subscription_status == "active"
      assert granted.subscription_expires_at == expires
    end
  end

  describe "revoke_access/2" do
    test "sets subscription_status to none", %{org: org} do
      viewer = insert(:subscribed_viewer, organization: org)
      scope = build_scope(org)

      assert {:ok, revoked} = Viewers.revoke_access(scope, viewer)
      assert revoked.subscription_status == "none"
      assert is_nil(revoked.subscription_expires_at)
    end
  end

  ## -----------------------------------------------------------------------
  ## Deletion
  ## -----------------------------------------------------------------------

  describe "delete_viewer/2" do
    test "soft-deletes the viewer", %{org: org} do
      viewer = insert(:viewer, organization: org)
      scope = build_scope(org)

      assert {:ok, deleted} = Viewers.delete_viewer(scope, viewer)
      assert deleted.deleted_at != nil
    end

    test "invalidates all session tokens for the viewer", %{org: org} do
      viewer = insert(:viewer, organization: org)
      scope = build_scope(org)
      token = Viewers.generate_viewer_session_token(viewer)

      assert {:ok, _deleted} = Viewers.delete_viewer(scope, viewer)
      assert is_nil(Viewers.get_viewer_by_session_token(token))
    end

    test "soft-deleted viewer is not returned by get_viewer", %{org: org} do
      viewer = insert(:viewer, organization: org)
      scope = build_scope(org)

      assert {:ok, _deleted} = Viewers.delete_viewer(scope, viewer)
      assert {:error, :not_found} = Viewers.get_viewer(org, viewer.id)
    end
  end

  describe "hard_delete_viewer_data/2" do
    test "permanently deletes the viewer record", %{org: org} do
      viewer = insert(:viewer, organization: org)

      assert {:ok, _} = Viewers.hard_delete_viewer_data(org, viewer)
      assert is_nil(Repo.get(Viewer, viewer.id))
    end

    test "returns {:error, :forbidden} for wrong org", %{org: org} do
      other_org = insert(:organization)
      viewer = insert(:viewer, organization: other_org)

      assert {:error, :forbidden} = Viewers.hard_delete_viewer_data(org, viewer)
    end
  end
end
