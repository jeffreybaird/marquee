defmodule Bobine.Branding.CacheSubscriberTest do
  use Bobine.DataCase, async: true

  alias Bobine.Branding.CacheSubscriber
  alias Bobine.Cache

  describe "handle_info/2" do
    test "invalidates theme cache on :theme_created" do
      org_id = Ecto.UUID.generate()
      Cache.put("theme:#{org_id}", :cached_value)
      assert {:ok, :cached_value} = Cache.get("theme:#{org_id}")

      msg = {:bobine_event, {:theme_created, %{organization_id: org_id}}, nil}
      {:noreply, _} = CacheSubscriber.handle_info(msg, %{})

      assert :miss = Cache.get("theme:#{org_id}")
    end

    test "invalidates theme cache on :theme_updated" do
      org_id = Ecto.UUID.generate()
      Cache.put("theme:#{org_id}", :cached_value)

      msg = {:bobine_event, {:theme_updated, %{organization_id: org_id}}, nil}
      {:noreply, _} = CacheSubscriber.handle_info(msg, %{})

      assert :miss = Cache.get("theme:#{org_id}")
    end

    test "invalidates theme cache on :theme_deleted" do
      org_id = Ecto.UUID.generate()
      Cache.put("theme:#{org_id}", :cached_value)

      msg = {:bobine_event, {:theme_deleted, %{organization_id: org_id}}, nil}
      {:noreply, _} = CacheSubscriber.handle_info(msg, %{})

      assert :miss = Cache.get("theme:#{org_id}")
    end

    test "ignores unrelated events" do
      org_id = Ecto.UUID.generate()
      Cache.put("theme:#{org_id}", :cached_value)

      msg = {:bobine_event, {:video_created, %{organization_id: org_id}}, nil}
      {:noreply, _} = CacheSubscriber.handle_info(msg, %{})

      assert {:ok, :cached_value} = Cache.get("theme:#{org_id}")
    end

    test "no-op when event payload has nil organization_id" do
      msg = {:bobine_event, {:theme_updated, %{organization_id: nil}}, nil}
      assert {:noreply, %{}} = CacheSubscriber.handle_info(msg, %{})
    end
  end

  describe "end-to-end via PubSub" do
    test "broadcasting :theme_updated invalidates the cached theme" do
      org_id = Ecto.UUID.generate()
      Cache.put("theme:#{org_id}", :cached_value)

      :ok =
        Phoenix.PubSub.broadcast(
          Bobine.PubSub,
          "events:global",
          {:bobine_event, {:theme_updated, %{organization_id: org_id}}, nil}
        )

      # Subscriber runs async; wait briefly for the handle_info to fire.
      Process.sleep(20)
      assert :miss = Cache.get("theme:#{org_id}")
    end
  end
end
