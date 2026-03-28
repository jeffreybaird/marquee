defmodule Bobine.ContentFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Bobine.Content` context.
  """

  @doc """
  Generate a video.
  """
  def video_fixture(attrs \\ %{}) do
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
        title: "some title"
      })
      |> Bobine.Content.create_video()

    video
  end

  @doc """
  Generate a collection.
  """
  def collection_fixture(attrs \\ %{}) do
    {:ok, collection} =
      attrs
      |> Enum.into(%{
        description: "some description",
        position: 42,
        slug: "some slug",
        title: "some title",
        type: :series
      })
      |> Bobine.Content.create_collection()

    collection
  end
end
