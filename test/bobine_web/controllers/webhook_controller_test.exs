defmodule BobineWeb.WebhookControllerTest do
  use BobineWeb.ConnCase, async: true
  use Oban.Testing, repo: Bobine.Repo

  describe "POST /webhooks/mux" do
    test "rejects webhook when no secret is configured", %{conn: conn} do
      Application.delete_env(:bobine, :mux_webhook_secret)

      payload = Jason.encode!(%{type: "video.asset.ready", data: %{id: "asset_1"}})

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/webhooks/mux", payload)

      assert conn.status == 400
    end

    test "accepts webhook with valid signature", %{conn: conn} do
      secret = "test-webhook-secret-123"
      Application.put_env(:bobine, :mux_webhook_secret, secret)

      on_exit(fn ->
        Application.delete_env(:bobine, :mux_webhook_secret)
      end)

      payload = Jason.encode!(%{type: "video.asset.ready", data: %{id: "asset_1"}})
      timestamp = System.system_time(:second)

      signature =
        :crypto.mac(:hmac, :sha256, secret, "#{timestamp}.#{payload}")
        |> Base.encode16(case: :lower)

      header = "t=#{timestamp},v1=#{signature}"

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("mux-signature", header)
        |> post("/webhooks/mux", payload)

      assert conn.status == 200
    end

    test "rejects webhook with invalid signature", %{conn: conn} do
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

    test "rejects webhook with no signature header", %{conn: conn} do
      Application.put_env(:bobine, :mux_webhook_secret, "test-secret")

      on_exit(fn ->
        Application.delete_env(:bobine, :mux_webhook_secret)
      end)

      payload = Jason.encode!(%{type: "video.asset.ready", data: %{id: "asset_1"}})

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/webhooks/mux", payload)

      assert conn.status == 400
    end
  end
end
