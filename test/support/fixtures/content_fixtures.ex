defmodule Marquee.ContentFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Marquee.Content` context.
  """

  import Marquee.Factory

  @doc """
  Generate a video.
  """
  def video_fixture(attrs \\ %{}) do
    org = insert(:organization)

    {:ok, video} =
      attrs
      |> Enum.into(%{
        description: "some description",
        duration: 120.5,
        max_resolution: "some max_resolution",
        mux_asset_id: "some mux_asset_id",
        mux_playback_id: "some mux_playback_id",
        mux_status: "some mux_status",
        mux_upload_id: "some mux_upload_id",
        published: true,
        slug: "some slug",
        title: "some title",
        organization_id: org.id
      })
      |> Marquee.Content.create_video()

    video
  end

  @doc """
  Generate a collection for a given scope.
  """
  def collection_fixture(scope, attrs \\ %{}) do
    attrs =
      attrs
      |> Enum.into(%{
        description: "some description",
        position: 42,
        title: "some title"
      })

    {:ok, collection} = Marquee.Content.create_collection(scope, attrs)
    collection
  end
end
