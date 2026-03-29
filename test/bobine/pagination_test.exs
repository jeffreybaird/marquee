defmodule Bobine.PaginationTest do
  use Bobine.DataCase, async: true

  alias Bobine.Content

  describe "pagination" do
    setup do
      org = insert(:organization)
      %{org: org}
    end

    test "returns correct page of results", %{org: org} do
      for i <- 1..3, do: insert(:video, organization: org, title: "Video #{i}")

      %{results: results, page: 1, per_page: 2, total: 3, total_pages: 2} =
        Content.list_videos(org, per_page: 2, page: 1)

      assert length(results) == 2

      %{results: results2, page: 2, total_pages: 2} =
        Content.list_videos(org, per_page: 2, page: 2)

      assert length(results2) == 1
    end

    test "respects per_page option", %{org: org} do
      for i <- 1..5, do: insert(:video, organization: org, title: "Video #{i}")

      %{results: results, per_page: 3} = Content.list_videos(org, per_page: 3)
      assert length(results) == 3
    end

    test "clamps per_page to max 100", %{org: org} do
      insert(:video, organization: org)

      %{per_page: 100} = Content.list_videos(org, per_page: 200)
    end

    test "returns correct total and total_pages", %{org: org} do
      for i <- 1..7, do: insert(:video, organization: org, title: "Video #{i}")

      %{total: 7, total_pages: 3} = Content.list_videos(org, per_page: 3)
    end

    test "page 1 is the default", %{org: org} do
      insert(:video, organization: org)

      %{page: 1} = Content.list_videos(org)
    end

    test "empty result set returns total: 0, total_pages: 1", %{org: org} do
      %{results: [], total: 0, total_pages: 1} = Content.list_videos(org)
    end
  end
end
