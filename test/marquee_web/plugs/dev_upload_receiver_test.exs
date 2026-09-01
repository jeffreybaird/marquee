defmodule MarqueeWeb.Plugs.DevUploadReceiverTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias MarqueeWeb.Plugs.DevUploadReceiver

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "marquee_dev_upload_plug_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)

    original = Application.get_env(:marquee, Marquee.Storage, [])

    Application.put_env(
      :marquee,
      Marquee.Storage,
      Keyword.put(original, :local_upload_dir, tmp_dir)
    )

    on_exit(fn ->
      Application.put_env(:marquee, Marquee.Storage, original)
      File.rm_rf!(tmp_dir)
    end)

    %{tmp_dir: tmp_dir}
  end

  describe "call/2" do
    test "writes PUT body to disk under the given key and returns 200",
         %{tmp_dir: tmp_dir} do
      body = "jpeg-bytes"

      conn =
        conn(:put, "/dev/uploads/org/abc/series_cover/x.jpg", body)
        |> put_req_header("content-type", "image/jpeg")
        |> DevUploadReceiver.call([])

      assert conn.status == 200
      assert conn.halted
      assert conn.resp_body =~ "\"key\":\"org/abc/series_cover/x.jpg\""

      stored = File.read!(Path.join(tmp_dir, "org/abc/series_cover/x.jpg"))
      assert stored == body
    end

    test "creates parent directories under the upload root", %{tmp_dir: tmp_dir} do
      conn =
        conn(:put, "/dev/uploads/a/b/c/file.bin", "data")
        |> DevUploadReceiver.call([])

      assert conn.status == 200
      assert File.exists?(Path.join(tmp_dir, "a/b/c/file.bin"))
    end

    test "responds to CORS preflight with 204 and permissive headers" do
      conn =
        conn(:options, "/dev/uploads/anything")
        |> DevUploadReceiver.call([])

      assert conn.status == 204
      assert conn.halted
      assert get_resp_header(conn, "access-control-allow-origin") == ["*"]
      assert get_resp_header(conn, "access-control-allow-methods") == ["PUT, OPTIONS"]
    end

    test "passes unrelated requests through untouched" do
      conn =
        conn(:get, "/something-else")
        |> DevUploadReceiver.call([])

      refute conn.halted
      assert conn.status == nil
    end

    test "ignores PUTs outside the upload prefix" do
      conn =
        conn(:put, "/api/other", "body")
        |> DevUploadReceiver.call([])

      refute conn.halted
    end

    test "returns 400 when the key is empty" do
      conn =
        conn(:put, "/dev/uploads/", "data")
        |> DevUploadReceiver.call([])

      assert conn.status == 400
      assert conn.halted
    end
  end
end
