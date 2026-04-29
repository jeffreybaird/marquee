defmodule Bobine.Podcasts.FeedXml do
  @moduledoc """
  Builds the RSS XML for a tokenized podcast feed.

  Conforms to RSS 2.0 with the iTunes podcast namespace
  (`http://www.itunes.com/dtds/podcast-1.0.dtd`). All publish dates use
  RFC 822 formatting.

  Episode enclosure URLs route through the audio proxy and carry the
  feed token so revocation kills both the feed and the audio at once.
  """

  alias Bobine.Podcasts.{Episode, FeedToken, Show}

  @itunes_ns "http://www.itunes.com/dtds/podcast-1.0.dtd"

  @doc """
  Renders the feed XML for a show + feed token + ordered list of
  published episodes. `audio_url_fun` is a function that takes an
  Episode and returns the absolute audio URL the feed should advertise
  (lets the controller layer inject the right host without this module
  knowing about Plug.Conn).

  Exempt from doctest — exercised via integration tests.
  """
  def render(%Show{} = show, %FeedToken{} = _token, episodes, audio_url_fun, opts \\ [])
      when is_list(episodes) and is_function(audio_url_fun, 1) do
    feed_url = Keyword.fetch!(opts, :feed_url)

    items = Enum.map(episodes, &item_xml(show, &1, audio_url_fun))

    """
    <?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0" xmlns:itunes="#{@itunes_ns}" xmlns:atom="http://www.w3.org/2005/Atom">
      <channel>
        <title>#{xml_escape(show.title)}</title>
        <link>#{xml_escape(show_link(show, feed_url))}</link>
        <atom:link href="#{xml_escape(feed_url)}" rel="self" type="application/rss+xml"/>
        <language>#{xml_escape(show.language || "en-us")}</language>
        <description>#{xml_escape(show.description || "")}</description>
        #{author_tag(show)}
        #{owner_tag(show)}
        #{image_tag(show)}
        #{category_tags(show)}
        #{copyright_tag(show)}
        <itunes:explicit>#{if show.explicit, do: "true", else: "false"}</itunes:explicit>
        <itunes:type>episodic</itunes:type>
        #{Enum.join(items, "\n    ")}
      </channel>
    </rss>
    """
    |> String.trim()
    |> Kernel.<>("\n")
  end

  @doc """
  RFC 822 format of a DateTime. Suitable for `<pubDate>`.

      iex> alias Bobine.Podcasts.FeedXml
      iex> FeedXml.rfc822(~U[2024-03-04 09:30:00Z])
      "Mon, 04 Mar 2024 09:30:00 +0000"
  """
  def rfc822(%DateTime{} = dt) do
    day = day_name(Date.day_of_week(DateTime.to_date(dt)))
    month = month_name(dt.month)

    :io_lib.format(
      "~s, ~2..0B ~s ~4..0B ~2..0B:~2..0B:~2..0B +0000",
      [day, dt.day, month, dt.year, dt.hour, dt.minute, dt.second]
    )
    |> IO.iodata_to_binary()
  end

  defp item_xml(_show, %Episode{} = ep, audio_url_fun) do
    audio_url = audio_url_fun.(ep)
    duration = format_duration(ep.duration_seconds)

    """
    <item>
          <title>#{xml_escape(ep.title)}</title>
          <description>#{xml_escape(ep.description || "")}</description>
          <guid isPermaLink="false">#{xml_escape(ep.guid)}</guid>
          #{pub_date_tag(ep.publish_date)}
          <enclosure url="#{xml_escape(audio_url)}" length="#{enclosure_length(ep)}" type="#{enclosure_type(ep)}"/>
          <itunes:duration>#{duration}</itunes:duration>
          #{episode_number_tag(ep)}
          #{season_tag(ep)}
          <itunes:episodeType>#{xml_escape(ep.episode_type || "full")}</itunes:episodeType>
          <itunes:explicit>#{if ep.explicit, do: "true", else: "false"}</itunes:explicit>
        </item>
    """
    |> String.trim_trailing()
  end

  defp show_link(_show, feed_url), do: feed_url

  defp author_tag(%Show{author: nil}), do: ""

  defp author_tag(%Show{author: author}),
    do: "<itunes:author>#{xml_escape(author)}</itunes:author>"

  defp owner_tag(%Show{owner_name: nil, owner_email: nil}), do: ""

  defp owner_tag(%Show{owner_name: name, owner_email: email}) do
    """
    <itunes:owner>
          <itunes:name>#{xml_escape(name || "")}</itunes:name>
          <itunes:email>#{xml_escape(email || "")}</itunes:email>
        </itunes:owner>
    """
    |> String.trim_trailing()
  end

  defp image_tag(%Show{cover_artwork_url: nil}), do: ""

  defp image_tag(%Show{cover_artwork_url: url}),
    do: ~s(<itunes:image href="#{xml_escape(url)}"/>)

  defp category_tags(%Show{primary_category: nil, secondary_categories: []}), do: ""

  defp category_tags(%Show{primary_category: primary, secondary_categories: secondary}) do
    [primary | List.wrap(secondary)]
    |> Enum.reject(&is_nil/1)
    |> Enum.map_join("\n    ", &~s(<itunes:category text="#{xml_escape(&1)}"/>))
  end

  defp copyright_tag(%Show{copyright: nil}), do: ""
  defp copyright_tag(%Show{copyright: c}), do: "<copyright>#{xml_escape(c)}</copyright>"

  defp pub_date_tag(nil), do: ""
  defp pub_date_tag(%DateTime{} = dt), do: "<pubDate>#{rfc822(dt)}</pubDate>"

  defp episode_number_tag(%Episode{episode_number: nil}), do: ""

  defp episode_number_tag(%Episode{episode_number: n}),
    do: "<itunes:episode>#{n}</itunes:episode>"

  defp season_tag(%Episode{season_number: nil}), do: ""
  defp season_tag(%Episode{season_number: n}), do: "<itunes:season>#{n}</itunes:season>"

  defp enclosure_length(%Episode{remote_audio_byte_size: size})
       when is_integer(size) and size > 0,
       do: size

  defp enclosure_length(%Episode{mp3_byte_size: size}) when is_integer(size) and size > 0,
    do: size

  defp enclosure_length(_), do: 0

  defp enclosure_type(%Episode{remote_audio_content_type: ct}) when is_binary(ct), do: ct
  defp enclosure_type(_), do: "audio/mpeg"

  defp format_duration(nil), do: "00:00:00"

  defp format_duration(seconds) when is_integer(seconds) and seconds >= 0 do
    h = div(seconds, 3600)
    m = div(rem(seconds, 3600), 60)
    s = rem(seconds, 60)
    :io_lib.format("~2..0B:~2..0B:~2..0B", [h, m, s]) |> IO.iodata_to_binary()
  end

  defp xml_escape(nil), do: ""

  defp xml_escape(value) when is_binary(value) do
    value
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&apos;")
  end

  defp xml_escape(value), do: value |> to_string() |> xml_escape()

  defp day_name(1), do: "Mon"
  defp day_name(2), do: "Tue"
  defp day_name(3), do: "Wed"
  defp day_name(4), do: "Thu"
  defp day_name(5), do: "Fri"
  defp day_name(6), do: "Sat"
  defp day_name(7), do: "Sun"

  defp month_name(1), do: "Jan"
  defp month_name(2), do: "Feb"
  defp month_name(3), do: "Mar"
  defp month_name(4), do: "Apr"
  defp month_name(5), do: "May"
  defp month_name(6), do: "Jun"
  defp month_name(7), do: "Jul"
  defp month_name(8), do: "Aug"
  defp month_name(9), do: "Sep"
  defp month_name(10), do: "Oct"
  defp month_name(11), do: "Nov"
  defp month_name(12), do: "Dec"
end
