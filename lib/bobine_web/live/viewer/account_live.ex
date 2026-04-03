defmodule BobineWeb.Viewer.AccountLive do
  use BobineWeb, :live_view

  alias Bobine.Billing
  alias Bobine.Viewers
  alias BobineWeb.Components.ViewerLayout

  @impl true
  def mount(_params, _session, socket) do
    viewer = socket.assigns.current_viewer
    org = socket.assigns.organization
    changeset = Viewers.Viewer.profile_changeset(viewer, %{})

    subscription = load_subscription(org, viewer)

    {:ok,
     socket
     |> assign(:page_title, "Account")
     |> assign(:viewer, viewer)
     |> assign(:subscription, subscription)
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
  def handle_event("manage_subscription", _params, socket) do
    org = socket.assigns.organization
    viewer = socket.assigns.viewer

    case Billing.create_viewer_portal_session(org, viewer) do
      {:ok, session} ->
        {:noreply, redirect(socket, external: session.url)}

      {:error, :stripe_not_connected} ->
        {:noreply, put_flash(socket, :error, "Subscription management is not available.")}

      {:error, :stripe_error, _} ->
        {:noreply, put_flash(socket, :error, "Something went wrong. Please try again.")}
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

  defp load_subscription(org, viewer) do
    case Billing.get_active_viewer_subscription(org, viewer) do
      {:ok, sub} -> sub
      {:error, :not_found} -> nil
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <ViewerLayout.viewer_layout
      organization={@organization}
      current_viewer={@current_viewer}
      impersonating_viewer={@impersonating_viewer}
      current_path="/account"
      theme={@theme}
      flash={@flash}
    >
      <div class="sv-page-content" style="max-width: 600px">
        <div class="sv-page-header">
          <h1 class="sv-page-title">Account</h1>
        </div>

        <%!-- Profile section --%>
        <div class="sv-account-section">
          <h3 class="sv-account-section-title">Profile</h3>

          <div :if={!@editing}>
            <div class="sv-account-field" data-test="account-email">
              <span class="sv-account-label">Email:</span>
              <span class="sv-account-value">{@viewer.email}</span>
            </div>
            <div class="sv-account-field" data-test="account-display-name">
              <span class="sv-account-label">Display name:</span>
              <span class="sv-account-value">{@viewer.display_name}</span>
            </div>
            <button
              :if={!@impersonating_viewer}
              phx-click="edit"
              class="sv-btn sv-btn-secondary"
              style="margin-top: 12px"
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
                class="sv-btn sv-btn-ghost"
                data-test="account-cancel-btn"
              >
                Cancel
              </button>
            </div>
          </form>
        </div>

        <%!-- Subscription section --%>
        <div class="sv-account-section">
          <h3 class="sv-account-section-title">Subscription</h3>

          <%!-- Active status --%>
          <div :if={@viewer.subscription_status == "active"} data-test="subscription-active-status">
            <div class="sv-account-field" data-test="account-subscription-status">
              <span class="sv-account-label">Status:</span>
              <span class="sv-badge sv-badge-accent">active</span>
            </div>
            <p
              :if={@subscription && @subscription.current_period_end}
              style="font-size: 0.8125rem; color: var(--sv-text-secondary); margin-top: 4px"
            >
              Renews on {Calendar.strftime(@subscription.current_period_end, "%B %d, %Y")}
            </p>
            <button
              :if={@viewer.stripe_customer_id}
              phx-click="manage_subscription"
              class="sv-btn sv-btn-secondary"
              style="margin-top: 12px"
              data-test="manage-subscription-btn"
            >
              Manage subscription
            </button>
          </div>

          <%!-- Trialing status --%>
          <div :if={@viewer.subscription_status == "trial"} data-test="subscription-trial-status">
            <div class="sv-account-field" data-test="account-subscription-status">
              <span class="sv-account-label">Status:</span>
              <span class="sv-badge sv-badge-accent">free trial</span>
            </div>
            <p
              :if={@viewer.trial_expires_at}
              style="font-size: 0.8125rem; color: var(--sv-text-secondary); margin-top: 4px"
            >
              Trial ends {Calendar.strftime(@viewer.trial_expires_at, "%B %d, %Y")}
            </p>
            <button
              :if={@viewer.stripe_customer_id}
              phx-click="manage_subscription"
              class="sv-btn sv-btn-secondary"
              style="margin-top: 12px"
              data-test="manage-subscription-btn"
            >
              Add payment method
            </button>
          </div>

          <%!-- Past due status --%>
          <div
            :if={@viewer.subscription_status == "past_due"}
            data-test="subscription-past-due-status"
          >
            <div class="sv-account-field" data-test="account-subscription-status">
              <span class="sv-account-label">Status:</span>
              <span class="sv-badge" style="background: #ff5050; color: #fff">past due</span>
            </div>
            <p style="font-size: 0.8125rem; color: #ff5050; margin-top: 4px">
              Your last payment didn't go through. Update your payment method to keep access.
            </p>
            <button
              :if={@viewer.stripe_customer_id}
              phx-click="manage_subscription"
              class="sv-btn sv-btn-accent"
              style="margin-top: 12px"
              data-test="update-payment-btn"
            >
              Update payment method
            </button>
          </div>

          <%!-- Canceled status --%>
          <div
            :if={@viewer.subscription_status == "canceled"}
            data-test="subscription-canceled-status"
          >
            <div class="sv-account-field" data-test="account-subscription-status">
              <span class="sv-account-label">Status:</span>
              <span class="sv-badge">canceled</span>
            </div>
            <p
              :if={@viewer.subscription_expires_at}
              style="font-size: 0.8125rem; color: var(--sv-text-secondary); margin-top: 4px"
            >
              Your subscription ended on {Calendar.strftime(
                @viewer.subscription_expires_at,
                "%B %d, %Y"
              )}
            </p>
            <a
              href="/subscribe"
              class="sv-btn sv-btn-accent"
              style="margin-top: 12px; display: inline-block"
              data-test="resubscribe-link"
            >
              Resubscribe
            </a>
          </div>

          <%!-- No subscription --%>
          <div
            :if={@viewer.subscription_status in ["none", "expired"]}
            data-test="subscription-none-status"
          >
            <div class="sv-account-field" data-test="account-subscription-status">
              <span class="sv-account-label">Status:</span>
              <span class="sv-badge">{@viewer.subscription_status}</span>
            </div>
            <a
              href="/subscribe"
              class="sv-btn sv-btn-accent"
              style="margin-top: 12px; display: inline-block"
              data-test="subscribe-link"
            >
              Subscribe to start watching
            </a>
          </div>
        </div>

        <%!-- Danger zone --%>
        <div
          :if={!@impersonating_viewer}
          class="sv-account-section"
          style="border: 1px solid rgba(255, 80, 80, 0.3)"
        >
          <h3 class="sv-account-section-title" style="color: #ff5050">Danger Zone</h3>
          <p style="font-size: 0.875rem; color: var(--sv-text-secondary); margin-bottom: 12px">
            Deleting your account is permanent. All your data will be removed.
          </p>
          <button
            phx-click="delete_account"
            data-confirm="Are you sure you want to delete your account? This cannot be undone."
            class="sv-btn"
            style="background: #ff5050; color: #fff"
            data-test="account-delete-btn"
          >
            Delete my account
          </button>
        </div>
      </div>
    </ViewerLayout.viewer_layout>
    """
  end
end
