defmodule Marquee.SubscriberDemoFixtures do
  @moduledoc "Deterministic media metadata for catalog tests; browser playback uses vetted real media."

  @doc "Returns a three-episode manifest without calling external media services."
  def catalog_manifest do
    for n <- 1..3 do
      %{
        slug: "workshop-episode-#{n}",
        title: "Workshop study #{n}",
        description: "A close view of craft materials and work in progress, study #{n}.",
        mux_asset_id: "fixture-workshop-asset-#{n}",
        mux_playback_id: "fixture-workshop-playback-#{n}",
        duration: 180.0,
        source_url: "https://example.com/workshop-study-#{n}"
      }
    end
  end
end
