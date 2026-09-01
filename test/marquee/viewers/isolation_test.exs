defmodule Marquee.Viewers.IsolationTest do
  use Marquee.DataCase

  alias Marquee.Viewers

  setup do
    org_a = insert(:organization)
    org_b = insert(:organization)
    %{org_a: org_a, org_b: org_b}
  end

  describe "cross-tenant email lookup isolation" do
    test "viewer on org A is not found via get_viewer_by_email on org B", %{
      org_a: org_a,
      org_b: org_b
    } do
      viewer = insert(:viewer, organization: org_a, email: "alice@example.com")

      assert Viewers.get_viewer_by_email(org_a, viewer.email) != nil
      assert is_nil(Viewers.get_viewer_by_email(org_b, viewer.email))
    end
  end

  describe "cross-tenant session token isolation" do
    test "session token from org A viewer returns org A viewer (not org B)", %{
      org_a: org_a,
      org_b: org_b
    } do
      viewer_a = insert(:viewer, organization: org_a)
      _viewer_b = insert(:viewer, organization: org_b)

      token = Viewers.generate_viewer_session_token(viewer_a)
      found = Viewers.get_viewer_by_session_token(token)

      # The token resolves to the viewer, and that viewer belongs to org_a
      assert found.id == viewer_a.id
      assert found.organization_id == org_a.id
      assert found.organization_id != org_b.id
    end
  end

  describe "cross-tenant list isolation" do
    test "list_viewers on org A never returns org B viewers", %{org_a: org_a, org_b: org_b} do
      viewer_a = insert(:viewer, organization: org_a)
      _viewer_b = insert(:viewer, organization: org_b)

      result = Viewers.list_viewers(org_a)
      viewer_ids = Enum.map(result.results, & &1.id)

      assert viewer_a.id in viewer_ids
      refute Enum.any?(result.results, fn v -> v.organization_id == org_b.id end)
    end

    test "list_viewers on org B never returns org A viewers", %{org_a: org_a, org_b: org_b} do
      _viewer_a = insert(:viewer, organization: org_a)
      viewer_b = insert(:viewer, organization: org_b)

      result = Viewers.list_viewers(org_b)
      viewer_ids = Enum.map(result.results, & &1.id)

      assert viewer_b.id in viewer_ids
      refute Enum.any?(result.results, fn v -> v.organization_id == org_a.id end)
    end
  end

  describe "cross-tenant get_viewer isolation" do
    test "get_viewer on org A returns not_found for org B viewer", %{
      org_a: org_a,
      org_b: org_b
    } do
      viewer_b = insert(:viewer, organization: org_b)
      assert {:error, :not_found} = Viewers.get_viewer(org_a, viewer_b.id)
    end

    test "get_viewer on org B returns not_found for org A viewer", %{
      org_a: org_a,
      org_b: org_b
    } do
      viewer_a = insert(:viewer, organization: org_a)
      assert {:error, :not_found} = Viewers.get_viewer(org_b, viewer_a.id)
    end
  end

  describe "cross-tenant operator action isolation" do
    test "operator cannot suspend a viewer from another org via get_viewer", %{
      org_a: org_a,
      org_b: org_b
    } do
      viewer_b = insert(:viewer, organization: org_b, status: :active)

      # Operator on org A tries to find the viewer — gets not_found
      assert {:error, :not_found} = Viewers.get_viewer(org_a, viewer_b.id)

      # Confirm the viewer is still active on org B
      assert {:ok, still_active} = Viewers.get_viewer(org_b, viewer_b.id)
      assert still_active.status == :active
    end

    test "operator cannot ban a viewer from another org via get_viewer", %{
      org_a: org_a,
      org_b: org_b
    } do
      viewer_b = insert(:viewer, organization: org_b, status: :active)

      # Operator on org A cannot find the viewer
      assert {:error, :not_found} = Viewers.get_viewer(org_a, viewer_b.id)

      # Confirm the viewer is still active on org B
      assert {:ok, still_active} = Viewers.get_viewer(org_b, viewer_b.id)
      assert still_active.status == :active
    end
  end

  describe "cross-tenant count isolation" do
    test "count_viewers only counts viewers for the given org", %{org_a: org_a, org_b: org_b} do
      insert(:viewer, organization: org_a)
      insert(:viewer, organization: org_a)
      insert(:viewer, organization: org_b)

      assert Viewers.count_viewers(org_a) == 2
      assert Viewers.count_viewers(org_b) == 1
    end
  end

  describe "cross-tenant hard delete isolation" do
    test "hard_delete_viewer_data rejects viewer from different org", %{
      org_a: org_a,
      org_b: org_b
    } do
      viewer_b = insert(:viewer, organization: org_b)

      assert {:error, :forbidden} = Viewers.hard_delete_viewer_data(org_a, viewer_b)

      # Viewer still exists in org B
      assert {:ok, _} = Viewers.get_viewer(org_b, viewer_b.id)
    end
  end
end
