# credo:disable-for-this-file Credo.Check.Refactor.CyclomaticComplexity
# credo:disable-for-this-file Credo.Check.Refactor.Nesting
defmodule MarqueeWeb.Plugs.SetOrganization do
  @moduledoc """
  Resolves the current tenant organization from the request host and
  updates the current_scope with the organization and membership.

  Resolution mode is selected via `Application.get_env(:marquee, :org_resolution)`:

  * `:query_param` (dev/staging) — checks `?org=slug` and the
    `x-marquee-org` header, falls back to a slug stashed in the session, then
    to the user's membership / first org. The slug from a successful
    query-param lookup is persisted to the session so subsequent requests
    without the param still resolve to the same tenant.

  * `:hostname` (production) — resolves only by custom domain or subdomain.
    The `?org=` query param is ignored entirely so it cannot be used to
    cross-tenant pivot in prod.

  In both modes super admins with an active impersonation session resolve
  to the impersonated org first.

  Sets `conn.assigns.current_scope` (when user + membership found) or
  `conn.assigns.organization` (for public/viewer routes without membership).
  """

  import Plug.Conn

  alias Marquee.Accounts
  alias Marquee.Accounts.Scope

  def init(opts), do: opts

  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  # credo:disable-for-next-line Credo.Check.Refactor.Nesting
  def call(conn, opts) do
    conn = fetch_query_params(conn)

    case resolve_organization(conn, opts) do
      {:ok, organization} ->
        conn = put_org_in_session(conn, organization)
        scope = conn.assigns[:current_scope]

        if scope && scope.user do
          case Accounts.get_membership(organization, scope.user) do
            nil when scope.user.is_super_admin ->
              # Super admin impersonating — no membership needed
              updated_scope = Scope.with_organization(scope, organization, nil)

              conn
              |> assign(:current_scope, updated_scope)
              |> assign(:impersonating, true)

            nil ->
              assign(conn, :organization, organization)

            membership ->
              updated_scope = Scope.with_organization(scope, organization, membership)

              conn
              |> assign(:current_scope, updated_scope)
              |> assign(:impersonating, false)
          end
        else
          assign(conn, :organization, organization)
        end

      {:error, :not_found} ->
        scope = conn.assigns[:current_scope]

        cond do
          scope && scope.user && scope.user.is_super_admin ->
            # Let super admins through without an org — the LiveView
            # will redirect them to /super
            clear_org_from_session(conn)

          Keyword.get(opts, :optional, false) ->
            # Optional mode: let the request through with nil org.
            # Used for routes that serve both org-scoped and platform content.
            clear_org_from_session(conn)

          true ->
            conn
            |> put_resp_content_type("text/html")
            |> send_resp(404, "Organization not found")
            |> halt()
        end
    end
  end

  # Clears any stale organization_id/org_slug from the session and marks
  # the request as having no resolved org. Prevents a previous tenant's
  # slug from silently pivoting subsequent requests after an explicit
  # ?org= override fails to resolve.
  defp clear_org_from_session(conn) do
    conn
    |> assign(:organization, nil)
    |> delete_session(:organization_id)
    |> delete_session(:org_slug)
    |> put_session(:no_org_resolved, true)
  end

  # Stash the resolved org_id and slug in the session so the LiveView
  # AssignScope hook can look it up during the WebSocket upgrade (where plug
  # assigns are gone), and so subsequent requests in `:query_param` mode keep
  # resolving to the same tenant when the `?org=` param is dropped.
  # Also clear no_org_resolved so a stale marketing-page flag doesn't interfere.
  defp put_org_in_session(conn, org) do
    conn
    |> put_session(:organization_id, org.id)
    |> put_session(:org_slug, org.slug)
    |> delete_session(:no_org_resolved)
  end

  defp resolve_organization(conn, opts) do
    case resolution_mode() do
      :query_param -> resolve_query_param_mode(conn, opts)
      :hostname -> resolve_hostname_mode(conn, opts)
    end
  end

  defp resolution_mode do
    Application.get_env(:marquee, :org_resolution, :query_param)
  end

  # Dev/staging: an explicit `?org=`/header signal is authoritative — if it
  # is provided but does not resolve to a real org, the request fails rather
  # than silently pivoting to another tenant via session/membership/dev
  # fallbacks. With no explicit signal, fall through the usual chain:
  # impersonation → session slug → host → implicit → env fallback.
  defp resolve_query_param_mode(conn, opts) do
    optional? = Keyword.get(opts, :optional, false)

    case explicit_org_signal(conn) do
      {:ok, slug} ->
        Accounts.get_organization_by_slug(slug)

      :none ->
        with {:error, _} <- resolve_impersonated_org(conn),
             {:error, _} <- resolve_from_session_slug(conn),
             {:error, _} <- Accounts.get_organization_by_custom_domain(conn.host),
             {:error, _} <- resolve_by_subdomain(conn.host),
             {:error, _} <- maybe_resolve_implicit(conn, optional?) do
          resolve_env_fallback(optional?)
        end
    end
  end

  # Returns `{:ok, slug}` when the request carries an explicit org signal
  # (`?org=` query param or `x-marquee-org` header), `:none` otherwise.
  defp explicit_org_signal(conn) do
    slug =
      get_req_header(conn, "x-marquee-org") |> List.first() ||
        case conn.query_params do
          %Plug.Conn.Unfetched{} -> nil
          params -> Map.get(params, "org")
        end

    case slug do
      slug when is_binary(slug) and slug != "" -> {:ok, slug}
      _ -> :none
    end
  end

  # Production: only host-based resolution. The `?org=` param is ignored so
  # it cannot be used to pivot tenants on a shared host.
  defp resolve_hostname_mode(conn, opts) do
    optional? = Keyword.get(opts, :optional, false)

    with {:error, _} <- resolve_impersonated_org(conn),
         {:error, _} <- Accounts.get_organization_by_custom_domain(conn.host),
         {:error, _} <- resolve_by_subdomain(conn.host),
         {:error, _} <- maybe_resolve_implicit(conn, optional?) do
      {:error, :not_found}
    end
  end

  defp resolve_from_session_slug(conn) do
    case get_session(conn, :org_slug) do
      slug when is_binary(slug) -> Accounts.get_organization_by_slug(slug)
      _ -> {:error, :not_found}
    end
  end

  # In optional mode, resolve from session if an impersonation is active
  # (the admin chose a specific org) or if a viewer is logged in (viewer
  # belongs to exactly one org). Skip membership fallback and dev fallback
  # so that `/` without an explicit org signal shows the marketing page
  # for unauthenticated visitors.
  defp maybe_resolve_implicit(conn, true = _optional) do
    cond do
      get_session(conn, :impersonating_viewer_id) || get_session(conn, :impersonated_org_id) ->
        resolve_from_session(conn)

      get_session(conn, :viewer_token) ->
        resolve_from_viewer_token(conn)

      true ->
        {:error, :not_found}
    end
  end

  defp maybe_resolve_implicit(conn, false) do
    with {:error, _} <- resolve_from_session(conn),
         {:error, _} <- resolve_from_viewer_token(conn),
         {:error, _} <- resolve_from_user_membership(conn) do
      {:error, :not_found}
    end
  end

  defp resolve_from_viewer_token(conn) do
    case get_session(conn, :viewer_token) do
      nil ->
        {:error, :not_found}

      token ->
        case Marquee.Viewers.get_viewer_by_session_token(token) do
          %{organization_id: org_id} -> Accounts.get_organization(org_id)
          nil -> {:error, :not_found}
        end
    end
  end

  defp resolve_from_session(conn) do
    case get_session(conn, :organization_id) do
      nil -> {:error, :not_found}
      org_id -> Accounts.get_organization(org_id)
    end
  end

  defp resolve_from_user_membership(conn) do
    case conn.assigns[:current_scope] do
      %{user: user} when not is_nil(user) -> Accounts.fetch_user_primary_organization(user)
      _ -> {:error, :not_found}
    end
  end

  # When a super admin is impersonating, use the impersonated org regardless of host.
  defp resolve_impersonated_org(conn) do
    scope = conn.assigns[:current_scope]

    with true <- scope != nil and scope.user != nil and scope.user.is_super_admin,
         org_id when is_binary(org_id) <- get_session(conn, :impersonated_org_id) do
      Accounts.get_organization(org_id)
    else
      _ -> {:error, :not_found}
    end
  end

  defp resolve_by_subdomain(host) do
    case extract_subdomain(host) do
      nil -> {:error, :not_found}
      subdomain -> Accounts.get_organization_by_slug(subdomain)
    end
  end

  defp extract_subdomain(host) do
    parts = String.split(host, ".")

    if length(parts) >= 2 do
      first = List.first(parts)
      if first != "www" and not Regex.match?(~r/^\d+$/, first), do: first
    end
  end

  if Mix.env() == :dev do
    # In dev, fall back to the first org when no slug is provided.
    # Skipped in optional mode so the marketing page can render.
    defp resolve_env_fallback(true = _optional), do: {:error, :not_found}
    defp resolve_env_fallback(false), do: Accounts.fetch_any_organization()
  else
    defp resolve_env_fallback(_optional), do: {:error, :not_found}
  end
end
