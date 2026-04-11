defmodule Bobine.Workers.AuditLogExporterTest do
  use Bobine.DataCase, async: true
  use Oban.Testing, repo: Bobine.Repo

  import Mox

  alias Bobine.Storage.MockSpacesClient
  alias Bobine.Workers.AuditLogExporter

  setup :verify_on_exit!

  describe "perform/1 — org scope" do
    test "generates CSV with correct rows and uploads to storage" do
      org = insert(:organization)
      user = insert(:user)

      insert(:audit_log,
        organization: org,
        user: user,
        action: "video.created",
        resource_type: "Video"
      )

      test_pid = self()

      MockSpacesClient
      |> expect(:put_object, fn key, body, "text/csv" ->
        send(test_pid, {:put_object_called, key, body})
        :ok
      end)

      user_id = user.id

      assert :ok =
               perform_job(AuditLogExporter, %{
                 "organization_id" => org.id,
                 "scope" => "org",
                 "filters" => %{},
                 "user_id" => user_id,
                 "format" => "csv"
               })

      assert_received {:put_object_called, key, csv_body}
      assert String.starts_with?(key, "exports/audit/#{org.id}/")
      assert String.ends_with?(key, ".csv")
      assert csv_body =~ "timestamp,actor_email,action"
      assert csv_body =~ "video.created"
      assert csv_body =~ user.email
    end

    test "broadcasts :audit_export_ready on success" do
      org = insert(:organization)
      user = insert(:user)

      Phoenix.PubSub.subscribe(Bobine.PubSub, "audit-exports:#{user.id}")

      MockSpacesClient
      |> expect(:put_object, fn _key, _body, _ct -> :ok end)

      assert :ok =
               perform_job(AuditLogExporter, %{
                 "organization_id" => org.id,
                 "scope" => "org",
                 "filters" => %{},
                 "user_id" => user.id,
                 "format" => "csv"
               })

      assert_receive {:audit_export_ready, url}
      assert String.contains?(url, "exports/audit/#{org.id}/")
    end

    test "handles empty result set (no logs)" do
      org = insert(:organization)
      user = insert(:user)

      MockSpacesClient
      |> expect(:put_object, fn _key, body, "text/csv" ->
        lines = String.split(body, "\n")
        # Only header row
        assert length(lines) == 1
        :ok
      end)

      assert :ok =
               perform_job(AuditLogExporter, %{
                 "organization_id" => org.id,
                 "scope" => "org",
                 "filters" => %{},
                 "user_id" => user.id,
                 "format" => "csv"
               })
    end
  end

  describe "perform/1 — platform scope" do
    test "exports logs across all orgs" do
      org_a = insert(:organization)
      org_b = insert(:organization)
      user = insert(:user)
      insert(:audit_log, organization: org_a, action: "video.created")
      insert(:audit_log, organization: org_b, action: "collection.updated")

      MockSpacesClient
      |> expect(:put_object, fn key, body, "text/csv" ->
        assert String.starts_with?(key, "exports/audit/platform/")
        assert body =~ "video.created"
        assert body =~ "collection.updated"
        :ok
      end)

      assert :ok =
               perform_job(AuditLogExporter, %{
                 "organization_id" => nil,
                 "scope" => "platform",
                 "filters" => %{},
                 "user_id" => user.id,
                 "format" => "csv"
               })
    end
  end

  describe "perform/1 — storage failure" do
    test "broadcasts :audit_export_failed and returns error on storage failure" do
      org = insert(:organization)
      user = insert(:user)

      Phoenix.PubSub.subscribe(Bobine.PubSub, "audit-exports:#{user.id}")

      MockSpacesClient
      |> expect(:put_object, fn _key, _body, _ct -> {:error, :network_error} end)

      assert {:error, _reason} =
               perform_job(AuditLogExporter, %{
                 "organization_id" => org.id,
                 "scope" => "org",
                 "filters" => %{},
                 "user_id" => user.id,
                 "format" => "csv"
               })

      assert_receive {:audit_export_failed, _reason}
    end
  end
end
