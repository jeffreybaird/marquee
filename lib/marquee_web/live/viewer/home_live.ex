# NOTE: Convert to static page with LiveView islands for hero carousel
# and any interactive elements. The catalog rows are read-only and should
# be server-rendered HTML for performance at scale.
defmodule MarqueeWeb.Viewer.HomeLive do
  @moduledoc """
  Homepage with multiple modes based on context:
  - org_home: hero carousel + catalog rows for authenticated org viewers
  - org_landing: minimal landing page when org resolved but no viewer auth
  - platform_marketing: Marquee marketing page when no org resolved

  Hooks: HeroCarousel, CardFocus, RowScroller
  Events: card_toggle_favorite, card_add_to_watchlist, card_add_to_queue (via CardActions)
  Route: / (home session, optional org + optional auth)
  """

  use MarqueeWeb, :live_view
  use MarqueeWeb.Viewer.CardActions

  import MarqueeWeb.Viewer.HomeLive.Components

  alias Marquee.Accounts
  alias Marquee.Catalog
  alias Marquee.Content
  alias Marquee.Engagement
  alias Marquee.LandingPage
  alias MarqueeWeb.Components.ViewerLayout

  @impl true
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  def mount(params, _session, socket) do
    scope = socket.assigns.current_scope
    org = socket.assigns[:organization]
    viewer = socket.assigns[:current_viewer]
    impersonating_viewer = socket.assigns[:impersonating_viewer] == true
    user = scope && scope.user
    org_param = params["org"]

    primary_org = user && Accounts.get_user_primary_organization(user)

    cond do
      viewer && Marquee.SubscriberDemo.demo_viewer?(viewer) && org ->
        {:ok, mount_org_home(socket, org, viewer)}

      # Operator or super admin previewing the member-facing site via the
      # admin "View site" link. Bypass the dashboard redirects so they land
      # on the org's viewer home and see exactly what members see, instead
      # of being bounced back to the admin panel.
      viewer && viewer.__preview__ && org ->
        {:ok, mount_org_home(socket, org, viewer)}

      # Super admin -> always route to the super dashboard regardless of
      # whether a tenant was resolved in the request. Skip when the user is
      # actively impersonating a viewer — the viewer home is the point.
      user && user.is_super_admin && not impersonating_viewer ->
        {:ok, redirect(socket, to: ~p"/super")}

      # Operator with at least one membership -> route to that org's admin
      # with the explicit ?org=<slug> param so dev tenant resolution works.
      # Bypassed during viewer impersonation so the operator lands on the
      # viewer home they requested.
      primary_org && not impersonating_viewer ->
        {:ok, redirect(socket, to: admin_path_for_org(primary_org))}

      # Viewer signed in but reached / without any tenant context in the
      # URL (no subdomain, no ?org=). Make the URL explicit so links
      # render with the right org param.
      viewer && org && org_param != org.slug && needs_org_param?(socket) ->
        {:ok, redirect(socket, to: home_path_for_org(org))}

      # Viewer with no org resolvable (defensive — shouldn't happen since
      # the viewer token resolves org by default).
      viewer && is_nil(org) ->
        case fetch_viewer_org(viewer) do
          nil -> {:ok, mount_landing_or_marketing(socket, nil)}
          viewer_org -> {:ok, redirect(socket, to: home_path_for_org(viewer_org))}
        end

      # Org resolved + viewer -> full viewer home.
      org && viewer ->
        {:ok, mount_org_home(socket, org, viewer)}

      # Org resolved but no auth -> org landing page.
      org ->
        {:ok, mount_landing_page(socket, org)}

      # No org, no user, no viewer -> Marquee platform marketing.
      true ->
        {:ok, mount_landing_or_marketing(socket, nil)}
    end
  end

  defp mount_landing_or_marketing(socket, _) do
    socket
    |> assign(:page_title, "Marquee — Your Video Platform")
    |> assign(:page_mode, :platform_marketing)
    |> assign(:subscriber_demo_url, subscriber_demo_url())
  end

  defp subscriber_demo_url do
    case Marquee.Admin.get_subscriber_demo_organization() do
      {:ok, org} ->
        demo_url_for_org(org)

      _ ->
        nil
    end
  end

  defp demo_url_for_org(org) do
    hostname? =
      Application.get_env(:marquee, :org_resolution) == :hostname or
        Application.get_env(:marquee, :tenant_domain_provisioning, [])[:enabled] == true

    if hostname? and is_nil(Application.get_env(:marquee, :tenant_host_pattern)) do
      uri = URI.parse(MarqueeWeb.Endpoint.url())
      %{uri | host: org.custom_domain || "#{org.slug}.#{uri.host}", path: "/"} |> URI.to_string()
    else
      base =
        if hostname? do
          config = Application.get_env(:marquee, MarqueeWeb.Endpoint, [])[:url] || []
          uri = URI.new!("#{config[:scheme] || "https"}://#{config[:host]}")
          URI.to_string(%{uri | port: config[:port], path: "/"})
        else
          "/"
        end

      MarqueeWeb.OrgURL.org_url(base, org)
    end
  end

  defp admin_path_for_org(%{slug: slug} = org) when is_binary(slug),
    do: MarqueeWeb.OrgURL.org_url("/admin", org)

  defp admin_path_for_org(_), do: "/admin"

  defp home_path_for_org(%{slug: slug} = org) when is_binary(slug),
    do: MarqueeWeb.OrgURL.org_url("/", org)

  defp home_path_for_org(_), do: "/"

  defp fetch_viewer_org(%{organization_id: org_id}) when is_binary(org_id) do
    case Marquee.Accounts.get_organization(org_id) do
      {:ok, org} -> org
      {:error, :not_found} -> nil
    end
  end

  defp fetch_viewer_org(_), do: nil

  # The URL needs ?org=<slug> only when the request didn't already carry
  # tenant context via the host — i.e. plain platform domain or
  # localhost. Subdomain or custom domain requests already pin the
  # tenant, so don't churn the URL.
  defp needs_org_param?(socket) do
    host = socket.host_uri && socket.host_uri.host

    Application.get_env(:marquee, :org_resolution) != :hostname and
      (is_nil(host) or host_subdomain(host) in [nil, "www"])
  end

  defp host_subdomain(host) do
    case String.split(host, ".") do
      [first | rest] when rest != [] ->
        if Regex.match?(~r/^\d+$/, first), do: nil, else: first

      _ ->
        nil
    end
  end

  defp mount_landing_page(socket, org) do
    %{results: raw_sections} = LandingPage.list_landing_sections(org, per_page: 100)
    sections = Enum.map(raw_sections, &LandingPage.resolve_landing_section(org, &1))

    socket
    |> assign(:page_title, org.name)
    |> assign(:page_mode, :org_landing)
    |> assign(:landing_sections, sections)
  end

  defp mount_org_home(socket, org, viewer) do
    %{slides: hero_slides, auto_advance_ms: auto_advance_ms} =
      Catalog.resolve_hero_slides_cached(org)

    hero_slides =
      filter_demo_items(hero_slides, org, viewer, "subscriber_demo_video_ids", & &1.video_id)
      |> link_demo_series(org, viewer)

    rows = load_catalog_rows(org, viewer)

    if connected?(socket), do: Catalog.subscribe_to_layout(org)

    socket
    |> assign(:page_title, org.name)
    |> assign(:page_mode, :org_home)
    |> assign(:hero_slides, hero_slides)
    |> assign(:hero_auto_advance_ms, auto_advance_ms)
    |> assign(:rows, rows)
  end

  @impl true
  def handle_event("dismiss_continue", %{"id" => id, "kind" => "series"}, socket) do
    org = socket.assigns[:organization]
    viewer = socket.assigns[:current_viewer]
    socket = remove_continue_watching_item(socket, id)
    if org && viewer, do: Engagement.dismiss_continue_watching(org, viewer, %{series_id: id})
    {:noreply, socket}
  end

  @impl true
  def handle_event("dismiss_continue", %{"id" => id, "kind" => "video"}, socket) do
    org = socket.assigns[:organization]
    viewer = socket.assigns[:current_viewer]
    socket = remove_continue_watching_item(socket, id)
    if org && viewer, do: Engagement.dismiss_continue_watching(org, viewer, %{video_id: id})
    {:noreply, socket}
  end

  @impl true
  def handle_info({:layout_updated, _layout}, socket) do
    org = socket.assigns[:organization]
    viewer = socket.assigns[:current_viewer]

    if org do
      rows = load_catalog_rows(org, viewer)
      {:noreply, assign(socket, :rows, rows)}
    else
      {:noreply, socket}
    end
  end

  defp load_catalog_rows(org, viewer) do
    org
    |> Catalog.load_catalog_rows_with_items(viewer: viewer)
    |> filter_demo_items(org, viewer, "subscriber_demo_row_ids", & &1.row.id)
    |> Enum.map(fn %{row: row} = entry ->
      Map.put(entry, :view_all_path, resolve_view_all_path(org, row))
    end)
  end

  defp filter_demo_items(items, org, viewer, key, id) do
    ids = (org.features || %{})[key]

    if Marquee.SubscriberDemo.demo_viewer?(viewer) && is_list(ids),
      do: Enum.filter(items, &(id.(&1) in ids)),
      else: items
  end

  defp link_demo_series(slides, org, viewer) do
    slug = (org.features || %{})["subscriber_demo_series_slug"]

    if Marquee.SubscriberDemo.demo_viewer?(viewer) && is_binary(slug),
      do: Enum.map(slides, &Map.put(&1, :secondary_cta_path, "/series/#{slug}")),
      else: slides
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

  defp remove_continue_watching_item(socket, item_id) do
    rows =
      Enum.map(socket.assigns[:rows] || [], fn
        %{row: %{source_type: :continue_watching}, items: items} = entry ->
          Map.put(entry, :items, Enum.reject(items, &(&1.id == item_id)))

        entry ->
          entry
      end)

    assign(socket, :rows, rows)
  end
end
