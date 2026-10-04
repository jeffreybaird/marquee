defmodule Marquee.SubscriberDemoManifestTest do
  use Marquee.DataCase, async: false
  alias Marquee.{SubscriberDemo, SubscriberDemoFixtures}

  setup do
    previous =
      for key <- [:subscriber_demo_catalog, :subscriber_demo_manifest_path],
          do: {key, Application.fetch_env(:marquee, key)}

    path =
      Path.join(System.tmp_dir!(), "workshop-manifest-#{System.unique_integer([:positive])}.json")

    Application.delete_env(:marquee, :subscriber_demo_catalog)
    Application.put_env(:marquee, :subscriber_demo_manifest_path, path)

    on_exit(fn ->
      File.rm(path)

      for {key, prior} <- previous do
        case prior do
          {:ok, value} -> Application.put_env(:marquee, key, value)
          :error -> Application.delete_env(:marquee, key)
        end
      end
    end)

    %{
      org: insert(:organization, slug: "the-workshop", features: %{"subscriber_demo" => true}),
      path: path
    }
  end

  test "reviewed JSON manifest is loaded when no in-memory override exists", %{
    org: org,
    path: path
  } do
    File.write!(path, Jason.encode!(SubscriberDemoFixtures.catalog_manifest()))
    assert {:ok, catalog} = SubscriberDemo.seed_catalog(org)

    assert Enum.map(catalog.videos, & &1.mux_playback_id) ==
             Enum.map(SubscriberDemoFixtures.catalog_manifest(), & &1.mux_playback_id)

    assert length(catalog.videos) == 3
  end

  test "missing or malformed manifest fails without seeding videos", %{org: org, path: path} do
    assert {:error, :media_not_configured} = SubscriberDemo.seed_catalog(org)
    File.write!(path, "{invalid JSON")
    assert {:error, :media_not_configured} = SubscriberDemo.seed_catalog(org)
    refute Repo.exists?(from v in Marquee.Content.Video, where: v.organization_id == ^org.id)
  end

  test "explicit in-memory manifest takes priority over the file", %{org: org} do
    Application.put_env(
      :marquee,
      :subscriber_demo_catalog,
      SubscriberDemoFixtures.catalog_manifest()
    )

    assert {:ok, catalog} = SubscriberDemo.seed_catalog(org)
    assert length(catalog.videos) == 3
  end
end
