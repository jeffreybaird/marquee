defmodule Marquee.AdminDemoFixtures do
  @moduledoc "Deterministic travel metadata for isolated admin-demo contracts; no external media calls."

  @doc "Returns attributed fixture clips without loading the production Wanderlust manifest."
  def catalog_manifest do
    %{
      version: 1,
      clips:
        for n <- 1..4 do
          %{
            slug: "travel-fixture-#{n}",
            title: "Travel fixture #{n}",
            description: "Deterministic travel scene #{n} for admin demo tests.",
            duration: 120.0 + n,
            mux_playback_id: "fixture-travel-playback-#{n}",
            mux_asset_id: "fixture-protected-travel-asset-#{n}",
            source_url: "https://media.example.test/clip/#{n}",
            creator_name: "Fixture creator #{n}",
            creator_url: "https://media.example.test/creator/#{n}",
            license_url: "https://media.example.test/license",
            collection: if(n <= 2, do: "Coastal escapes", else: "Mountain paths"),
            initial: n <= 3
          }
        end
    }
  end

  @doc "Returns a separate sixty-clip fixture with twelve initial and three library clips per collection."
  def expanded_catalog_manifest do
    template = hd(catalog_manifest().clips)
    collections = ["City journeys", "Coastal escapes", "Food & culture", "Wild horizons"]

    %{
      version: "fixture-travel-v2",
      clips:
        for {collection, group} <- Enum.with_index(collections), n <- 1..15 do
          id = group * 15 + n

          %{
            template
            | slug: "expanded-travel-#{id}",
              title: "Expanded travel #{id}",
              mux_playback_id: "expanded-playback-#{id}",
              mux_asset_id: "expanded-protected-#{id}",
              source_url: "https://media.example.test/expanded/#{id}",
              collection: collection,
              initial: n <= 12
          }
        end
    }
  end
end
