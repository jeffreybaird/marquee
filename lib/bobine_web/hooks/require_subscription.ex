defmodule BobineWeb.Hooks.RequireSubscription do
  @moduledoc """
  LiveView `on_mount` hook that gates access to subscription-required pages.

  Must be used after `AssignViewerScope` so that `current_viewer` is available.
  """

  use BobineWeb, :verified_routes

  import Phoenix.LiveView, only: [put_flash: 3, redirect: 2]

  alias Bobine.Viewers.SubscriptionAccess

  def on_mount(:require_subscription, _params, _session, socket) do
    viewer = socket.assigns[:current_viewer]

    cond do
      is_nil(viewer) ->
        {:halt, redirect(socket, to: ~p"/login")}

      viewer.status in [:suspended, :banned] ->
        {:halt,
         socket
         |> put_flash(:error, "Your account has been suspended.")
         |> redirect(to: ~p"/")}

      SubscriptionAccess.has_access?(viewer) ->
        {:cont, socket}

      true ->
        {:halt, redirect(socket, to: ~p"/subscribe")}
    end
  end
end
