defmodule Bobine.AuditQueryTest do
  use Bobine.DataCase, async: true

  alias Bobine.Audit

  describe "list_for_organization/3" do
    test "returns logs for the given organization" do
      org = insert(:organization)
      user = insert(:user)
      log = insert(:audit_log, organization: org, user: user, action: "video.created")

      %{results: results} = Audit.list_for_organization(org)

      assert length(results) == 1
      assert hd(results).id == log.id
    end

    test "preloads user" do
      org = insert(:organization)
      user = insert(:user)
      insert(:audit_log, organization: org, user: user)

      %{results: [log]} = Audit.list_for_organization(org)

      assert %Bobine.Accounts.User{} = log.user
      assert log.user.id == user.id
    end

    test "filters by action" do
      org = insert(:organization)
      log_a = insert(:audit_log, organization: org, action: "video.created")
      _log_b = insert(:audit_log, organization: org, action: "video.deleted")

      %{results: results} = Audit.list_for_organization(org, %{action: "video.created"})

      assert length(results) == 1
      assert hd(results).id == log_a.id
    end

    test "filters by user_id" do
      org = insert(:organization)
      user_a = insert(:user)
      user_b = insert(:user)
      log_a = insert(:audit_log, organization: org, user: user_a)
      _log_b = insert(:audit_log, organization: org, user: user_b)

      %{results: results} = Audit.list_for_organization(org, %{user_id: user_a.id})

      assert length(results) == 1
      assert hd(results).id == log_a.id
    end

    test "filters by resource_type" do
      org = insert(:organization)
      log_v = insert(:audit_log, organization: org, resource_type: "Video")
      _log_c = insert(:audit_log, organization: org, resource_type: "Collection")

      %{results: results} = Audit.list_for_organization(org, %{resource_type: "Video"})

      assert length(results) == 1
      assert hd(results).id == log_v.id
    end

    test "filters by from date" do
      org = insert(:organization)
      past_time = ~U[2026-01-01 00:00:00Z]
      recent_time = ~U[2026-04-01 00:00:00Z]

      past_log = insert(:audit_log, organization: org, inserted_at: past_time)
      recent_log = insert(:audit_log, organization: org, inserted_at: recent_time)

      %{results: results} =
        Audit.list_for_organization(org, %{from: ~D[2026-02-01]})

      ids = Enum.map(results, & &1.id)
      assert recent_log.id in ids
      refute past_log.id in ids
    end

    test "filters by to date" do
      org = insert(:organization)
      past_time = ~U[2026-01-01 00:00:00Z]
      recent_time = ~U[2026-04-01 00:00:00Z]

      past_log = insert(:audit_log, organization: org, inserted_at: past_time)
      _recent_log = insert(:audit_log, organization: org, inserted_at: recent_time)

      %{results: results} =
        Audit.list_for_organization(org, %{to: ~D[2026-02-01]})

      ids = Enum.map(results, & &1.id)
      assert past_log.id in ids
      assert length(results) == 1
    end

    test "filters by search (action ILIKE)" do
      org = insert(:organization)
      log_a = insert(:audit_log, organization: org, action: "video.published")
      _log_b = insert(:audit_log, organization: org, action: "collection.updated")

      %{results: results} = Audit.list_for_organization(org, %{search: "video"})

      assert length(results) == 1
      assert hd(results).id == log_a.id
    end

    test "cursor pagination returns correct next_cursor when more results exist" do
      org = insert(:organization)

      logs =
        for i <- 1..5 do
          t = DateTime.add(~U[2026-04-01 00:00:00Z], i, :second)
          insert(:audit_log, organization: org, inserted_at: t)
        end

      %{results: page1, next_cursor: cursor} = Audit.list_for_organization(org, %{}, per_page: 3)

      assert length(page1) == 3
      assert cursor != nil

      %{results: page2, next_cursor: cursor2} =
        Audit.list_for_organization(org, %{}, per_page: 3, cursor: cursor)

      assert length(page2) == 2
      assert cursor2 == nil

      all_ids = (page1 ++ page2) |> Enum.map(& &1.id) |> MapSet.new()
      expected_ids = logs |> Enum.map(& &1.id) |> MapSet.new()
      assert all_ids == expected_ids
    end

    test "no duplicate results across pages" do
      org = insert(:organization)

      for i <- 1..6 do
        t = DateTime.add(~U[2026-04-01 00:00:00Z], i, :second)
        insert(:audit_log, organization: org, inserted_at: t)
      end

      %{results: page1, next_cursor: cursor} = Audit.list_for_organization(org, %{}, per_page: 4)
      %{results: page2} = Audit.list_for_organization(org, %{}, per_page: 4, cursor: cursor)

      all_ids = (page1 ++ page2) |> Enum.map(& &1.id)
      assert all_ids == Enum.uniq(all_ids)
    end

    test "tenant isolation: org A cannot see org B's logs" do
      org_a = insert(:organization)
      org_b = insert(:organization)
      _log_a = insert(:audit_log, organization: org_a)
      _log_b = insert(:audit_log, organization: org_b)

      %{results: results} = Audit.list_for_organization(org_a)

      assert length(results) == 1
      assert hd(results).organization_id == org_a.id
    end
  end

  describe "list_all/2" do
    test "returns audit logs across all organizations" do
      org_a = insert(:organization)
      org_b = insert(:organization)
      log_a = insert(:audit_log, organization: org_a)
      log_b = insert(:audit_log, organization: org_b)

      %{results: results} = Audit.list_all()

      ids = Enum.map(results, & &1.id)
      assert log_a.id in ids
      assert log_b.id in ids
    end

    test "preloads user and organization" do
      org = insert(:organization)
      user = insert(:user)
      insert(:audit_log, organization: org, user: user)

      %{results: [log]} = Audit.list_all()

      assert %Bobine.Accounts.User{} = log.user
      assert %Bobine.Accounts.Organization{} = log.organization
    end

    test "filters by organization_id" do
      org_a = insert(:organization)
      org_b = insert(:organization)
      log_a = insert(:audit_log, organization: org_a)
      _log_b = insert(:audit_log, organization: org_b)

      %{results: results} = Audit.list_all(%{organization_id: org_a.id})

      assert length(results) == 1
      assert hd(results).id == log_a.id
    end

    test "returns empty list when no logs exist" do
      %{results: results} = Audit.list_all()
      assert results == []
    end
  end

  describe "get_filter_options/1" do
    setup do
      Bobine.Cache.delete_by_prefix("audit_filter_options:")
      :ok
    end

    test "returns distinct actions, actors, and resource types for the org" do
      org = insert(:organization)
      user = insert(:user)

      insert(:audit_log,
        organization: org,
        user: user,
        action: "video.created",
        resource_type: "Video"
      )

      insert(:audit_log,
        organization: org,
        user: user,
        action: "video.deleted",
        resource_type: "Video"
      )

      options = Audit.get_filter_options(org)

      assert "video.created" in options.actions
      assert "video.deleted" in options.actions
      assert Enum.any?(options.actors, &(&1.id == user.id))
      assert "Video" in options.resource_types
    end

    test "does not include other org's data" do
      org_a = insert(:organization)
      org_b = insert(:organization)
      insert(:audit_log, organization: org_a, action: "video.created")
      insert(:audit_log, organization: org_b, action: "collection.updated")

      options = Audit.get_filter_options(org_a)

      assert "video.created" in options.actions
      refute "collection.updated" in options.actions
    end
  end

  describe "get_filter_options_global/0" do
    setup do
      Bobine.Cache.delete("audit_filter_options:global")
      :ok
    end

    test "returns actions, actors, resource types, and organizations across all tenants" do
      org_a = insert(:organization)
      org_b = insert(:organization)
      user = insert(:user)

      insert(:audit_log,
        organization: org_a,
        user: user,
        action: "video.created",
        resource_type: "Video"
      )

      insert(:audit_log,
        organization: org_b,
        action: "collection.updated",
        resource_type: "Collection"
      )

      options = Audit.get_filter_options_global()

      assert "video.created" in options.actions
      assert "collection.updated" in options.actions
      assert "Video" in options.resource_types
      assert "Collection" in options.resource_types
      assert Enum.any?(options.organizations, &(&1.id == org_a.id))
      assert Enum.any?(options.organizations, &(&1.id == org_b.id))
    end
  end
end
