defmodule Bobine.Podcasts.RemoteFeedParser do
  @moduledoc """
  Parses an RSS feed body into a normalized map structure suitable for
  upserting into our `podcast_episodes` table.

  Returns:

      {:ok, %{
        show: %{
          title: String.t() | nil,
          description: String.t() | nil,
          author: String.t() | nil,
          language: String.t() | nil,
          cover_artwork_url: String.t() | nil,
          explicit: boolean() | nil
        },
        episodes: [
          %{
            guid: String.t(),
            title: String.t(),
            description: String.t() | nil,
            episode_number: integer() | nil,
            season_number: integer() | nil,
            episode_type: String.t(),
            publish_date: DateTime.t() | nil,
            duration_seconds: integer() | nil,
            remote_audio_url: String.t() | nil,
            remote_audio_byte_size: integer() | nil,
            remote_audio_content_type: String.t() | nil
          }
        ]
      }}

  or `{:error, :invalid_feed}` when the body does not parse as RSS.
  """

  import SweetXml

  @doc """
  Parses an RSS feed body. Returns `{:ok, map}` or `{:error, reason}`.

  Exempt from doctest — exercised via integration tests.
  """
  def parse(body) when is_binary(body) do
    try do
      doc = SweetXml.parse(body, quiet: true)

      if doc |> xpath(~x"//rss/channel"o) do
        {:ok, %{show: parse_show(doc), episodes: parse_episodes(doc)}}
      else
        {:error, :invalid_feed}
      end
    rescue
      _ -> {:error, :invalid_feed}
    catch
      :exit, _ -> {:error, :invalid_feed}
      _, _ -> {:error, :invalid_feed}
    end
  end

  def parse(_), do: {:error, :invalid_feed}

  defp parse_show(doc) do
    %{
      title: doc |> xpath(~x"//rss/channel/title/text()"so) |> blank_to_nil(),
      description: doc |> xpath(~x"//rss/channel/description/text()"so) |> blank_to_nil(),
      author: doc |> xpath(~x"//rss/channel/itunes:author/text()"so) |> blank_to_nil(),
      language: doc |> xpath(~x"//rss/channel/language/text()"so) |> blank_to_nil(),
      cover_artwork_url: doc |> xpath(~x"//rss/channel/itunes:image/@href"so) |> blank_to_nil(),
      explicit: parse_explicit(doc |> xpath(~x"//rss/channel/itunes:explicit/text()"so))
    }
  end

  defp parse_episodes(doc) do
    doc
    |> xpath(~x"//rss/channel/item"l)
    |> Enum.map(&parse_item/1)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_item(item) do
    guid = item |> xpath(~x"./guid/text()"so) |> blank_to_nil()
    title = item |> xpath(~x"./title/text()"so) |> blank_to_nil()

    if guid && title do
      enclosure_url = item |> xpath(~x"./enclosure/@url"so) |> blank_to_nil()
      enclosure_length = item |> xpath(~x"./enclosure/@length"so) |> blank_to_nil()
      enclosure_type = item |> xpath(~x"./enclosure/@type"so) |> blank_to_nil()

      %{
        guid: guid,
        title: title,
        description: item |> xpath(~x"./description/text()"so) |> blank_to_nil(),
        episode_number: item |> xpath(~x"./itunes:episode/text()"so) |> parse_int(),
        season_number: item |> xpath(~x"./itunes:season/text()"so) |> parse_int(),
        episode_type: item |> xpath(~x"./itunes:episodeType/text()"so) |> normalize_type(),
        publish_date: item |> xpath(~x"./pubDate/text()"so) |> parse_pub_date(),
        duration_seconds: item |> xpath(~x"./itunes:duration/text()"so) |> parse_duration(),
        remote_audio_url: enclosure_url,
        remote_audio_byte_size: parse_int(enclosure_length),
        remote_audio_content_type: enclosure_type
      }
    else
      nil
    end
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(value) when is_binary(value), do: value |> String.trim() |> nil_if_empty()
  defp blank_to_nil(value), do: value

  defp nil_if_empty(""), do: nil
  defp nil_if_empty(value), do: value

  defp parse_explicit("yes"), do: true
  defp parse_explicit("true"), do: true
  defp parse_explicit("no"), do: false
  defp parse_explicit("false"), do: false
  defp parse_explicit("clean"), do: false
  defp parse_explicit(_), do: nil

  defp normalize_type(nil), do: "full"
  defp normalize_type(""), do: "full"

  defp normalize_type(type) do
    case String.downcase(type) do
      "trailer" -> "trailer"
      "bonus" -> "bonus"
      _ -> "full"
    end
  end

  defp parse_int(nil), do: nil
  defp parse_int(""), do: nil

  defp parse_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp parse_int(_), do: nil

  # iTunes <itunes:duration> is either an integer-seconds string or HH:MM:SS.
  defp parse_duration(nil), do: nil
  defp parse_duration(""), do: nil

  defp parse_duration(value) when is_binary(value) do
    parts = String.split(value, ":")

    case length(parts) do
      1 ->
        parse_int(value)

      2 ->
        with [m, s] <- parts,
             {mm, _} <- Integer.parse(m),
             {ss, _} <- Integer.parse(s) do
          mm * 60 + ss
        else
          _ -> nil
        end

      3 ->
        with [h, m, s] <- parts,
             {hh, _} <- Integer.parse(h),
             {mm, _} <- Integer.parse(m),
             {ss, _} <- Integer.parse(s) do
          hh * 3600 + mm * 60 + ss
        else
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp parse_pub_date(nil), do: nil
  defp parse_pub_date(""), do: nil

  # RFC 822 / RFC 2822 — Mon, 02 Jan 2006 15:04:05 GMT
  defp parse_pub_date(value) when is_binary(value) do
    case __MODULE__.Rfc2822.parse(value) do
      {:ok, dt} -> DateTime.truncate(dt, :second)
      _ -> nil
    end
  end

  defmodule Rfc2822 do
    @moduledoc false

    @months %{
      "jan" => 1,
      "feb" => 2,
      "mar" => 3,
      "apr" => 4,
      "may" => 5,
      "jun" => 6,
      "jul" => 7,
      "aug" => 8,
      "sep" => 9,
      "oct" => 10,
      "nov" => 11,
      "dec" => 12
    }

    @doc """
    Parses an RFC 2822 / RFC 822 datetime such as
    `Mon, 02 Jan 2006 15:04:05 GMT` into `{:ok, %DateTime{}}` or `:error`.

    Returns the time in UTC. Recognized timezone offsets:

      * `GMT`, `UTC`, `Z` — UTC
      * `+HHMM` / `-HHMM` — numeric offset
      * Single-letter or three-letter zone abbreviations are treated as UTC
        because the RFC permits this when the offset is ambiguous.
    """
    def parse(string) do
      string
      |> String.replace(~r/\s+/, " ")
      |> String.trim()
      |> drop_weekday()
      |> String.split(" ")
      |> case do
        [day, month, year, time, zone] ->
          build(day, month, year, time, zone)

        [day, month, year, time] ->
          build(day, month, year, time, "UTC")

        _ ->
          :error
      end
    end

    defp drop_weekday(string) do
      case String.split(string, ", ", parts: 2) do
        [_weekday, rest] -> rest
        [single] -> single
      end
    end

    defp build(day, month, year, time, zone) do
      with {d, _} <- Integer.parse(day),
           m when not is_nil(m) <- Map.get(@months, String.downcase(month)),
           {y, _} <- Integer.parse(year),
           {h, mi, s} <- parse_time(time),
           {:ok, naive} <- NaiveDateTime.new(y, m, d, h, mi, s),
           offset_seconds <- parse_zone(zone),
           {:ok, dt} <- DateTime.from_naive(naive, "Etc/UTC") do
        {:ok, DateTime.add(dt, -offset_seconds, :second)}
      else
        _ -> :error
      end
    end

    defp parse_time(time) do
      case String.split(time, ":") do
        [h, m, s] ->
          with {hh, _} <- Integer.parse(h),
               {mm, _} <- Integer.parse(m),
               {ss, _} <- Integer.parse(s) do
            {hh, mm, ss}
          else
            _ -> :error
          end

        [h, m] ->
          with {hh, _} <- Integer.parse(h),
               {mm, _} <- Integer.parse(m) do
            {hh, mm, 0}
          else
            _ -> :error
          end

        _ ->
          :error
      end
    end

    defp parse_zone("GMT"), do: 0
    defp parse_zone("UTC"), do: 0
    defp parse_zone("Z"), do: 0

    defp parse_zone(<<sign, h1, h2, m1, m2>>) when sign in [?+, ?-] do
      with {hh, _} <- Integer.parse(<<h1, h2>>),
           {mm, _} <- Integer.parse(<<m1, m2>>) do
        offset = hh * 3600 + mm * 60
        if sign == ?+, do: offset, else: -offset
      else
        _ -> 0
      end
    end

    defp parse_zone(_), do: 0
  end
end
