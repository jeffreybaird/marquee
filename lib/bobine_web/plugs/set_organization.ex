defmodule BobineWeb.Plugs.SetOrganization do
  @moduledoc """
  Resolves the current tenant organization from the request host and
  updates the current_scope with the organization and membership.

  Resolution order:
  1. Custom domain — match `organizations.custom_domain`
  2. Subdomain — extract first subdomain segment, match `organizations.slug`
  3. Dev fallback — only in dev: `x-bobine-org` header, `?org=` param, or first org
  4. 404 — if no tenant is resolved

  Sets `conn.assigns.current_scope` (when user + membership found) or
  `conn.assigns.organization` (for public/viewer routes without membership).
  """

  import Plug.Conn
  import Ecto.Query, only: [from: 2]

  alias Bobine.Accounts
  alias Bobine.Accounts.Scope

  def init(opts), do: opts

  def call(conn, opts) do
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
            conn
            |> assign(:organization, nil)
            |> put_session(:no_org_resolved, true)

          Keyword.get(opts, :optional, false) ->
            # Optional mode: let the request through with nil org.
            # Used for routes that serve both org-scoped and platform content.
            conn
            |> assign(:organization, nil)
            |> put_session(:no_org_resolved, true)

          true ->
            conn
            |> put_resp_content_type("text/html")
            |> send_resp(404, "Organization not found")
            |> halt()
        end
    end
  end

  # Stash the resolved org_id in the session so the LiveView AssignScope hook
  # can look it up during the WebSocket upgrade (where plug assigns are gone).
  # Also clear no_org_resolved so a stale marketing-page flag doesn't interfere.
  defp put_org_in_session(conn, org) do
    conn
    |> put_session(:organization_id, org.id)
    |> delete_session(:no_org_resolved)
  end

  defp resolve_organization(conn, opts) do
    optional? = Keyword.get(opts, :optional, false)

    with {:error, _} <- resolve_impersonated_org(conn),
         {:error, _} <- Accounts.get_organization_by_custom_domain(conn.host),
         {:error, _} <- resolve_by_subdomain(conn.host),
         {:error, _} <- resolve_from_query_or_header(conn),
         {:error, _} <- maybe_resolve_implicit(conn, optional?) do
      resolve_env_fallback(optional?)
    end
  end

  # Implicit sources (session, membership, dev fallback) are skipped in
  # optional mode so that `/` without an explicit org signal shows the
  # platform marketing page instead of a sticky/fallback org.
  defp maybe_resolve_implicit(_conn, true = _optional), do: {:error, :not_found}

  defp maybe_resolve_implicit(conn, false) do
    with {:error, _} <- resolve_from_session(conn),
         {:error, _} <- resolve_from_user_membership(conn) do
      {:error, :not_found}
    end
  end

  defp resolve_from_session(conn) do
    case get_session(conn, :organization_id) do
      nil -> {:error, :not_found}
      org_id -> Bobine.Repo.get(Accounts.Organization, org_id) |> wrap_org()
    end
  end

  defp resolve_from_user_membership(conn) do
    scope = conn.assigns[:current_scope]

    if scope && scope.user do
      case Bobine.Repo.one(
             from m in Bobine.Accounts.Membership,
               where: m.user_id == ^scope.user.id,
               join: o in assoc(m, :organization),
               where: is_nil(o.deleted_at),
               select: o,
               limit: 1
           ) do
        nil -> {:error, :not_found}
        org -> {:ok, org}
      end
    else
      {:error, :not_found}
    end
  end

  defp wrap_org(nil), do: {:error, :not_found}
  defp wrap_org(org), do: {:ok, org}

  # When a super admin is impersonating, use the impersonated org regardless of host.
  defp resolve_impersonated_org(conn) do
    scope = conn.assigns[:current_scope]

    with true <- scope != nil and scope.user != nil and scope.user.is_super_admin,
         org_id when is_binary(org_id) <- get_session(conn, :impersonated_org_id),
         org when org != nil <- Bobine.Repo.get(Bobine.Accounts.Organization, org_id) do
      {:ok, org}
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

  # All environments: resolve from ?org=slug query param or x-bobine-org header.
  # This enables staging on shared hosts (e.g. app.fly.dev/?org=demo) where
  # wildcard subdomains are not available.
  defp resolve_from_query_or_header(conn) do
    slug_from_header = get_req_header(conn, "x-bobine-org") |> List.first()

    slug_from_param =
      case conn.params do
        %Plug.Conn.Unfetched{} -> nil
        params -> Map.get(params, "org")
      end

    case slug_from_header || slug_from_param do
      nil -> {:error, :not_found}
      slug -> Accounts.get_organization_by_slug(slug)
    end
  end

  if Mix.env() == :dev do
    # In dev, fall back to the first org when no slug is provided.
    # Skipped in optional mode so the marketing page can render.
    defp resolve_env_fallback(true = _optional), do: {:error, :not_found}

    defp resolve_env_fallback(false) do
      case Bobine.Repo.all(Bobine.Accounts.Organization) do
        [org | _] -> {:ok, org}
        [] -> {:error, :not_found}
      end
    end
  else
    defp resolve_env_fallback(_optional), do: {:error, :not_found}
  end
end
