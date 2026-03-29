defmodule BobineWeb.WebhookControllerTest do
  use BobineWeb.ConnCase, async: true
  use Oban.Testing, repo: Bobine.Repo

  describe "POST /webhooks/mux" do
    test "accepts valid webhook payload and returns 200", %{conn: conn} do
      payload = Jason.encode!(%{type: "video.asset.ready", data: %{id: "asset_1"}})

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/webhooks/mux", payload)

      # In test, Oban runs inline so the job is already processed
      assert conn.status == 200
      assert conn.resp_body == "ok"
    end

    test "returns 400 for invalid signature when secret is configured", %{conn: conn} do
      Application.put_env(:bobine, :mux_webhook_secret, "test-secret")

      on_exit(fn ->
        Application.delete_env(:bobine, :mux_webhook_secret)
      end)

      payload = Jason.encode!(%{type: "video.asset.ready", data: %{id: "asset_1"}})

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("mux-signature", "invalid-sig")
        |> post("/webhooks/mux", payload)

      assert conn.status == 400
    end
  end
end
