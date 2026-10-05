defmodule MarqueeWeb.Viewer.SubscriberDemoLandingTest do
  use MarqueeWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import Ecto.Query
  alias Marquee.{Accounts, Repo, SubscriberDemo}
  alias Marquee.LandingPage.LandingSection
  alias Marquee.Viewers.{Viewer, ViewerToken}

  setup do
    original = Application.fetch_env(:marquee, :subscriber_demo_catalog)

    Application.put_env(
      :marquee,
      :subscriber_demo_catalog,
      Marquee.SubscriberDemoFixtures.catalog_manifest()
    )

    on_exit(fn ->
      case original do
        {:ok, value} -> Application.put_env(:marquee, :subscriber_demo_catalog, value)
        :error -> Application.delete_env(:marquee, :subscriber_demo_catalog)
      end
    end)

    org =
      insert(:organization,
        name: "Craft Atlas",
        preset_name: "learning_platform",
        features: %{"subscriber_demo" => true}
      )

    {:ok, catalog} = SubscriberDemo.seed_catalog(org)
    {:ok, org} = Accounts.get_organization(org.id)
    %{org: org, catalog: catalog}
  end

  test "empty demo landing renders real catalog sections and POST entry without persistence", %{
    org: org,
    catalog: catalog
  } do
    insert(:theme, organization: org, background: "#19352a")
    assert Repo.aggregate(LandingSection, :count) == 0
    {:ok, view, html} = live(host_conn(org), "/")
    assert has_element?(view, "[data-test=subscriber-demo-landing]")

    assert has_element?(
             view,
             "[data-test=hero-image-section] img[src='#{hd(catalog.videos).landscape_thumbnail_url}']"
           )

    assert has_element?(view, "[data-test=subscriber-demo-entry][data-method=post]", "Begin demo")

    for action <- ["favorite", "watchlist", "queue"] do
      refute has_element?(view, "[data-test^=sv-card-#{action}-]")
    end

    assert Repo.aggregate(Viewer, :count) == 0
    assert Repo.aggregate(ViewerToken, :count) == 0
    viewer = insert(:subscribed_viewer, organization: org)

    {:ok, catalog_view, _} =
      live(conn_for_viewer(viewer) |> Map.put(:host, "#{org.slug}.localhost"), "/browse")

    assert has_element?(catalog_view, "[data-test^=sv-card-favorite-]")
    assert has_element?(catalog_view, "[data-test^=sv-card-watchlist-]")
    assert has_element?(catalog_view, "[data-test^=sv-card-queue-]")
    assert html =~ "Craft Atlas"
    assert has_element?(view, "[data-test=sv-root][style*=\"#19352a\"]")
    refute html =~ "The Workshop ·"
    assert Repo.aggregate(LandingSection, :count) == 0
    assert Repo.aggregate(Viewer, :count) == 1
    assert Repo.aggregate(ViewerToken, :count) == 1
  end

  test "configured ordering hidden sections and explicit image override demo defaults", %{
    org: org
  } do
    insert(:landing_section,
      organization: org,
      section_type: :header_text,
      position: 2,
      config: %{"headline" => "Second configured section"}
    )

    insert(:landing_section,
      organization: org,
      section_type: :hero_image,
      position: 0,
      config: %{
        "headline" => "First configured hero",
        "image_url" => "https://images.example/custom.jpg",
        "cta_text" => "Explore our craft journal",
        "cta_link" => "https://example.com/craft-journal"
      }
    )

    insert(:landing_section,
      organization: org,
      section_type: :marketing_copy,
      position: 1,
      visible: false,
      config: %{"headline" => "Hidden operator draft"}
    )

    before =
      Repo.all(
        from s in LandingSection, where: s.organization_id == ^org.id, order_by: s.position
      )

    {:ok, view, html} = live(host_conn(org), "/")

    assert has_element?(
             view,
             "[data-test=hero-image-section] img[src='https://images.example/custom.jpg']"
           )

    assert has_element?(
             view,
             "[data-test=hero-image-section] a[href='https://example.com/craft-journal']",
             "Explore our craft journal"
           )

    assert has_element?(view, "[data-test=subscriber-demo-entry][data-method=post]", "Begin demo")

    assert :binary.match(html, "First configured hero") <
             :binary.match(html, "Second configured section")

    refute html =~ "Hidden operator draft"
    assert {:ok, :unchanged} = SubscriberDemo.seed_landing_page(org)

    assert Repo.all(
             from s in LandingSection, where: s.organization_id == ^org.id, order_by: s.position
           ) == before
  end

  test "missing hero image uses only approved same-tenant catalog media", %{
    org: org,
    catalog: catalog
  } do
    insert(:video,
      organization: org,
      published: true,
      landscape_thumbnail_url: "https://images.example/unapproved.jpg"
    )

    foreign =
      insert(:video,
        published: true,
        landscape_thumbnail_url: "https://images.example/foreign.jpg"
      )

    section =
      insert(:landing_section,
        organization: org,
        section_type: :hero_image,
        config: %{"headline" => "Catalog hero", "image_url" => ""}
      )

    {:ok, view, html} = live(host_conn(org), "/")

    assert has_element?(
             view,
             "[data-test=hero-image-section] img[src='#{hd(catalog.videos).landscape_thumbnail_url}']"
           )

    refute html =~ "https://images.example/unapproved.jpg"
    refute html =~ foreign.landscape_thumbnail_url
    assert Repo.get!(LandingSection, section.id).config["image_url"] == ""
  end

  test "landing-only seed is idempotent scoped and respects hidden-only configuration", %{
    org: org
  } do
    assert {:ok, :seeded} = SubscriberDemo.seed_landing_page(org)

    sections =
      Repo.all(
        from s in LandingSection, where: s.organization_id == ^org.id, order_by: s.position
      )

    assert hd(sections).section_type == :hero_image
    assert Enum.count(sections, &(&1.section_type == :content_row)) == 2
    assert Enum.any?(sections, &(&1.section_type == :faq))
    assert {:ok, :unchanged} = SubscriberDemo.seed_landing_page(org)

    assert Repo.all(
             from s in LandingSection, where: s.organization_id == ^org.id, order_by: s.position
           ) == sections

    ordinary = insert(:organization)
    assert {:error, :forbidden} = SubscriberDemo.seed_landing_page(ordinary)
    hidden_org = insert(:organization, features: %{"subscriber_demo" => true})

    hidden =
      insert(:landing_section,
        organization: hidden_org,
        visible: false,
        section_type: :header_text,
        config: %{"headline" => "Private draft"}
      )

    assert {:ok, :unchanged} = SubscriberDemo.seed_landing_page(hidden_org)
    {:ok, view, html} = live(host_conn(hidden_org), "/")
    refute has_element?(view, "[data-test=hero-image-section]")
    refute html =~ "Private draft"

    [persisted] = Repo.all(from s in LandingSection, where: s.organization_id == ^hidden_org.id)
    fields = [:id, :organization_id, :visible, :section_type, :position, :config, :updated_at]
    assert Map.take(persisted, fields) == Map.take(hidden, fields)
  end

  defp host_conn(org),
    do: build_conn() |> Map.put(:host, "#{org.slug}.localhost") |> init_test_session(%{})
end
