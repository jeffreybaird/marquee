defmodule Marquee.Storage.SpacesClientTest do
  @moduledoc """
  Unit tests for the real `SpacesClient` — specifically the credential-check
  path. The happy presign path hits `ExAws.S3.presigned_url`, which needs
  real AWS config plumbing; that's exercised in staging. These tests cover
  the failure modes we care about catching before we ship a cryptic
  EC2-IMDS timeout to users.
  """

  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Marquee.Storage.SpacesClient

  setup do
    original_key = Application.get_env(:ex_aws, :access_key_id)
    original_secret = Application.get_env(:ex_aws, :secret_access_key)

    on_exit(fn ->
      restore_env(:access_key_id, original_key)
      restore_env(:secret_access_key, original_secret)
    end)

    :ok
  end

  describe "presign_put/1 credential handling" do
    test "returns :spaces_credentials_not_configured when both creds are missing" do
      Application.delete_env(:ex_aws, :access_key_id)
      Application.delete_env(:ex_aws, :secret_access_key)

      log =
        capture_log(fn ->
          assert {:error, :spaces_credentials_not_configured} =
                   SpacesClient.presign_put(
                     key: "org/abc/series_cover/x.jpg",
                     content_type: "image/jpeg"
                   )
        end)

      assert log =~ "Spaces credentials not configured"
      assert log =~ "SPACES_ACCESS_KEY_ID"
    end

    test "returns :spaces_credentials_not_configured when only access key is set" do
      Application.put_env(:ex_aws, :access_key_id, "some-key")
      Application.delete_env(:ex_aws, :secret_access_key)

      assert capture_log(fn ->
               assert {:error, :spaces_credentials_not_configured} =
                        SpacesClient.presign_put(
                          key: "org/abc/series_cover/x.jpg",
                          content_type: "image/jpeg"
                        )
             end) =~ "Spaces credentials not configured"
    end

    test "returns :spaces_credentials_not_configured when the ex_aws default chain is in place" do
      # ex_aws' default access_key_id is a list (system / pod / instance-role).
      # If runtime.exs never wrote a string, we should not hand that list
      # off to ExAws.Config.new — catch it here instead.
      Application.put_env(:ex_aws, :access_key_id, [
        {:system, "AWS_ACCESS_KEY_ID"},
        :pod_identity,
        :instance_role
      ])

      Application.put_env(:ex_aws, :secret_access_key, [
        {:system, "AWS_SECRET_ACCESS_KEY"},
        :pod_identity,
        :instance_role
      ])

      assert capture_log(fn ->
               assert {:error, :spaces_credentials_not_configured} =
                        SpacesClient.presign_put(
                          key: "org/abc/series_cover/x.jpg",
                          content_type: "image/jpeg"
                        )
             end) =~ "Spaces credentials not configured"
    end

    test "rejects blank string credentials" do
      Application.put_env(:ex_aws, :access_key_id, "")
      Application.put_env(:ex_aws, :secret_access_key, "")

      capture_log(fn ->
        assert {:error, :spaces_credentials_not_configured} =
                 SpacesClient.presign_put(
                   key: "org/abc/series_cover/x.jpg",
                   content_type: "image/jpeg"
                 )
      end)
    end
  end

  defp restore_env(_key, nil), do: :ok
  defp restore_env(key, value), do: Application.put_env(:ex_aws, key, value)
end
