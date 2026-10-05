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
end
