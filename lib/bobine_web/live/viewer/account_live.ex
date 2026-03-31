defmodule BobineWeb.Viewer.AccountLive do
  use BobineWeb, :live_view

  alias Bobine.Viewers

  @impl true
  def mount(_params, _session, socket) do
    viewer = socket.assigns.current_viewer
    changeset = Viewers.Viewer.profile_changeset(viewer, %{})

    {:ok,
     socket
     |> assign(:page_title, "Account")
     |> assign(:viewer, viewer)
     |> assign(:editing, false)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("edit", _params, socket) do
    {:noreply, assign(socket, :editing, true)}
  end

  @impl true
  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, :editing, false)}
  end

  @impl true
  def handle_event("save", %{"viewer" => viewer_params}, socket) do
    viewer = socket.assigns.viewer
    scope = socket.assigns[:current_scope]

    case Viewers.update_viewer_profile(scope, viewer, viewer_params) do
      {:ok, updated_viewer} ->
        {:noreply,
         socket
         |> assign(:viewer, updated_viewer)
         |> assign(:editing, false)
         |> assign_form(Viewers.Viewer.profile_changeset(updated_viewer, %{}))
         |> put_flash(:info, "Profile updated.")}

      {:error, :validation, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  @impl true
  def handle_event("delete_account", _params, socket) do
    viewer = socket.assigns.viewer
    scope = socket.assigns[:current_scope]

    case Viewers.delete_viewer(scope, viewer) do
      {:ok, _viewer} ->
        {:noreply,
         socket
         |> put_flash(:info, "Your account has been deleted.")
         |> redirect(to: ~p"/")}

      {:error, _, _} ->
        {:noreply, put_flash(socket, :error, "Could not delete account.")}
    end
  end

  defp assign_form(socket, changeset), do: assign(socket, :form, to_form(changeset))

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      current_viewer={@current_viewer}
      organization={@organization}
    >
      <div class="max-w-lg mx-auto">
        <.header>Account</.header>

        <%!-- Impersonation banner --%>
        <div
          :if={@impersonating_viewer}
          class="mt-4 p-3 bg-amber-500/20 border border-amber-500 rounded-lg flex items-center justify-between"
          data-test="impersonation-banner"
        >
          <span class="text-amber-200 text-sm">
            Viewing as {@viewer.email}
          </span>
          <.link
            href={~p"/viewer-session/impersonate"}
            method="delete"
            class="text-amber-200 hover:text-amber-100 text-sm font-medium"
            data-test="stop-impersonation-btn"
          >
            Stop viewing
          </.link>
        </div>

        <div class="mt-6 space-y-6">
          <%!-- Profile section --%>
          <div class="bg-base-200 rounded-lg p-6">
            <h3 class="text-lg font-medium">Profile</h3>

            <div :if={!@editing} class="mt-4 space-y-2">
              <p data-test="account-email">
                <span class="text-base-content/60">Email:</span>
                <span>{@viewer.email}</span>
              </p>
              <p data-test="account-display-name">
                <span class="text-base-content/60">Display name:</span>
                <span>{@viewer.display_name}</span>
              </p>
              <button
                :if={!@impersonating_viewer}
                phx-click="edit"
                class="btn btn-sm btn-outline mt-2"
                data-test="account-edit-btn"
              >
                Edit
              </button>
            </div>

            <form
              :if={@editing}
              id="profile-form"
              phx-submit="save"
              class="mt-4 space-y-4"
              data-test="account-edit-form"
            >
              <.input
                field={@form[:display_name]}
                type="text"
                label="Display name"
                data-test="account-display-name-input"
              />
              <.input
                field={@form[:marketing_opt_in]}
                type="checkbox"
                label="Marketing emails"
                data-test="account-marketing-opt-in"
              />
              <div class="flex gap-2">
                <.button type="submit" data-test="account-save-btn">Save</.button>
                <button
                  type="button"
                  phx-click="cancel_edit"
                  class="btn btn-ghost btn-sm"
                  data-test="account-cancel-btn"
                >
                  Cancel
                </button>
              </div>
            </form>
          </div>

          <%!-- Subscription section --%>
          <div class="bg-base-200 rounded-lg p-6">
            <h3 class="text-lg font-medium">Subscription</h3>
            <p class="mt-2" data-test="account-subscription-status">
              <span class="text-base-content/60">Status:</span>
              <span class={"badge #{subscription_badge_class(@viewer.subscription_status)}"}>
                {@viewer.subscription_status}
              </span>
            </p>
            <p :if={@viewer.subscription_expires_at} class="mt-1 text-sm text-base-content/60">
              Expires: {Calendar.strftime(@viewer.subscription_expires_at, "%B %d, %Y")}
            </p>
          </div>

          <%!-- Danger zone --%>
          <div
            :if={!@impersonating_viewer}
            class="bg-base-200 rounded-lg p-6 border border-error/30"
          >
            <h3 class="text-lg font-medium text-error">Danger Zone</h3>
            <p class="mt-2 text-sm text-base-content/60">
              Deleting your account is permanent. All your data will be removed.
            </p>
            <button
              phx-click="delete_account"
              data-confirm="Are you sure you want to delete your account? This cannot be undone."
              class="btn btn-error btn-sm mt-3"
              data-test="account-delete-btn"
            >
              Delete my account
            </button>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp subscription_badge_class("active"), do: "badge-success"
  defp subscription_badge_class("trial"), do: "badge-info"
  defp subscription_badge_class("past_due"), do: "badge-warning"
  defp subscription_badge_class("canceled"), do: "badge-error"
  defp subscription_badge_class(_), do: "badge-ghost"
end
