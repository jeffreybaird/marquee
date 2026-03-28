defmodule Bobine.EngagementFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Bobine.Engagement` context.
  """

  @doc """
  Generate a watchlist_item.
  """
  def watchlist_item_fixture(attrs \\ %{}) do
    {:ok, watchlist_item} =
      attrs
      |> Enum.into(%{
        auto_remove_on_watch: true,
        position: 42
      })
      |> Bobine.Engagement.create_watchlist_item()

    watchlist_item
  end
end
