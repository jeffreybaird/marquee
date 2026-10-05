defmodule MarqueeWeb.Hooks.AssignViewerScope do
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

  ## Member preview

  Authorized admins can navigate with a transient, subscribed preview identity.
  Preview events are read-only and authorization is checked at each mount.

  ## Impersonation

  Supports session-layered impersonation: if `impersonating_viewer_id` is
  in the session AND the operator has the required role, `current_viewer`
  is set to the impersonated viewer with `__impersonating__: true`.
  """

  use MarqueeWeb, :verified_routes

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3, redirect: 2]

  alias Marquee.Accounts
  alias Marquee.Accounts.Organization
  alias Marquee.Viewers
  alias MarqueeWeb.Plugs.MemberPreview

  @impersonation_max_age_seconds 3600

  def on_mount(:optional_auth, _params, session, socket) do
    viewer = resolve_viewer(session, socket)
    impersonating = viewer != nil && Map.get(viewer, :__impersonating__, false)

    {:cont,
     socket
     |> assign(:current_viewer, viewer)
     |> assign(:impersonating_viewer, impersonating)
     |> attach_preview_guard(viewer)
     |> attach_demo_guard(viewer, session)}
  end

  def on_mount(:require_authenticated, _params, session, socket) do
    case resolve_viewer(session, socket) do
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

        if Marquee.SubscriberDemo.demo_viewer?(viewer) && demo_excluded_page?(socket.view) do
          {:halt, redirect(socket, to: ~p"/")}
        else
          {:cont,
           socket
           |> assign(:current_viewer, viewer)
           |> assign(:impersonating_viewer, impersonating)
           |> attach_preview_guard(viewer)
           |> attach_demo_guard(viewer, session)}
        end
    end
  end

  defp resolve_viewer(%{"admin_demo_viewer_id" => id}, %{
         assigns: %{current_scope: %{admin_demo_session_id: demo_id} = scope}
       })
       when is_binary(demo_id) do
    case Marquee.AdminDemo.sample_viewer(scope, id) do
      {:ok, viewer} -> viewer
      _ -> nil
    end
  end

  defp resolve_viewer(session, socket) do
    org = socket.assigns[:organization]
    scope = socket.assigns[:current_scope]

    case MemberPreview.viewer(session, scope, org) do
      %Viewers.Viewer{} = viewer ->
        viewer

      nil ->
        case get_viewer_from_session(session) do
          %{organization_id: org_id} = viewer when not is_nil(org) and org_id == org.id ->
            viewer

          _ ->
            nil
        end
    end
  end

  defp attach_preview_guard(
         socket,
         %{__preview__: false, metadata: %{"admin_demo_sample" => true}} = viewer
       ) do
    attach_preview_guard(socket, %{viewer | __preview__: true})
  end

  defp attach_preview_guard(socket, %{__preview__: true}) do
    Phoenix.LiveView.attach_hook(socket, :member_preview, :handle_event, fn event, _, socket ->
      cond do
        event in ~w(filter load_more switch_tab toggle_chat toggle_queue switch_season play_episode go_back close_queue_dropdown cancel_add_season) ->
          {:cont, socket}

        String.starts_with?(event, "playback_") ->
          {:halt, socket}

        true ->
          {:halt, put_flash(socket, :info, "Member preview is read-only.")}
      end
    end)
  end

  defp attach_preview_guard(socket, _viewer), do: socket

  defp attach_demo_guard(socket, viewer, session) do
    if Marquee.SubscriberDemo.demo_viewer?(viewer) do
      Phoenix.LiveView.attach_hook(socket, :subscriber_demo, :handle_event, fn _, _, socket ->
        validate_demo_event(socket, viewer.id, session["viewer_token"])
      end)
    else
      socket
    end
  end

  defp validate_demo_event(socket, viewer_id, token) do
    case token && Viewers.get_viewer_by_session_token(token) do
      %{id: ^viewer_id} ->
        {:cont, socket}

      _ ->
        {:halt,
         socket
         |> put_flash(:info, "Your demo session has expired. Start a new demo to continue.")
         |> redirect(to: ~p"/")}
    end
  end

  defp demo_excluded_page?(view) do
    view in [
      MarqueeWeb.Viewer.AccountLive,
      MarqueeWeb.Viewer.SubscribeLive,
      MarqueeWeb.Viewer.PaymentIssueLive,
      MarqueeWeb.Viewer.SubscribeSuccessLive,
      MarqueeWeb.Viewer.LiveEventWatchLive
    ]
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

        case authorized_to_impersonate?(admin_user_id, viewer_id) do
          true -> fetch_viewer_for_impersonation(viewer_id)
          false -> nil
        end
    end
  end

  defp fetch_viewer_for_impersonation(viewer_id) do
    case Viewers.get_viewer_by_id(viewer_id) do
      nil -> nil
      viewer -> %{viewer | __impersonating__: true}
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
      authorize_viewer_impersonation(user, viewer_id)
    end
  end

  defp authorize_viewer_impersonation(user, viewer_id) do
    with %{organization_id: organization_id} <- Viewers.get_viewer_by_id(viewer_id),
         membership when not is_nil(membership) <-
           Accounts.get_membership(%Organization{id: organization_id}, user) do
      membership.role in [:viewer_support, :admin, :owner]
    else
      _ -> false
    end
  end
end
