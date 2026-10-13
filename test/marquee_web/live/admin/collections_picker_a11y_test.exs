defmodule MarqueeWeb.Admin.CollectionsPickerA11yTest do
  @moduledoc """
  D5: season and series items in the collection item picker are clickable
  choices, so they must be real `<button>` elements (keyboard reachable),
  never `phx-click` on a `<div>`.
  """
  use MarqueeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Marquee.Accounts.Scope
  alias Marquee.Content

  defp setup_picker do
    org = insert(:organization)
    user = insert(:user)
    membership = insert(:membership, organization: org, user: user, role: :editor)
    membership = Marquee.Repo.preload(membership, [:user, :organization])

    scope =
      Scope.for_user(membership.user)
      |> Scope.with_organization(membership.organization, membership)

    {:ok, collection} = Content.create_collection(scope, %{title: "Picker Target"})
    {:ok, series} = Content.create_series(scope, %{title: "Picker Series"})
    {:ok, season} = Content.create_season(scope, series, %{title: "Picker Season"})

    {:ok, view, _html} = live(conn_for(membership), ~p"/admin/collections")
    render_click(view, "view_collection", %{id: collection.id})
    view |> element(~s([data-test="add-videos-btn"])) |> render_click()

    %{org: org, view: view, collection: collection, series: series, season: season}
  end

  defp collection_items(org, collection) do
    %{results: items} = Content.list_collection_items(org, collection)
    items
  end

  test "season picker items are buttons and clicking one adds the season" do
    %{org: org, view: view, collection: collection, season: season} = setup_picker()

    view |> element(~s([data-test="picker-type-season"])) |> render_click()

    item = ~s([data-test="picker-item-season-#{season.id}"])
    assert has_element?(view, "button#{item}")
    refute has_element?(view, "div#{item}")
    assert has_element?(view, ~s(button#{item}[type="button"]))

    view |> element("button#{item}") |> render_click()

    assert Enum.any?(collection_items(org, collection), &(&1.season_id == season.id))
  end

  test "series picker items are buttons and clicking one adds the series" do
    %{org: org, view: view, collection: collection, series: series} = setup_picker()

    view |> element(~s([data-test="picker-type-series"])) |> render_click()

    item = ~s([data-test="picker-item-series-#{series.id}"])
    assert has_element?(view, "button#{item}")
    refute has_element?(view, "div#{item}")
    assert has_element?(view, ~s(button#{item}[type="button"]))

    view |> element("button#{item}") |> render_click()

    assert Enum.any?(collection_items(org, collection), &(&1.series_id == series.id))
  end
end
