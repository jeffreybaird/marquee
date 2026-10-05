defmodule MarqueeWeb.E2E.SubscriberDemoColdEntryTest do
  use MarqueeWeb.WallabyCase

  import Ecto.Query

  alias Marquee.{Engagement, Repo, SubscriberDemo}
  alias Marquee.Viewers.Viewer

  @moduletag :e2e

  setup do
    changes = [
      subscriber_demo_catalog: Marquee.SubscriberDemoFixtures.catalog_manifest(),
      org_resolution: :query_param,
      tenant_domain_provisioning: [enabled: false]
    ]

    original = Map.new(changes, fn {key, _} -> {key, Application.fetch_env(:marquee, key)} end)
    for {key, value} <- changes, do: Application.put_env(:marquee, key, value)

    on_exit(fn ->
      for {key, value} <- original do
        case value do
          {:ok, value} -> Application.put_env(:marquee, key, value)
          :error -> Application.delete_env(:marquee, key)
        end
      end
    end)

    org = insert(:organization, features: %{"subscriber_demo" => true})
    {:ok, catalog} = SubscriberDemo.seed_catalog(org)
    %{org: org, catalog: catalog}
  end

  test "cold browser enters catalog directly and its signed cookie survives live navigation and reload",
       %{session: session, org: org, catalog: catalog} do
    session =
      session
      |> visit("/?org=#{org.slug}")
      |> assert_has(css("[data-test=subscriber-demo-banner]"))
      |> assert_has(css("[data-test=hero-primary-cta-0]"))

    [viewer] = Repo.all(from(v in Viewer, where: v.organization_id == ^org.id))
    assert SubscriberDemo.demo_viewer?(viewer)
    video = hd(catalog.videos)
    assert {:ok, saved} = Engagement.add_to_watchlist(org, viewer, video)

    session =
      session
      |> click(css("[data-test=nav-my-stuff]"))
      |> assert_has(css("[data-test=sv-watchlist-remove-#{saved.video_id}]"))
      |> click(css("[data-test=sv-watchlist-remove-#{saved.video_id}]"))
      |> assert_has(css("[data-test=sv-watchlist-remove-#{saved.video_id}]", count: 0))
      |> visit("/?org=#{org.slug}")
      |> assert_has(css("[data-test=subscriber-demo-banner]"))

    assert_has(session, css("[data-test=hero-primary-cta-0]"))
    assert [persisted] = Repo.all(from(v in Viewer, where: v.organization_id == ^org.id))
    assert persisted.id == viewer.id
    refute Engagement.in_watchlist?(org, viewer, video)
  end
end
