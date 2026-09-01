defmodule Marquee.Workers.PodcastFeedSyncTest do
  use Marquee.DataCase, async: false
  use Oban.Testing, repo: Marquee.Repo

  import Mox

  alias Marquee.Podcasts.{Episode, MockRemoteFeedClient, Show}
  alias Marquee.Repo
  alias Marquee.Workers.PodcastFeedSync

  setup :set_mox_from_context
  setup :verify_on_exit!

  @rss """
  <?xml version="1.0" encoding="UTF-8"?>
  <rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">
    <channel>
      <title>Sample</title>
      <description>A sample feed.</description>
      <item>
        <guid>ep-1</guid>
        <title>Pilot</title>
        <description>The first one</description>
        <enclosure url="https://example.com/ep1.mp3" length="123456" type="audio/mpeg"/>
        <pubDate>Mon, 01 Jan 2024 12:00:00 +0000</pubDate>
        <itunes:duration>1800</itunes:duration>
      </item>
    </channel>
  </rss>
  """

  describe "per-show sync" do
    test "fetches, parses, and upserts episodes; clears prior failure state" do
      org = insert(:organization)

      show =
        insert(:feed_import_show,
          organization: org,
          remote_feed_url: "https://example.com/feed.xml",
          remote_consecutive_failures: 2,
          remote_last_sync_error: "old error"
        )

      expect(MockRemoteFeedClient, :fetch, fn "https://example.com/feed.xml" ->
        {:ok, %{status: 200, body: @rss, headers: []}}
      end)

      assert :ok = perform_job(PodcastFeedSync, %{"show_id" => show.id})

      reloaded = Repo.get!(Show, show.id)
      assert reloaded.remote_consecutive_failures == 0
      assert reloaded.remote_last_sync_error == nil
      assert reloaded.remote_last_synced_at != nil

      assert [%Episode{guid: "ep-1", title: "Pilot"}] =
               Repo.all(Ecto.Query.from(e in Episode, where: e.show_id == ^show.id))
    end

    test "non-200 response increments the failure counter" do
      org = insert(:organization)

      show =
        insert(:feed_import_show,
          organization: org,
          remote_feed_url: "https://example.com/missing.xml"
        )

      expect(MockRemoteFeedClient, :fetch, fn _ ->
        {:ok, %{status: 404, body: "", headers: []}}
      end)

      assert {:error, _} = perform_job(PodcastFeedSync, %{"show_id" => show.id})

      reloaded = Repo.get!(Show, show.id)
      assert reloaded.remote_consecutive_failures == 1
      assert reloaded.remote_last_sync_error =~ "404"
    end

    test "fetch error is recorded" do
      org = insert(:organization)
      show = insert(:feed_import_show, organization: org)

      expect(MockRemoteFeedClient, :fetch, fn _ -> {:error, :timeout} end)

      assert {:error, _} = perform_job(PodcastFeedSync, %{"show_id" => show.id})

      reloaded = Repo.get!(Show, show.id)
      assert reloaded.remote_last_sync_error =~ "timeout"
    end

    test "deleted show is a no-op" do
      org = insert(:organization)

      show =
        insert(:feed_import_show,
          organization: org,
          deleted_at: DateTime.utc_now() |> DateTime.truncate(:second)
        )

      assert :ok = perform_job(PodcastFeedSync, %{"show_id" => show.id})
    end
  end

  describe "cron tick" do
    test "enqueues per-show jobs for each due feed_import show" do
      org = insert(:organization)
      due_a = insert(:feed_import_show, organization: org, remote_last_synced_at: nil)

      due_b =
        insert(:feed_import_show,
          organization: org,
          remote_last_synced_at:
            DateTime.utc_now() |> DateTime.add(-3600, :second) |> DateTime.truncate(:second)
        )

      _recent =
        insert(:feed_import_show,
          organization: org,
          remote_last_synced_at: DateTime.utc_now() |> DateTime.truncate(:second)
        )

      _paused =
        insert(:feed_import_show,
          organization: org,
          remote_consecutive_failures: 5,
          remote_last_synced_at: nil
        )

      _direct =
        insert(:podcast_show, organization: org, source_type: "direct_upload")

      stub(MockRemoteFeedClient, :fetch, fn _ ->
        {:ok, %{status: 200, body: @rss, headers: []}}
      end)

      assert :ok = perform_job(PodcastFeedSync, %{})

      # Two due shows ran inline (testing: :inline) and now show synced timestamps
      assert Repo.get!(Show, due_a.id).remote_last_synced_at != nil
      assert Repo.get!(Show, due_b.id).remote_last_synced_at != nil
    end
  end

  describe "manual enqueue" do
    test "enqueue_for_show/1 inserts a per-show job tagged manual" do
      org = insert(:organization)
      show = insert(:feed_import_show, organization: org)

      stub(MockRemoteFeedClient, :fetch, fn _ ->
        {:ok, %{status: 200, body: @rss, headers: []}}
      end)

      assert {:ok, %Oban.Job{}} = PodcastFeedSync.enqueue_for_show(show)
      assert Repo.get!(Show, show.id).remote_last_synced_at != nil
    end
  end
end
