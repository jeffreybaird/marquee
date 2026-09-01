defmodule Marquee.AuditTest do
  use Marquee.DataCase, async: true

  alias Marquee.Accounts.Scope
  alias Marquee.Audit
  alias Marquee.Audit.Log

  describe "log/4" do
    test "creates an audit log with all fields populated" do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :owner)
      scope = Scope.for_user(user) |> Scope.with_organization(org, membership)
      video = insert(:video, organization: org)

      assert {:ok, %Log{} = log} = Audit.log(scope, "video.created", video, %{title: "New"})

      assert log.organization_id == org.id
      assert log.user_id == user.id
      assert log.action == "video.created"
      assert log.resource_type == "Video"
      assert log.resource_id == video.id
      assert log.changes == %{title: "New"}
      assert log.inserted_at != nil
    end

    test "with nil scope creates a log with nil user and org" do
      video = insert(:video)

      assert {:ok, %Log{} = log} = Audit.log(nil, "video.processed", video)

      assert log.organization_id == nil
      assert log.user_id == nil
      assert log.action == "video.processed"
    end

    test "correctly extracts resource type and ID from structs" do
      org = insert(:organization)

      assert {:ok, %Log{} = log} = Audit.log(nil, "organization.created", org)

      assert log.resource_type == "Organization"
      assert log.resource_id == org.id
    end

    test "audit logs are append-only (no updated_at field)" do
      video = insert(:video)

      assert {:ok, %Log{} = log} = Audit.log(nil, "video.created", video)

      assert log.inserted_at != nil
      refute Map.has_key?(Map.from_struct(log), :updated_at)
    end
  end
end
