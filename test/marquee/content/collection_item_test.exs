defmodule Marquee.Content.CollectionItemTest do
  use Marquee.DataCase

  alias Marquee.Content.CollectionItem

  describe "changeset/2" do
    test "with item_type :video and video_id set succeeds" do
      video = insert(:video)

      changeset =
        CollectionItem.changeset(%CollectionItem{}, %{
          item_type: :video,
          video_id: video.id,
          position: 0,
          organization_id: video.organization_id,
          collection_id: Ecto.UUID.generate()
        })

      assert changeset.valid?
    end

    test "with item_type :season and season_id set succeeds" do
      season = insert(:season)

      changeset =
        CollectionItem.changeset(%CollectionItem{}, %{
          item_type: :season,
          season_id: season.id,
          position: 0,
          organization_id: season.organization_id,
          collection_id: Ecto.UUID.generate()
        })

      assert changeset.valid?
    end

    test "with item_type :series and series_id set succeeds" do
      series = insert(:series)

      changeset =
        CollectionItem.changeset(%CollectionItem{}, %{
          item_type: :series,
          series_id: series.id,
          position: 0,
          organization_id: series.organization_id,
          collection_id: Ecto.UUID.generate()
        })

      assert changeset.valid?
    end

    test "with item_type :video but video_id nil fails" do
      changeset =
        CollectionItem.changeset(%CollectionItem{}, %{
          item_type: :video,
          position: 0
        })

      refute changeset.valid?
      assert %{video_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "with item_type :video and season_id set fails" do
      video = insert(:video)
      season = insert(:season)

      changeset =
        CollectionItem.changeset(%CollectionItem{}, %{
          item_type: :video,
          video_id: video.id,
          season_id: season.id,
          position: 0
        })

      refute changeset.valid?
      assert %{season_id: _} = errors_on(changeset)
    end

    test "with item_type :season and video_id set fails" do
      season = insert(:season)
      video = insert(:video)

      changeset =
        CollectionItem.changeset(%CollectionItem{}, %{
          item_type: :season,
          season_id: season.id,
          video_id: video.id,
          position: 0
        })

      refute changeset.valid?
      assert %{video_id: _} = errors_on(changeset)
    end

    test "without item_type fails" do
      changeset =
        CollectionItem.changeset(%CollectionItem{}, %{
          position: 0,
          video_id: Ecto.UUID.generate()
        })

      refute changeset.valid?
      assert %{item_type: _} = errors_on(changeset)
    end

    test "position defaults to 0 when not provided" do
      video = insert(:video)

      changeset =
        CollectionItem.changeset(%CollectionItem{}, %{
          item_type: :video,
          video_id: video.id
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :position) == 0
    end
  end

  describe "referenced_entity/1" do
    test "returns video for video items" do
      video = %{id: "v1"}

      item = %CollectionItem{
        item_type: :video,
        video: video,
        season: nil,
        series: nil
      }

      assert CollectionItem.referenced_entity(item) == video
    end

    test "returns season for season items" do
      season = %{id: "s1"}

      item = %CollectionItem{
        item_type: :season,
        video: nil,
        season: season,
        series: nil
      }

      assert CollectionItem.referenced_entity(item) == season
    end

    test "returns series for series items" do
      series = %{id: "sr1"}

      item = %CollectionItem{
        item_type: :series,
        video: nil,
        season: nil,
        series: series
      }

      assert CollectionItem.referenced_entity(item) == series
    end
  end
end
