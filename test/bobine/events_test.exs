defmodule Bobine.EventsTest do
  use Bobine.DataCase, async: false

  import Ecto.Query

  alias Bobine.Events
  alias Bobine.Accounts.Scope

  describe "broadcast/2" do
    test "sends to org-specific and global PubSub topics" do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :owner)
      scope = Scope.for_user(user) |> Scope.with_organization(org, membership)
      video = insert(:video, organization: org)

      Events.subscribe(org.id)
      Events.subscribe_global()

      Events.broadcast(scope, {:video_created, video})

      # Should receive on org-specific topic
      assert_receive {:bobine_event, {:video_created, ^video}, ^scope}
      # Should also receive on global topic
      assert_receive {:bobine_event, {:video_created, ^video}, ^scope}
    end

    test "sends to global topic when scope has no org" do
      Events.subscribe_global()

      Events.broadcast(nil, {:system_action, %{id: "test"}})

      assert_receive {:bobine_event, {:system_action, %{id: "test"}}, nil}
    end

  end

  describe "AuditSubscriber" do
    test "creates audit log entries when events are broadcast" do
      # Start a local AuditSubscriber for this test
      start_supervised!({Bobine.Events.AuditSubscriber, []})
      # Allow it sandbox access
      Ecto.Adapters.SQL.Sandbox.allow(
        Bobine.Repo,
        self(),
        Process.whereis(Bobine.Events.AuditSubscriber)
      )

      video = insert(:video)

      Events.broadcast(nil, {:video_created, video})

      # Give the GenServer time to process
      Process.sleep(100)

      logs =
        Bobine.Repo.all(
          from(l in Bobine.Audit.Log,
            where: l.action == "video.created" and l.resource_id == ^video.id
          )
        )

      assert length(logs) > 0
      assert hd(logs).resource_type == "Video"
    end
  end
end
