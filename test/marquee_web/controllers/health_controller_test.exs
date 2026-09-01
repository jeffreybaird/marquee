defmodule MarqueeWeb.HealthControllerTest do
  use MarqueeWeb.ConnCase, async: true

  describe "GET /health" do
    test "returns 200 with ok status when all services are running", %{conn: conn} do
      conn = get(conn, "/health")

      assert json_response(conn, 200) == %{
               "status" => "ok",
               "checks" => %{
                 "pubsub" => "ok",
                 "repo" => "ok",
                 "oban" => "ok"
               }
             }
    end
  end
end
