defmodule BobineWeb.Super.UsersLive do
  use BobineWeb, :live_view

  alias Bobine.Admin

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Users")
     |> assign(:current_path, "/super/users")
     |> assign(:current_user, socket.assigns.current_scope.user)
     |> assign(:confirm_revoke_id, nil)
     |> load_users()}
  end

  @impl true
  def handle_event("grant_super_admin", %{"id" => id}, socket) do
    user = find_user!(socket.assigns.users, id)

    case Admin.grant_super_admin(user) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Super admin granted to #{user.email}.")
         |> load_users()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to grant super admin.")}
    end
  end

  @impl true
  def handle_event("confirm_revoke", %{"id" => id}, socket) do
    {:noreply, assign(socket, :confirm_revoke_id, id)}
  end

  @impl true
  def handle_event("cancel_revoke", _params, socket) do
    {:noreply, assign(socket, :confirm_revoke_id, nil)}
  end

  @impl true
  def handle_event("revoke_super_admin", %{"id" => id}, socket) do
    current_user = socket.assigns.current_user

    if current_user.id == id do
      {:noreply,
       socket
       |> put_flash(:error, "You cannot revoke your own super admin status.")
       |> assign(:confirm_revoke_id, nil)}
    else
      user = find_user!(socket.assigns.users, id)

      case Admin.revoke_super_admin(user) do
        {:ok, _} ->
          {:noreply,
           socket
           |> put_flash(:info, "Super admin revoked from #{user.email}.")
           |> assign(:confirm_revoke_id, nil)
           |> load_users()}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to revoke super admin.")}
      end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <BobineWeb.Components.SuperLayout.super_layout
      current_path={@current_path}
      current_user={@current_user}
      flash={@flash}
    >
      <.header>Users</.header>

      <div class="mt-8 overflow-x-auto">
        <table class="table w-full" data-test="users-table">
          <thead>
            <tr>
              <th>Email</th>
              <th>Super Admin</th>
              <th>Joined</th>
              <th>Actions</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={user <- @users} data-test={"user-row-#{user.id}"}>
              <td>{user.email}</td>
              <td>
                <span
                  :if={user.is_super_admin}
                  class="badge badge-error badge-sm"
                  data-test={"super-admin-badge-#{user.id}"}
                >
                  Super Admin
                </span>
              </td>
              <td class="text-sm text-base-content/60">
                {Calendar.strftime(user.inserted_at, "%b %d, %Y")}
              </td>
              <td>
                <div :if={@confirm_revoke_id == user.id} class="flex items-center gap-2">
                  <span class="text-sm">Revoke super admin?</span>
                  <button
                    phx-click="revoke_super_admin"
                    phx-value-id={user.id}
                    class="btn btn-xs btn-error"
                    data-test={"confirm-revoke-#{user.id}"}
                  >
                    Yes, revoke
                  </button>
                  <button
                    phx-click="cancel_revoke"
                    class="btn btn-xs btn-ghost"
                    data-test={"cancel-revoke-#{user.id}"}
                  >
                    Cancel
                  </button>
                </div>

                <div :if={@confirm_revoke_id != user.id} class="flex gap-2">
                  <button
                    :if={!user.is_super_admin}
                    phx-click="grant_super_admin"
                    phx-value-id={user.id}
                    class="btn btn-xs btn-outline"
                    data-test={"grant-super-admin-#{user.id}"}
                  >
                    Grant Super Admin
                  </button>
                  <button
                    :if={user.is_super_admin}
                    phx-click="confirm_revoke"
                    phx-value-id={user.id}
                    class="btn btn-xs btn-outline btn-error"
                    data-test={"revoke-super-admin-#{user.id}"}
                  >
                    Revoke
                  </button>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </BobineWeb.Components.SuperLayout.super_layout>
    """
  end

  defp load_users(socket) do
    %{results: users} = Admin.list_users()
    assign(socket, :users, users)
  end

  defp find_user!(users, id) do
    Enum.find(users, &(&1.id == id)) ||
      raise "User #{id} not found in current user list"
  end
end
