defmodule Marquee.SubscriberDemoSeederTest do
  use Marquee.DataCase, async: false
  alias Marquee.{Catalog, DemoSeeder, SubscriberDemo}

  setup do
    previous = Application.fetch_env(:marquee, :subscriber_demo_catalog)

    Application.put_env(
      :marquee,
      :subscriber_demo_catalog,
      Marquee.SubscriberDemoFixtures.catalog_manifest()
    )

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:marquee, :subscriber_demo_catalog, value)
        :error -> Application.delete_env(:marquee, :subscriber_demo_catalog)
      end
    end)

    :ok
  end

  test "fresh Workshop provisioning leaves exactly one usable hero row" do
    assert {:ok, catalog} = DemoSeeder.seed_subscriber_demo()
    assert {:ok, hero} = Catalog.get_hero_row(catalog.organization)
    assert hero.visible
    assert Catalog.resolve_hero_slides_cached(catalog.organization).slides != []
    assert {:ok, repeated} = DemoSeeder.seed_subscriber_demo()
    assert repeated.organization.id == catalog.organization.id
    assert {:ok, same_hero} = Catalog.get_hero_row(catalog.organization)
    assert same_hero.id == hero.id
  end

  test "existing Workshop hero is reused during subscriber catalog seeding" do
    org = insert(:organization, slug: "the-workshop", features: %{"subscriber_demo" => true})
    hero = insert(:hero_row, organization: org)
    assert {:ok, _} = SubscriberDemo.seed_catalog(org)
    assert {:ok, same_hero} = Catalog.get_hero_row(org)
    assert same_hero.id == hero.id
    assert Catalog.resolve_hero_slides_cached(org).slides != []
  end
end
