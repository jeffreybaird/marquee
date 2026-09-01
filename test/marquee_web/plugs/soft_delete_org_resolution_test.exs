defmodule MarqueeWeb.Plugs.SoftDeleteOrgResolutionTest do
  use MarqueeWeb.ConnCase, async: true

  describe "soft-deleted org resolution" do
    test "soft-deleted org still resolves (not 404) for deactivation page", %{conn: conn} do
      org = insert(:organization, slug: "deleted-org")
      # Soft-delete the org
      Marquee.Admin.delete_organization(org)

      conn =
        conn
        |> Map.put(:host, "deleted-org.localhost")
        |> get("/")

      # Should NOT be 404 — the org should resolve so we can show
      # a "this site is no longer available" page
      refute conn.status == 404
    end
  end
end
