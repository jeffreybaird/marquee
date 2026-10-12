defmodule Marquee.Content.AspectRatio do
  @moduledoc """
  Pure helpers for the `W:H` aspect ratio Mux reports for an asset
  (`"9:16"`, `"16:9"`, `"1:1"`, ...).

  The ratio is stored on `videos.aspect_ratio` and drives how the Shorts
  feed fits a clip: the media box takes the clip's own ratio and the
  video is letterboxed or pillarboxed (`object-fit: contain`), never
  cropped. Unknown ratios fall back to the 9:16 stage.
  """

  @ratio_pattern ~r/\A(\d+):(\d+)\z/
  @fallback_css "9 / 16"

  @doc """
  Parses a `W:H` ratio into a tuple of positive integers.

      iex> Marquee.Content.AspectRatio.parse("9:16")
      {:ok, {9, 16}}

      iex> Marquee.Content.AspectRatio.parse("16:9")
      {:ok, {16, 9}}

      iex> Marquee.Content.AspectRatio.parse("0:16")
      :error

      iex> Marquee.Content.AspectRatio.parse(nil)
      :error
  """
  def parse(value) when is_binary(value) do
    with [_, width, height] <- Regex.run(@ratio_pattern, value),
         {w, h} when w > 0 and h > 0 <- {String.to_integer(width), String.to_integer(height)} do
      {:ok, {w, h}}
    else
      _ -> :error
    end
  end

  def parse(_value), do: :error

  @doc """
  Returns the canonical `W:H` string for a valid ratio, or `nil`.

      iex> Marquee.Content.AspectRatio.normalize("9:16")
      "9:16"

      iex> Marquee.Content.AspectRatio.normalize("garbage")
      nil
  """
  def normalize(value) do
    case parse(value) do
      {:ok, {w, h}} -> "#{w}:#{h}"
      :error -> nil
    end
  end

  @doc """
  Classifies a ratio as `:portrait`, `:landscape`, `:square` or `:unknown`.

      iex> Marquee.Content.AspectRatio.orientation("9:16")
      :portrait

      iex> Marquee.Content.AspectRatio.orientation("16:9")
      :landscape

      iex> Marquee.Content.AspectRatio.orientation("1:1")
      :square

      iex> Marquee.Content.AspectRatio.orientation(nil)
      :unknown
  """
  def orientation(value) do
    case parse(value) do
      {:ok, {w, h}} when w < h -> :portrait
      {:ok, {w, h}} when w > h -> :landscape
      {:ok, _} -> :square
      :error -> :unknown
    end
  end

  @doc """
  Renders a CSS `aspect-ratio` value, falling back to the 9:16 stage.

      iex> Marquee.Content.AspectRatio.css_ratio("16:9")
      "16 / 9"

      iex> Marquee.Content.AspectRatio.css_ratio("9:16")
      "9 / 16"

      iex> Marquee.Content.AspectRatio.css_ratio(nil)
      "9 / 16"
  """
  def css_ratio(value) do
    case parse(value) do
      {:ok, {w, h}} -> "#{w} / #{h}"
      :error -> @fallback_css
    end
  end
end
