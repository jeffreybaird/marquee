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

  alias Bobine.Accounts
  alias Bobine.Accounts.Scope

  def init(opts), do: opts

  def call(conn, _opts) do
    case resolve_organization(conn) do
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
        conn
        |> put_resp_content_type("text/html")
        |> send_resp(404, "Organization not found")
        |> halt()
    end
  end

  # Stash the resolved org_id in the session so the LiveView AssignScope hook
  # can look it up during the WebSocket upgrade (where plug assigns are gone).
  defp put_org_in_session(conn, org) do
    put_session(conn, :organization_id, org.id)
  end

  defp resolve_organization(conn) do
    with {:error, _} <- resolve_impersonated_org(conn),
         {:error, _} <- Accounts.get_organization_by_custom_domain(conn.host),
         {:error, _} <- resolve_by_subdomain(conn.host) do
      resolve_dev_fallback(conn)
    end
  end

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

  if Mix.env() == :dev do
    defp resolve_dev_fallback(conn) do
      slug_from_header = get_req_header(conn, "x-bobine-org") |> List.first()
      slug_from_param = conn.params["org"]
      slug = slug_from_header || slug_from_param

      if slug do
        Accounts.get_organization_by_slug(slug)
      else
        case Bobine.Repo.all(Bobine.Accounts.Organization) do
          [org | _] -> {:ok, org}
          [] -> {:error, :not_found}
        end
      end
    end
  end

  if Mix.env() == :test do
    # In test, support ?org=slug param and x-bobine-org header for E2E tests,
    # but do NOT fall back to first org — tests must be explicit about which org
    # they resolve to keep async isolation safe.
    defp resolve_dev_fallback(conn) do
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
  end

  if Mix.env() not in [:dev, :test] do
    defp resolve_dev_fallback(_conn), do: {:error, :not_found}
  end
end
