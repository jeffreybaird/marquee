defmodule BobineWeb.Viewer.LoginLive do
  use BobineWeb, :live_view

  alias Bobine.Viewers
  alias BobineWeb.Components.ViewerLayout

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Sign In")
     |> assign(:check_email, false)
     |> assign(:email, "")}
  end

  @impl true
  def handle_event("send_magic_link", %{"email" => email}, socket) do
    org = socket.assigns.organization

    # Always show the same message regardless of whether the email exists
    Viewers.deliver_viewer_magic_link(org, email)

    {:noreply,
     socket
     |> assign(:check_email, true)
     |> put_flash(:info, "Check your email for a sign-in link.")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <ViewerLayout.viewer_layout
      organization={@organization}
      current_viewer={@current_viewer}
      impersonating_viewer={@impersonating_viewer}
      current_path="/login"
      theme={@theme}
      flash={@flash}
    >
      <div class="max-w-md mx-auto px-4 py-8 sm:px-6 lg:px-8">
        <.header>
          Sign in
          <:subtitle>
            {if @organization, do: "to #{@organization.name}", else: ""}
          </:subtitle>
        </.header>

        <div
          :if={@check_email}
          class="mt-6 p-4 bg-base-200 rounded-lg"
          data-test="check-email-message"
        >
          <p class="text-base-content">Check your email for a sign-in link.</p>
        </div>

        <form
          :if={!@check_email}
          id="login-form"
          phx-submit="send_magic_link"
          class="mt-6"
          data-test="login-form"
        >
          <div class="space-y-4">
            <div>
              <label for="email" class="block text-sm font-medium text-base-content">Email</label>
              <input
                type="email"
                name="email"
                id="email"
                required
                class="mt-1 block w-full rounded-md border-base-300 bg-base-100 text-base-content shadow-sm focus:border-primary focus:ring-primary sm:text-sm"
                data-test="login-email-input"
              />
            </div>
            <.button
              type="submit"
              phx-disable-with="Sending..."
              class="w-full"
              data-test="login-submit-btn"
            >
              Send magic link
            </.button>
          </div>
        </form>

        <p class="mt-4 text-center text-sm text-base-content/60">
          Don't have an account?
          <.link navigate={~p"/register"} class="font-semibold text-primary hover:underline">
            Register
          </.link>
        </p>
      </div>
    </ViewerLayout.viewer_layout>
    """
  end
end
