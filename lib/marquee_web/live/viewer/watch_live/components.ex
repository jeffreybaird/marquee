defmodule MarqueeWeb.Viewer.WatchLive.Components do
  @moduledoc """
  Template helper functions used by the WatchLive colocated template.

  These are pure functions with no database or external service dependencies.
  """

  @doc """
  Formats a duration in seconds into a human-readable string.

  ## Examples

      iex> MarqueeWeb.Viewer.WatchLive.Components.format_duration(nil)
      ""

      iex> MarqueeWeb.Viewer.WatchLive.Components.format_duration(65)
      "1:05"

      iex> MarqueeWeb.Viewer.WatchLive.Components.format_duration(3661)
      "1h 1m"

      iex> MarqueeWeb.Viewer.WatchLive.Components.format_duration("not a number")
      ""
  """
  def format_duration(nil), do: ""

  def format_duration(seconds) when is_number(seconds) do
    minutes = div(trunc(seconds), 60)
    secs = rem(trunc(seconds), 60)

    if minutes >= 60 do
      hours = div(minutes, 60)
      mins = rem(minutes, 60)
      "#{hours}h #{mins}m"
    else
      "#{minutes}:#{String.pad_leading(Integer.to_string(secs), 2, "0")}"
    end
  end

  def format_duration(_), do: ""

  @doc """
  Trims a list of items so that it contains only complete rows of `cols` columns.

  ## Examples

      iex> MarqueeWeb.Viewer.WatchLive.Components.fill_rows([1, 2, 3, 4, 5], 3)
      [1, 2, 3]

      iex> MarqueeWeb.Viewer.WatchLive.Components.fill_rows([1, 2, 3], 3)
      [1, 2, 3]

      iex> MarqueeWeb.Viewer.WatchLive.Components.fill_rows([1, 2], 3)
      []
  """
  def fill_rows(items, cols) do
    count = length(items)
    full_row_count = div(count, cols) * cols
    Enum.take(items, full_row_count)
  end
end
