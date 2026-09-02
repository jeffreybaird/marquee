defmodule MarqueeWeb.SampleContentControllerTest do
  use MarqueeWeb.ConnCase

  alias Marquee.Onboarding.StarterContent

  describe "DELETE /admin/sample-content" do
    setup do
      org = insert(:organization)
      membership = insert(:membership, organization: org, role: :owner)
      {:ok, _} = StarterContent.seed(org)
      %{org: org, membership: membership}
    end

    test "clears sample content and redirects to the dashboard", %{
      membership: membership,
      org: org
    } do
      conn = conn_for(membership) |> delete(~p"/admin/sample-content")

      assert redirected_to(conn) == ~p"/admin"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Removed"
      refute StarterContent.seeded?(org)
    end

    test "an editor may clear sample content", %{org: org} do
      editor = insert(:membership, organization: org, role: :editor)
      conn = conn_for(editor) |> delete(~p"/admin/sample-content")

      assert redirected_to(conn) == ~p"/admin"
      refute StarterContent.seeded?(org)
    end

    test "a read-only viewer_support member is rejected", %{org: org} do
      support = insert(:membership, organization: org, role: :viewer_support)
      conn = conn_for(support) |> delete(~p"/admin/sample-content")

      # RequireRole redirects below-threshold roles; sample content survives.
      assert redirected_to(conn) == ~p"/admin"
      assert StarterContent.seeded?(org)
    end
  end
end
