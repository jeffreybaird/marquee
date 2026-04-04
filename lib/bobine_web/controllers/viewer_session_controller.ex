defmodule BobineWeb.Viewer.SessionController do
  @moduledoc """
  Handles viewer session creation/destruction and magic link verification.

  Completely separate from the operator `UserSessionController`.
  Viewer sessions use `:viewer_token` in the session.
  """

  use BobineWeb, :controller

  alias Bobine.Viewers

  @doc """
  GET /magic-link/:token — validates a magic link token and creates a viewer session.
  """
  def magic_link(conn, %{"token" => token}) do
    case Viewers.verify_viewer_magic_link(token) do
      {:ok, viewer} ->
        conn
        |> put_flash(:info, "Welcome back!")
        |> put_viewer_session(viewer)
        |> redirect(to: home_path(conn))

      {:error, :invalid_token} ->
        conn
        |> put_flash(:error, "The link is invalid or it has expired.")
        |> redirect(to: ~p"/login")
    end
  end

  @doc """
  POST /viewer-session — creates a viewer session (used by form-based login if needed).
  """
  def create(conn, %{"token" => token}) do
    case Viewers.verify_viewer_magic_link(token) do
      {:ok, viewer} ->
        conn
        |> put_flash(:info, "Welcome back!")
        |> put_viewer_session(viewer)
        |> redirect(to: ~p"/")

      {:error, :invalid_token} ->
        conn
        |> put_flash(:error, "The link is invalid or it has expired.")
        |> redirect(to: ~p"/login")
    end
  end

  @doc """
  DELETE /viewer-session — logs out the viewer.
  """
  def delete(conn, _params) do
    viewer_token = get_session(conn, :viewer_token)
    viewer_token && Viewers.delete_viewer_session_token(viewer_token)

    conn
    |> clear_viewer_session()
    |> put_flash(:info, "Signed out successfully.")
    |> redirect(to: ~p"/")
  end

  @doc """
  POST /viewer-session/impersonate — starts viewer impersonation (operator only).
  """
  def start_impersonation(conn, %{"viewer_id" => viewer_id, "return_path" => return_path}) do
    conn
    |> put_session(:impersonating_viewer_id, viewer_id)
    |> put_session(:impersonating_admin_user_id, conn.assigns.current_scope.user.id)
    |> put_session(:impersonating_return_path, return_path)
    |> put_session(:impersonation_started_at, System.system_time(:second))
    |> redirect(to: ~p"/")
  end

  @doc """
  DELETE /viewer-session/impersonate — stops viewer impersonation.
  """
  def stop_impersonation(conn, _params) do
    return_path = get_session(conn, :impersonating_return_path) || ~p"/admin/members"

    conn
    |> delete_session(:impersonating_viewer_id)
    |> delete_session(:impersonating_admin_user_id)
    |> delete_session(:impersonating_return_path)
    |> delete_session(:impersonation_started_at)
    |> redirect(to: return_path)
  end

  defp home_path(conn) do
    org = conn.assigns[:organization]

    if org && !resolved_from_subdomain?(conn) do
      ~p"/?org=#{org.slug}"
    else
      ~p"/"
    end
  end

  defp resolved_from_subdomain?(conn) do
    parts = String.split(conn.host, ".")
    length(parts) >= 2 && List.first(parts) not in ["www", "localhost"]
  end

  defp put_viewer_session(conn, viewer) do
    token = Viewers.generate_viewer_session_token(viewer)

    conn
    |> put_session(:viewer_token, token)
    |> put_session(:live_socket_id, "viewers_sessions:#{Base.url_encode64(token)}")
  end

  defp clear_viewer_session(conn) do
    conn
    |> delete_session(:viewer_token)
    |> delete_session(:live_socket_id)
  end
end
