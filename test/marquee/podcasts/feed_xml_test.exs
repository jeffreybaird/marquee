defmodule Marquee.Podcasts.FeedXmlTest do
  use ExUnit.Case, async: true

  import SweetXml

  alias Marquee.Podcasts.{Episode, FeedToken, FeedXml, Show}

  doctest FeedXml, import: true

  defp build_show do
    %Show{
      id: Ecto.UUID.generate(),
      organization_id: Ecto.UUID.generate(),
      title: "Sample & Friends",
      slug: "sample",
      description: "All about <stuff>",
      author: "Test Author",
      owner_name: "Owner",
      owner_email: "owner@example.com",
      language: "en-us",
      primary_category: "Technology",
      secondary_categories: ["News"],
      explicit: false,
      copyright: "© 2024",
      cover_artwork_url: "https://example.com/art.jpg"
    }
  end

  defp build_token, do: %FeedToken{token: "tok_abc"}

  defp build_episode(attrs \\ %{}) do
    Map.merge(
      %Episode{
        id: Ecto.UUID.generate(),
        guid: "ep-1",
        title: "Pilot",
        description: "first one",
        publish_date: ~U[2024-03-04 09:30:00Z],
        duration_seconds: 3725,
        episode_number: 1,
        season_number: 1,
        episode_type: "full",
        explicit: false,
        mp3_byte_size: 9_000_000
      },
      attrs
    )
    |> then(fn map -> struct(Episode, Map.from_struct(map)) end)
  end

  test "renders a feed with iTunes namespace and channel metadata" do
    show = build_show()
    token = build_token()
    ep = build_episode()

    xml =
      FeedXml.render(show, token, [ep], fn _ -> "https://podcasts.test/audio/ep1.mp3" end,
        feed_url: "https://podcasts.test/feed.xml"
      )

    assert xml =~ ~s(<?xml version="1.0" encoding="UTF-8"?>)
    assert xml =~ ~s(xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd")

    doc = SweetXml.parse(xml)
    assert xpath(doc, ~x"//rss/channel/title/text()"s) == "Sample & Friends"
    assert xpath(doc, ~x"//rss/channel/itunes:author/text()"s) == "Test Author"
    assert xpath(doc, ~x"//rss/channel/itunes:owner/itunes:email/text()"s) == "owner@example.com"
    assert xpath(doc, ~x"//rss/channel/itunes:image/@href"s) == "https://example.com/art.jpg"

    assert xpath(doc, ~x"//rss/channel/itunes:category[1]/@text"s) == "Technology"
    assert xpath(doc, ~x"//rss/channel/itunes:category[2]/@text"s) == "News"
  end

  test "items include enclosure URL, duration, guid, and pubDate" do
    show = build_show()
    token = build_token()
    ep = build_episode()

    xml =
      FeedXml.render(show, token, [ep], fn _ -> "https://podcasts.test/audio/ep1.mp3" end,
        feed_url: "https://podcasts.test/feed.xml"
      )

    doc = SweetXml.parse(xml)
    assert xpath(doc, ~x"//item/title/text()"s) == "Pilot"
    assert xpath(doc, ~x"//item/guid/text()"s) == "ep-1"
    assert xpath(doc, ~x"//item/enclosure/@url"s) == "https://podcasts.test/audio/ep1.mp3"
    assert xpath(doc, ~x"//item/enclosure/@length"s) == "9000000"
    assert xpath(doc, ~x"//item/enclosure/@type"s) == "audio/mpeg"
    assert xpath(doc, ~x"//item/itunes:duration/text()"s) == "01:02:05"
    assert xpath(doc, ~x"//item/pubDate/text()"s) == "Mon, 04 Mar 2024 09:30:00 +0000"
  end

  test "feed-import episode uses remote_audio_byte_size + content_type" do
    show = build_show()
    token = build_token()

    ep =
      build_episode(%{
        mp3_byte_size: nil,
        remote_audio_byte_size: 1234,
        remote_audio_content_type: "audio/x-m4a"
      })

    xml = FeedXml.render(show, token, [ep], fn _ -> "https://x" end, feed_url: "https://feed")
    doc = SweetXml.parse(xml)

    assert xpath(doc, ~x"//item/enclosure/@length"s) == "1234"
    assert xpath(doc, ~x"//item/enclosure/@type"s) == "audio/x-m4a"
  end

  test "escapes XML-special characters in titles" do
    show = build_show()
    token = build_token()
    raw = "Q&A: <span> tag"
    ep = build_episode(%{title: raw})

    xml = FeedXml.render(show, token, [ep], fn _ -> "https://x" end, feed_url: "https://feed")
    refute xml =~ raw
    doc = SweetXml.parse(xml)
    assert xpath(doc, ~x"//item/title/text()"s) == raw
  end
end
