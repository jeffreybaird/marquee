defmodule Bobine.EngagementFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Bobine.Engagement` context.
  """

  import Bobine.Factory

  @doc """
  Generate a watchlist_item.
  """
  def watchlist_item_fixture(attrs \\ %{}) do
    org = insert(:organization)
    user = insert(:user)
    video = insert(:video, organization: org)

    {:ok, watchlist_item} =
      attrs
      |> Enum.into(%{
        auto_remove_on_watch: true,
        position: 42,
        organization_id: org.id,
        user_id: user.id,
        video_id: video.id
      })
      |> Bobine.Engagement.create_watchlist_item()

    watchlist_item
  end
end
