defmodule Marquee.IdempotencyTest do
  use ExUnit.Case, async: true

  alias Marquee.Idempotency

  describe "key/3" do
    test "is deterministic for the same inputs on the same day" do
      key1 = Idempotency.key("create_upload", "org_1", "video_1")
      key2 = Idempotency.key("create_upload", "org_1", "video_1")
      assert key1 == key2
    end

    test "changes for different operations" do
      key1 = Idempotency.key("create_upload", "org_1", "video_1")
      key2 = Idempotency.key("delete_asset", "org_1", "video_1")
      assert key1 != key2
    end

    test "changes for different resources" do
      key1 = Idempotency.key("create_upload", "org_1", "video_1")
      key2 = Idempotency.key("create_upload", "org_1", "video_2")
      assert key1 != key2
    end

    test "includes the current date" do
      key = Idempotency.key("create_upload", "org_1", "video_1")
      assert String.contains?(key, Date.to_string(Date.utc_today()))
    end
  end
end
