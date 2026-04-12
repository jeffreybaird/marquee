# NOTE: Convert to static page with LiveView islands for hero carousel
# and any interactive elements. The catalog rows are read-only and should
# be server-rendered HTML for performance at scale.
defmodule BobineWeb.Viewer.HomeLive do
  @moduledoc """
  Homepage with multiple modes based on context:
  - org_home: hero carousel + catalog rows for authenticated org viewers
  - org_landing: minimal landing page when org resolved but no viewer auth
  - platform_marketing: Bobine marketing page when no org resolved

  Hooks: HeroCarousel, CardFocus, RowScroller
  Events: card_toggle_favorite, card_add_to_watchlist, card_add_to_queue (via CardActions)
  Route: / (home session, optional org + optional auth)
  """

  use BobineWeb, :live_view
  use BobineWeb.Viewer.CardActions

  import BobineWeb.Viewer.HomeLive.Components

  alias Bobine.Catalog
  alias Bobine.Content
  alias Bobine.LandingPage
  alias BobineWeb.Components.ViewerLayout

  @impl true
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    org = socket.assigns[:organization]
    viewer = socket.assigns[:current_viewer]

    cond do
      # Super admin with no org resolved -> send to super admin dashboard
      scope && scope.user && scope.user.is_super_admin && is_nil(org) ->
        {:ok, push_navigate(socket, to: ~p"/super")}

      # Authenticated operator with org but no viewer session -> show org home
      org && is_nil(viewer) && scope && scope.user ->
        {:ok, mount_org_home(socket, org, nil)}

      # Org resolved + viewer -> show catalog
      org && viewer ->
        {:ok, mount_org_home(socket, org, viewer)}

      # Org resolved but no auth -> org landing page
      org ->
        {:ok, mount_landing_page(socket, org)}

      # No org, no super admin -> platform marketing page
      true ->
        {:ok,
         socket
         |> assign(:page_title, "Bobine — Your Video Platform")
         |> assign(:page_mode, :platform_marketing)}
    end
  end

  defp mount_landing_page(socket, org) do
    sections =
      org
      |> LandingPage.list_landing_sections()
      |> Enum.map(&LandingPage.resolve_landing_section(org, &1))

    if sections == [] do
      mount_org_home(socket, org, nil)
    else
      socket
      |> assign(:page_title, org.name)
      |> assign(:page_mode, :org_landing)
      |> assign(:landing_sections, sections)
    end
  end

  defp mount_org_home(socket, org, viewer) do
    %{slides: hero_slides, auto_advance_ms: auto_advance_ms} =
      Catalog.resolve_hero_slides_cached(org)

    rows = load_catalog_rows(org, viewer)

    socket
    |> assign(:page_title, org.name)
    |> assign(:page_mode, :org_home)
    |> assign(:hero_slides, hero_slides)
    |> assign(:hero_auto_advance_ms, auto_advance_ms)
    |> assign(:rows, rows)
  end

  defp load_catalog_rows(org, viewer) do
    org
    |> Catalog.load_catalog_rows_with_items(viewer: viewer)
    |> Enum.map(fn %{row: row} = entry ->
      Map.put(entry, :view_all_path, resolve_view_all_path(org, row))
    end)
  end

  defp resolve_view_all_path(org, %{source_type: :collection, source_id: source_id})
       when not is_nil(source_id) do
    case Content.get_collection(org, source_id) do
      {:ok, collection} -> ~p"/collections/#{collection.slug}"
      _ -> nil
    end
  end

  defp resolve_view_all_path(_org, %{source_type: :popular}), do: ~p"/browse/popular"
  defp resolve_view_all_path(_org, %{source_type: :recent}), do: ~p"/browse/recent"

  defp resolve_view_all_path(_org, %{source_type: :tag, source_id: source_id})
       when not is_nil(source_id) do
    ~p"/browse?#{[tag: source_id]}"
  end

  defp resolve_view_all_path(_org, _row), do: nil
end
