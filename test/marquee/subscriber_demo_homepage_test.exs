defmodule Marquee.SubscriberDemoHomepageTest do
  use Marquee.DataCase, async: false

  alias Marquee.Accounts.Organization
  alias Marquee.Catalog.HeroSlide
  alias Marquee.Catalog.Row
  alias Marquee.SubscriberDemo
  alias Marquee.SubscriberDemoFixtures

  setup do
    previous = Application.fetch_env(:marquee, :subscriber_demo_catalog)

    Application.put_env(
      :marquee,
      :subscriber_demo_catalog,
      SubscriberDemoFixtures.catalog_manifest()
    )

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:marquee, :subscriber_demo_catalog, value)
        :error -> Application.delete_env(:marquee, :subscriber_demo_catalog)
      end
    end)

    %{org: insert(:organization, slug: "the-workshop", features: %{"subscriber_demo" => true})}
  end

  test "fresh catalog has three distinct accurate hero slides and no explanatory text row", %{
    org: org
  } do
    {:ok, catalog} = SubscriberDemo.seed_catalog(org)
    slides = hero_slides(org)
    assert length(slides) >= 3
    assert length(Enum.uniq_by(slides, & &1.video_id)) == length(slides)
    assert Enum.map(slides, & &1.position) == Enum.to_list(0..(length(slides) - 1))
    videos = Map.new(catalog.videos, &{&1.id, &1})
    assert hd(slides).headline == catalog.series.title

    for slide <- slides do
      video = Map.fetch!(videos, slide.video_id)
      assert slide.description == video.description
      assert slide.background_image_url == video.landscape_thumbnail_url
      if slide.position > 0, do: assert(slide.headline == video.title)
    end

    refute Repo.exists?(
             from r in Row,
               where: r.organization_id == ^org.id and r.title == "Your subscriber demo"
           )

    hd(slides)
    |> Ecto.Changeset.change(
      background_image_url: "https://example.com/stale.jpg",
      title_logo_url: "https://example.com/old-title.svg",
      channel_logo_url: "https://example.com/old-channel.svg",
      show_primary_cta: false,
      show_secondary_cta: false,
      show_headline: false,
      show_description: false
    )
    |> Repo.update!()

    {:ok, _} = SubscriberDemo.seed_catalog(Repo.get!(Organization, org.id))

    assert Enum.map(hero_slides(org), &{&1.id, &1.video_id, &1.position}) ==
             Enum.map(slides, &{&1.id, &1.video_id, &1.position})

    for slide <- hero_slides(org) do
      assert slide.background_image_url ==
               Map.fetch!(videos, slide.video_id).landscape_thumbnail_url

      assert is_nil(slide.title_logo_url)
      assert is_nil(slide.channel_logo_url)
      assert slide.show_primary_cta and slide.show_secondary_cta
      assert slide.show_headline and slide.show_description
    end
  end

  test "only the exact active managed legacy welcome row is retired and excluded from configuration",
       %{org: org} do
    managed =
      insert(:row,
        organization: org,
        title: "Your subscriber demo",
        source_type: :welcome_text,
        visible: true
      )

    same_title_operator =
      insert(:row,
        organization: org,
        title: "Your subscriber demo",
        source_type: :welcome_text,
        visible: true
      )

    other_text =
      insert(:row,
        organization: org,
        title: "Our workshop story",
        source_type: :welcome_text,
        visible: true
      )

    deleted_at = ~U[2025-01-01 00:00:00Z]

    deleted =
      insert(:row,
        organization: org,
        title: "Your subscriber demo",
        source_type: :welcome_text,
        deleted_at: deleted_at
      )

    other_org_row =
      insert(:row, title: "Your subscriber demo", source_type: :welcome_text, visible: true)

    org =
      org
      |> Ecto.Changeset.change(
        features:
          Map.put(org.features, "subscriber_demo_row_ids", [managed.id, deleted.id, other_text.id])
      )
      |> Repo.update!()

    {:ok, _} = SubscriberDemo.seed_catalog(org)
    retired = Repo.get!(Row, managed.id)
    assert retired.deleted_at

    assert preserved_row_fields(Repo.get!(Row, same_title_operator.id)) ==
             preserved_row_fields(same_title_operator)

    assert preserved_row_fields(Repo.get!(Row, other_text.id)) == preserved_row_fields(other_text)
    assert Repo.get!(Row, deleted.id).deleted_at == deleted_at

    assert preserved_row_fields(Repo.get!(Row, other_org_row.id)) ==
             preserved_row_fields(other_org_row)

    refreshed = Repo.get!(Organization, org.id)
    refute managed.id in refreshed.features["subscriber_demo_row_ids"]
    refute deleted.id in refreshed.features["subscriber_demo_row_ids"]
    {:ok, _} = SubscriberDemo.seed_catalog(refreshed)
    assert Repo.get!(Row, managed.id).deleted_at == retired.deleted_at
  end

  defp hero_slides(org) do
    Repo.all(
      from s in HeroSlide,
        where: s.organization_id == ^org.id and is_nil(s.deleted_at),
        order_by: s.position
    )
  end

  defp preserved_row_fields(row),
    do: Map.take(row, [:title, :source_type, :visible, :deleted_at, :filter_config, :updated_at])
end
