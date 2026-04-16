defmodule Bobine.EventsTest do
  use Bobine.DataCase, async: false

  import Ecto.Query

  alias Bobine.Accounts.Scope
  alias Bobine.Audit.Log
  alias Bobine.Events
  alias Bobine.Events.AuditSubscriber
  alias Bobine.Repo
  alias Ecto.Adapters.SQL.Sandbox

  describe "broadcast/2" do
    test "org-scoped events publish only to the org topic and the audit mirror" do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :owner)
      scope = Scope.for_user(user) |> Scope.with_organization(org, membership)
      video = insert(:video, organization: org)

      Events.subscribe(org.id)
      Events.subscribe_global()
      Events.subscribe_audit()

      Events.broadcast(scope, {:video_created, video})

      # Should land on the org-specific topic.
      assert_receive {:bobine_event, {:video_created, ^video}, ^scope}
      # Should land on the audit mirror topic.
      assert_receive {:bobine_event, {:video_created, ^video}, ^scope}
      # Must NOT fan out to the platform topic.
      refute_receive {:bobine_event, {:video_created, ^video}, ^scope}
    end

    test "routes to org topic when scope is nil but the event payload names an org" do
      org = insert(:organization)
      video = insert(:video, organization: org)

      Events.subscribe(org.id)
      payload = %{organization: org, video: video}

      Events.broadcast(nil, {:queue_item_added, payload})

      assert_receive {:bobine_event, {:queue_item_added, ^payload}, nil}
    end

    test "falls through to broadcast_platform/2 when no org can be resolved" do
      Events.subscribe_global()

      Events.broadcast(nil, {:system_action, %{id: "test"}})

      assert_receive {:bobine_event, {:system_action, %{id: "test"}}, nil}
    end
  end

  describe "broadcast_platform/2" do
    test "publishes to the global topic and to the audit mirror" do
      Events.subscribe_global()
      Events.subscribe_audit()

      Events.broadcast_platform(nil, {:organization_created, %{id: "org-1"}})

      assert_receive {:bobine_event, {:organization_created, %{id: "org-1"}}, nil}
      assert_receive {:bobine_event, {:organization_created, %{id: "org-1"}}, nil}
    end

    test "does not reach org-specific topics" do
      org = insert(:organization)
      Events.subscribe(org.id)

      Events.broadcast_platform(nil, {:super_admin_granted, %{id: "user-1"}})

      refute_receive {:bobine_event, {:super_admin_granted, _}, _}
    end
  end

  describe "AuditSubscriber" do
    test "creates audit log entries when events are broadcast" do
      # Start a local AuditSubscriber for this test
      start_supervised!({AuditSubscriber, []})
      # Allow it sandbox access
      Sandbox.allow(
        Repo,
        self(),
        Process.whereis(AuditSubscriber)
      )

      video = insert(:video)

      Events.broadcast(nil, {:video_created, video})

      # Give the GenServer time to process
      Process.sleep(100)

      logs =
        Repo.all(
          from(l in Log, where: l.action == "video.created" and l.resource_id == ^video.id)
        )

      assert logs != []
      assert hd(logs).resource_type == "Video"
    end
  end
end
