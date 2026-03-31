defmodule BobineWeb.Hooks.AssignViewerScope do
  @moduledoc """
  LiveView `on_mount` hook for viewer-facing routes.

  Completely separate from `AssignScope` which handles operator auth.
  Viewer sessions use `:viewer_token` in the session, not `:user_token`.

  ## Actions

    * `:optional_auth` — assigns `current_viewer` (may be nil). Used for
      public pages where auth is optional.

    * `:require_authenticated` — requires a valid viewer session. Redirects
      to `/login` if not authenticated. Redirects with error flash if
      suspended or banned.

  ## Impersonation

  Supports session-layered impersonation: if `impersonating_viewer_id` is
  in the session AND the operator has the required role, `current_viewer`
  is set to the impersonated viewer with `__impersonating__: true`.
  """

  use BobineWeb, :verified_routes

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3, redirect: 2]

  alias Bobine.Viewers
  alias Bobine.Accounts

  @impersonation_max_age_seconds 3600

  def on_mount(:optional_auth, _params, session, socket) do
    viewer = get_viewer_from_session(session)
    impersonating = viewer != nil && Map.get(viewer, :__impersonating__, false)

    {:cont,
     socket
     |> assign(:current_viewer, viewer)
     |> assign(:impersonating_viewer, impersonating)}
  end

  def on_mount(:require_authenticated, _params, session, socket) do
    case get_viewer_from_session(session) do
      nil ->
        {:halt,
         socket
         |> put_flash(:error, "You must sign in to access this page.")
         |> redirect(to: ~p"/login")}

      %{status: status} when status in [:suspended, :banned] ->
        {:halt,
         socket
         |> put_flash(:error, "Your account has been suspended.")
         |> redirect(to: ~p"/")}

      viewer ->
        impersonating = Map.get(viewer, :__impersonating__, false)

        {:cont,
         socket
         |> assign(:current_viewer, viewer)
         |> assign(:impersonating_viewer, impersonating)}
    end
  end

  defp get_viewer_from_session(session) do
    cond do
      # Check for impersonation first
      viewer_id = session["impersonating_viewer_id"] ->
        handle_impersonation(session, viewer_id)

      # Normal viewer auth
      token = session["viewer_token"] ->
        Viewers.get_viewer_by_session_token(token)

      true ->
        nil
    end
  end

  defp handle_impersonation(session, viewer_id) do
    started_at = session["impersonation_started_at"]

    cond do
      is_nil(started_at) ->
        nil

      impersonation_expired?(started_at) ->
        nil

      true ->
        admin_user_id = session["impersonating_admin_user_id"]

        if authorized_to_impersonate?(admin_user_id, viewer_id) do
          case Viewers.get_viewer_by_id(viewer_id) do
            nil -> nil
            viewer -> %{viewer | __impersonating__: true}
          end
        end
    end
  end

  defp impersonation_expired?(started_at) when is_integer(started_at) do
    now = System.system_time(:second)
    now - started_at > @impersonation_max_age_seconds
  end

  defp impersonation_expired?(_), do: true

  defp authorized_to_impersonate?(nil, _viewer_id), do: false

  defp authorized_to_impersonate?(admin_user_id, viewer_id) do
    user = Accounts.get_user!(admin_user_id)

    if user.is_super_admin do
      true
    else
      viewer = Viewers.get_viewer_by_id(viewer_id)

      if viewer do
        case Accounts.get_membership(
               %Bobine.Accounts.Organization{id: viewer.organization_id},
               user
             ) do
          nil -> false
          membership -> Accounts.role_at_least?(membership, :viewer_support)
        end
      else
        false
      end
    end
  end
end
