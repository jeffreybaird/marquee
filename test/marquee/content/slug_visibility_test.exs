defmodule Marquee.Content.SlugVisibilityTest do
  @moduledoc """
  Viewer-facing slug lookups must respect the operator's visibility toggle.
  A hidden collection or series is not reachable by slug (D1, D2).
  """
  use Marquee.DataCase, async: true

  alias Marquee.Content

  setup do
    %{org: insert(:organization)}
  end

  describe "get_collection_by_slug/2" do
    test "returns a visible collection", %{org: org} do
      collection = insert(:collection, organization: org, slug: "shown", visible: true)

      assert {:ok, found} = Content.get_collection_by_slug(org, "shown")
      assert found.id == collection.id
    end

    test "returns not_found for a hidden collection", %{org: org} do
      insert(:collection, organization: org, slug: "hidden-collection", visible: false)

      assert {:error, :not_found} = Content.get_collection_by_slug(org, "hidden-collection")
    end
  end

  describe "get_series_by_slug/2" do
    test "returns a visible series", %{org: org} do
      series = insert(:series, organization: org, slug: "shown-series", visible: true)

      assert {:ok, found} = Content.get_series_by_slug(org, "shown-series")
      assert found.id == series.id
    end

    test "returns not_found for a hidden series", %{org: org} do
      insert(:series, organization: org, slug: "hidden-series", visible: false)

      assert {:error, :not_found} = Content.get_series_by_slug(org, "hidden-series")
    end
  end
end
