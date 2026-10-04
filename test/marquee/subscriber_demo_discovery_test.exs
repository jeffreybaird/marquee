defmodule Marquee.SubscriberDemoDiscoveryTest do
  use Marquee.DataCase, async: false
  use Oban.Testing, repo: Marquee.Repo

  alias Marquee.Admin
  alias Marquee.Workers.SubscriberDemoCleanup

  test "platform discovery selects the oldest active strictly enabled tenant and follows renames" do
    insert(:organization, slug: "the-workshop", features: %{})

    insert(:organization,
      features: %{"subscriber_demo" => "true"},
      inserted_at: ~U[2020-01-01 00:00:00Z]
    )

    insert(:organization,
      features: %{"subscriber_demo" => true},
      deleted_at: ~U[2021-01-01 00:00:00Z],
      inserted_at: ~U[2020-01-01 00:00:00Z]
    )

    first =
      insert(:organization,
        slug: "first-demo",
        features: %{"subscriber_demo" => true},
        inserted_at: ~U[2022-01-01 00:00:00Z]
      )

    second =
      insert(:organization,
        features: %{"subscriber_demo" => true},
        inserted_at: ~U[2023-01-01 00:00:00Z]
      )

    assert {:ok, %{id: id}} = Admin.get_subscriber_demo_organization()
    assert id == first.id
    first |> Ecto.Changeset.change(slug: "renamed-demo") |> Repo.update!()
    assert {:ok, %{id: ^id, slug: "renamed-demo"}} = Admin.get_subscriber_demo_organization()

    Repo.get!(Marquee.Accounts.Organization, first.id)
    |> Ecto.Changeset.change(features: %{})
    |> Repo.update!()

    assert {:ok, %{id: next_id}} = Admin.get_subscriber_demo_organization()
    assert next_id == second.id
  end

  test "no explicitly enabled tenant means no platform demo" do
    insert(:organization, slug: "the-workshop", features: %{})
    assert {:error, :not_found} = Admin.get_subscriber_demo_organization()
  end

  test "cleanup discovery is distinct, bounded, and includes disabled demo tenants" do
    orgs = for _ <- 1..3, do: insert(:organization, features: %{})

    for org <- orgs do
      insert(:viewer, organization: org, metadata: %{"subscriber_demo" => true})
      insert(:viewer, organization: org, metadata: %{"subscriber_demo" => true})
    end

    ordinary = insert(:organization, features: %{"subscriber_demo" => true})
    insert(:viewer, organization: ordinary)
    ids = Enum.sort(Enum.map(orgs, & &1.id))
    assert Admin.list_subscriber_demo_cleanup_organization_ids(per_page: 2) == Enum.take(ids, 2)

    assert Admin.list_subscriber_demo_cleanup_organization_ids(
             per_page: 2,
             after_id: Enum.at(ids, 1)
           ) == Enum.drop(ids, 2)

    assert Admin.list_subscriber_demo_cleanup_organization_ids(after_id: List.last(ids)) == []

    Oban.Testing.with_testing_mode(:manual, fn ->
      assert :ok = perform_job(SubscriberDemoCleanup, %{})

      for org <- orgs,
          do: assert_enqueued(worker: SubscriberDemoCleanup, args: %{organization_id: org.id})

      refute_enqueued(worker: SubscriberDemoCleanup, args: %{organization_id: ordinary.id})
    end)
  end

  test "an org-scoped cleanup removes only its expired demo after the feature is disabled" do
    org = insert(:organization, features: %{})
    other = insert(:organization, features: %{})

    metadata = %{
      "subscriber_demo" => true,
      "subscriber_demo_expires_at" => "2020-01-01T00:00:00Z"
    }

    expired = insert(:viewer, organization: org, metadata: metadata)
    untouched = insert(:viewer, organization: other, metadata: metadata)
    ordinary = insert(:viewer, organization: org)
    assert :ok = perform_job(SubscriberDemoCleanup, %{organization_id: org.id})
    assert is_nil(Repo.get(Marquee.Viewers.Viewer, expired.id))
    assert Repo.get(Marquee.Viewers.Viewer, untouched.id)
    assert Repo.get(Marquee.Viewers.Viewer, ordinary.id)
  end

  test "recovery dispatch continues after a full bounded page without skipping tenants" do
    ids =
      for _ <- 1..101 do
        org = insert(:organization)
        insert(:viewer, organization: org, metadata: %{"subscriber_demo" => true})
        org.id
      end
      |> Enum.sort()

    assert length(Admin.list_subscriber_demo_cleanup_organization_ids(per_page: 1000)) == 100

    Oban.Testing.with_testing_mode(:manual, fn ->
      assert :ok = perform_job(SubscriberDemoCleanup, %{})
      cursor = Enum.at(ids, 99)
      assert_enqueued(worker: SubscriberDemoCleanup, args: %{after_id: cursor})

      for id <- Enum.take(ids, 100),
          do: assert_enqueued(worker: SubscriberDemoCleanup, args: %{organization_id: id})

      refute_enqueued(worker: SubscriberDemoCleanup, args: %{organization_id: List.last(ids)})
      assert :ok = perform_job(SubscriberDemoCleanup, %{after_id: cursor})
      assert_enqueued(worker: SubscriberDemoCleanup, args: %{organization_id: List.last(ids)})
    end)
  end
end
