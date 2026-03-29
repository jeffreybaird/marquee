defmodule Bobine.Admin.ExportTest do
  use Bobine.DataCase, async: true

  alias Bobine.Admin

  describe "export_organization_data/1" do
    test "includes records from the target org" do
      org = insert(:organization)
      user = insert(:user)
      insert(:membership, organization: org, user: user, role: :owner)
      insert(:video, organization: org)
      insert(:collection, organization: org)
      insert(:tag, organization: org)
      insert(:row, organization: org)
      insert(:plan, organization: org)
      insert(:theme, organization: org)
      insert(:webhook_endpoint, organization: org)
      insert(:notification, organization: org)
      insert(:watchlist_item, organization: org, user: user)
      insert(:favorite, organization: org, user: user)
      insert(:watch_history, organization: org, user: user)
      insert(:progress, organization: org, user: user)
      insert(:analytics_event, organization: org, user: user)

      export = Admin.export_organization_data(org)

      assert export.organization.id == org.id
      assert length(export.memberships) == 1
      assert length(export.videos) == 1
      assert length(export.collections) == 1
      assert length(export.tags) == 1
      assert length(export.rows) == 1
      assert length(export.plans) == 1
      assert export.theme != nil
      assert length(export.webhook_endpoints) == 1
      assert length(export.notifications) == 1
      assert length(export.watchlist_items) == 1
      assert length(export.favorites) == 1
      assert length(export.watch_histories) == 1
      assert length(export.progresses) == 1
      assert length(export.analytics_events) == 1
    end

    test "does NOT include records from other orgs" do
      org_a = insert(:organization)
      org_b = insert(:organization)
      insert(:video, organization: org_a)
      insert(:video, organization: org_b)

      export = Admin.export_organization_data(org_a)

      assert length(export.videos) == 1
      assert hd(export.videos).organization_id == org_a.id
    end

    test "includes soft-deleted records" do
      org = insert(:organization)
      video = insert(:video, organization: org)

      # Soft-delete the video
      Bobine.Content.delete_video(video)

      export = Admin.export_organization_data(org)

      assert length(export.videos) == 1
      assert hd(export.videos).deleted_at != nil
    end

    test "returns empty lists (not nil) for schemas with no data" do
      org = insert(:organization)

      export = Admin.export_organization_data(org)

      assert export.memberships == []
      assert export.videos == []
      assert export.collections == []
      assert export.tags == []
      assert export.rows == []
      assert export.plans == []
      assert export.subscriptions == []
      assert export.theme == nil
      assert export.webhook_endpoints == []
      assert export.notifications == []
      assert export.audit_logs == []
      assert export.watchlist_items == []
      assert export.favorites == []
      assert export.watch_histories == []
      assert export.progresses == []
      assert export.analytics_events == []
    end
  end
end
