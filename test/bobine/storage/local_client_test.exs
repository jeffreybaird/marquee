defmodule Bobine.Storage.LocalClientTest do
  use ExUnit.Case, async: true

  alias Bobine.Storage.LocalClient

  setup do
    tmp_dir =
      Path.join(System.tmp_dir!(), "bobine_local_client_#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp_dir)

    original = Application.get_env(:bobine, Bobine.Storage, [])

    Application.put_env(
      :bobine,
      Bobine.Storage,
      Keyword.put(original, :local_upload_dir, tmp_dir)
    )

    on_exit(fn ->
      Application.put_env(:bobine, Bobine.Storage, original)
      File.rm_rf!(tmp_dir)
    end)

    %{tmp_dir: tmp_dir}
  end

  describe "presign_put/1" do
    test "returns a dev presigned response pointing at the local receiver" do
      assert {:ok, presigned} =
               LocalClient.presign_put(
                 key: "org/abc/series_cover/x.jpg",
                 content_type: "image/jpeg"
               )

      assert presigned.presigned_url == "/dev/uploads/org/abc/series_cover/x.jpg"
      assert presigned.public_url == "/uploads/org/abc/series_cover/x.jpg"
      assert presigned.key == "org/abc/series_cover/x.jpg"
      assert presigned.headers["Content-Type"] == "image/jpeg"
      assert %DateTime{} = presigned.expires_at
    end

    test "defaults content-type when none is given" do
      assert {:ok, presigned} = LocalClient.presign_put(key: "k")
      assert presigned.headers["Content-Type"] == "application/octet-stream"
    end
  end

  describe "put_object/3" do
    test "writes bytes to the configured upload directory", %{tmp_dir: tmp_dir} do
      key = "org/abc/exports/audit/file.csv"

      assert :ok = LocalClient.put_object(key, "id,name\n1,a\n", "text/csv")

      full_path = Path.join(tmp_dir, key)
      assert File.exists?(full_path)
      assert File.read!(full_path) == "id,name\n1,a\n"
    end

    test "creates parent directories as needed", %{tmp_dir: tmp_dir} do
      key = "nested/deep/path/file.bin"

      assert :ok = LocalClient.put_object(key, "data", "application/octet-stream")
      assert File.exists?(Path.join(tmp_dir, key))
    end
  end

  describe "upload_dir/0" do
    test "returns the configured directory", %{tmp_dir: tmp_dir} do
      assert LocalClient.upload_dir() == tmp_dir
    end
  end
end
