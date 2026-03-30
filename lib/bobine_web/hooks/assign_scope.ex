defmodule BobineWeb.Hooks.AssignScope do
  @moduledoc """
  LiveView `on_mount` hooks that build the full scope (user + organization +
  membership) from the session and socket host URI.

  ## Actions

    * `:assign_org` — resolves organization and assigns scope, no auth required.
      Used for public viewer routes.

    * `:require_authenticated` — resolves full scope and halts with a redirect
      if the user is not authenticated or has no membership in the resolved org.
      Used for admin routes.

  ## Usage

      live_session :admin,
        on_mount: [{BobineWeb.Hooks.AssignScope, :require_authenticated}] do
        live "/admin", BobineWeb.Admin.DashboardLive
      end

  """

  use BobineWeb, :verified_routes

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3, redirect: 2]

  alias Bobine.Accounts
  alias Bobine.Accounts.Scope

  def on_mount(:require_authenticated, _params, session, socket) do
    socket = mount_full_scope(socket, session)
    scope = socket.assigns.current_scope

    cond do
      is_nil(scope) or is_nil(scope.user) ->
        {:halt,
         socket
         |> put_flash(:error, "You must log in to access this page.")
         |> redirect(to: ~p"/users/log-in")}

      is_nil(scope.organization) ->
        {:halt,
         socket
         |> put_flash(:error, "Organization not found.")
         |> redirect(to: ~p"/users/log-in")}

      # Super admins can access any org's admin pages without a membership
      scope.user.is_super_admin ->
        {:cont, socket}

      is_nil(scope.membership) ->
        {:halt,
         socket
         |> put_flash(:error, "You don't have access to this organization.")
         |> redirect(to: ~p"/")}

      true ->
        {:cont, socket}
    end
  end

  def on_mount(:assign_org, _params, session, socket) do
    if session["no_org_resolved"] do
      # Super admin with no org — skip org resolution, let the LiveView handle it
      user = load_user_from_session(session)

      socket =
        socket
        |> assign(:current_scope, user && Scope.for_user(user))
        |> assign(:current_user, user)
        |> assign(:organization, nil)
        |> assign(:current_membership, nil)
        |> assign(:current_path, derive_current_path(socket))
        |> assign(:impersonating, false)

      {:cont, socket}
    else
      {:cont, mount_full_scope(socket, session)}
    end
  end

  defp mount_full_scope(socket, session) do
    user = load_user_from_session(session)
    host = socket.host_uri && socket.host_uri.host
    org = resolve_org(host, session)
    impersonating = impersonating?(user, session)

    membership =
      if org && user && !impersonating do
        Accounts.get_membership(org, user)
      end

    scope =
      case Scope.for_user(user) do
        nil ->
          nil

        s when not is_nil(org) and not is_nil(membership) ->
          Scope.with_organization(s, org, membership)

        s when not is_nil(org) and impersonating ->
          Scope.with_organization(s, org, nil)

        s ->
          s
      end

    socket
    |> assign(:current_scope, scope)
    |> assign(:current_user, user)
    |> assign(:organization, org)
    |> assign(:current_membership, membership)
    |> assign(:current_path, derive_current_path(socket))
    |> assign(:impersonating, impersonating)
  end

  defp derive_current_path(socket) do
    case socket.view do
      BobineWeb.Admin.DashboardLive -> "/admin"
      BobineWeb.Admin.ContentLive -> "/admin/content"
      BobineWeb.Admin.CollectionsLive -> "/admin/collections"
      BobineWeb.Admin.TagsLive -> "/admin/tags"
      BobineWeb.Admin.CatalogLive -> "/admin/catalog"
      BobineWeb.Admin.AnalyticsLive -> "/admin/analytics"
      BobineWeb.Admin.BrandingLive -> "/admin/branding"
      BobineWeb.Admin.MembersLive -> "/admin/members"
      BobineWeb.Admin.WebhooksLive -> "/admin/webhooks"
      BobineWeb.Admin.SettingsLive -> "/admin/settings"
      BobineWeb.Super.DashboardLive -> "/super"
      BobineWeb.Super.OrganizationsLive -> "/super/organizations"
      BobineWeb.Super.UsersLive -> "/super/users"
      _ -> nil
    end
  end

  defp impersonating?(nil, _session), do: false

  defp impersonating?(user, session) do
    user.is_super_admin && not is_nil(session["impersonated_org_id"])
  end

  defp load_user_from_session(session) do
    {user, _} =
      if token = session["user_token"] do
        Accounts.get_user_by_session_token(token)
      end || {nil, nil}

    user
  end

  defp resolve_org(nil, session), do: resolve_org_from_session(session)

  defp resolve_org(host, session) do
    with {:error, _} <- resolve_impersonated_org(session),
         {:error, _} <- Accounts.get_organization_by_custom_domain(host),
         {:error, _} <- resolve_by_subdomain(host),
         {:error, _} <- resolve_org_from_session(session) do
      resolve_dev_fallback()
    else
      {:ok, org} -> org
      nil -> nil
    end
  end

  # If a super admin is impersonating, the impersonated org takes precedence.
  defp resolve_impersonated_org(session) do
    case session["impersonated_org_id"] do
      nil -> {:error, :not_found}
      org_id -> Bobine.Repo.get(Bobine.Accounts.Organization, org_id) |> wrap_org()
    end
  end

  # Read the org_id stashed by the SetOrganization plug into the session during
  # the HTTP phase. This bridges plug-land to LiveView-land on the WS upgrade.
  defp resolve_org_from_session(session) do
    case session["organization_id"] do
      nil -> {:error, :not_found}
      org_id -> Bobine.Repo.get(Bobine.Accounts.Organization, org_id) |> wrap_org()
    end
  end

  defp wrap_org(nil), do: {:error, :not_found}
  defp wrap_org(org), do: {:ok, org}

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
    defp resolve_dev_fallback do
      case Bobine.Repo.all(Bobine.Accounts.Organization) do
        [org | _] -> {:ok, org}
        [] -> {:error, :not_found}
      end
    end
  else
    defp resolve_dev_fallback, do: {:error, :not_found}
  end
end
