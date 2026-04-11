defmodule Bobine.StorageTest do
  use Bobine.DataCase, async: false

  import Mox
  setup :verify_on_exit!

  alias Bobine.Storage
  alias Bobine.Storage.MockSpacesClient

  setup do
    org = insert(:organization)
    %{org: org}
  end

  describe "config/0" do
    test "returns the test-env config values" do
      cfg = Storage.config()
      assert cfg.bucket == "bobine-test"
      assert cfg.region == "nyc3"
      assert cfg.host == "nyc3.digitaloceanspaces.com"
      assert cfg.public_url_base == "https://bobine-test.nyc3.digitaloceanspaces.com"
      assert cfg.client == MockSpacesClient
    end
  end

  describe "build_key/3" do
    test "scopes the key under org/<id>/<kind>/", %{org: org} do
      key = Storage.build_key(org.id, "series_cover", "pilot.jpg")
      assert String.starts_with?(key, "org/#{org.id}/series_cover/")
      assert String.ends_with?(key, ".jpg")
    end

    test "handles filenames with no extension" do
      key = Storage.build_key("abc", "video_thumbnail", "noext")
      assert String.starts_with?(key, "org/abc/video_thumbnail/")
      refute String.contains?(key, ".")
    end

    test "uses fresh uuids so repeat calls don't collide" do
      k1 = Storage.build_key("abc", "k", "x.jpg")
      k2 = Storage.build_key("abc", "k", "x.jpg")
      assert k1 != k2
    end
  end

  describe "presign_upload/3" do
    test "delegates to the configured client with a sensible key", %{org: org} do
      MockSpacesClient
      |> expect(:presign_put, fn opts ->
        assert opts[:content_type] == "image/jpeg"
        assert String.starts_with?(opts[:key], "org/#{org.id}/series_cover/")
        assert opts[:expires_in] == 900

        {:ok,
         %{
           presigned_url: "https://spaces.example.com/" <> opts[:key],
           public_url: "https://bobine-test.nyc3.digitaloceanspaces.com/" <> opts[:key],
           key: opts[:key],
           expires_at: DateTime.utc_now() |> DateTime.add(900, :second),
           headers: %{"Content-Type" => "image/jpeg"}
         }}
      end)

      assert {:ok, presigned} =
               Storage.presign_upload(org, "series_cover",
                 content_type: "image/jpeg",
                 filename: "pilot.jpg"
               )

      assert presigned.public_url =~ presigned.key
    end

    test "propagates client errors", %{org: org} do
      MockSpacesClient
      |> expect(:presign_put, fn _opts -> {:error, :invalid_credentials} end)

      assert {:error, :invalid_credentials} =
               Storage.presign_upload(org, "series_cover", content_type: "image/jpeg")
    end
  end

  describe "allowed_image_content_type?/1" do
    test "accepts common image types" do
      for t <- ~w(image/jpeg image/png image/webp image/gif image/avif) do
        assert Storage.allowed_image_content_type?(t)
      end
    end

    test "rejects everything else" do
      for t <- ~w(application/pdf text/html video/mp4),
          do: refute(Storage.allowed_image_content_type?(t))

      refute Storage.allowed_image_content_type?(nil)
      refute Storage.allowed_image_content_type?(42)
    end
  end
end
