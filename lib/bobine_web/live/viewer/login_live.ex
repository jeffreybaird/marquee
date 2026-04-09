defmodule BobineWeb.Viewer.LoginLive do
  @moduledoc """
  Viewer magic-link login page. Collects email and sends a magic link.
  Shows a confirmation message regardless of whether the email exists.

  Renders the polished `sv-auth-shell` layout. When the org's theme has a
  `login_background_image_url`, it is used as the full-bleed background;
  otherwise a branded gradient derived from the theme accent is shown.

  Events: send_magic_link
  Route: /login (viewer_auth session)
  """

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
    assigns = assign(assigns, :bg_image, safe_bg_url(theme_bg_image(assigns[:theme])))

    ~H"""
    <ViewerLayout.viewer_layout
      organization={@organization}
      current_viewer={@current_viewer}
      impersonating_viewer={@impersonating_viewer}
      current_path="/login"
      theme={@theme}
      flash={@flash}
    >
      <section
        class={["sv-auth-shell", @bg_image && "has-bg-image"]}
        style={@bg_image && "--sv-auth-bg-image: url('#{@bg_image}')"}
        data-test="login-shell"
      >
        <div class="sv-auth-card" data-test="login-card">
          <div class="sv-auth-brand">
            <img
              :if={theme_logo_url(@theme)}
              src={theme_logo_url(@theme)}
              alt={"#{@organization && @organization.name} logo"}
              class="sv-auth-logo"
              data-test="login-logo"
            />
            <p :if={@organization} class="sv-auth-org-name" data-test="login-org-name">
              {@organization.name}
            </p>
          </div>

          <h1 class="sv-auth-heading">Sign in</h1>
          <p class="sv-auth-subtitle">
            We'll email you a secure link to sign in. No password required.
          </p>

          <div
            :if={@check_email}
            class="sv-auth-notice"
            role="status"
            aria-live="polite"
            data-test="check-email-message"
          >
            <.icon name="hero-envelope" class="size-5 sv-auth-notice-icon" />
            <p>Check your email for a sign-in link.</p>
          </div>

          <form
            :if={!@check_email}
            id="login-form"
            phx-submit="send_magic_link"
            class="sv-auth-form"
            data-test="login-form"
          >
            <div class="sv-auth-field">
              <label for="email" class="sv-auth-label">Email address</label>
              <input
                type="email"
                name="email"
                id="email"
                required
                autocomplete="email"
                spellcheck="false"
                placeholder="you@example.com"
                class="sv-auth-input"
                data-test="login-email-input"
                phx-mounted={JS.focus()}
              />
            </div>

            <button
              type="submit"
              phx-disable-with="Sending magic link…"
              class="sv-auth-submit"
              data-test="login-submit-btn"
            >
              Send magic link <span aria-hidden="true">→</span>
            </button>
          </form>

          <p class="sv-auth-footer">
            Don't have an account?
            <.link navigate={~p"/register"} data-test="login-register-link">
              Create one
            </.link>
          </p>
        </div>
      </section>
    </ViewerLayout.viewer_layout>
    """
  end

  defp theme_bg_image(%Bobine.Branding.Theme{login_background_image_url: url}), do: url
  defp theme_bg_image(_), do: nil

  defp theme_logo_url(%Bobine.Branding.Theme{logo_url: url}) when is_binary(url) and url != "",
    do: url

  defp theme_logo_url(_), do: nil

  # Validate the URL strictly so it can be safely interpolated into a CSS
  # `url('...')` value. Reject anything containing characters that could
  # break out of the CSS string or function (quotes, parens, semicolons,
  # whitespace, angle brackets, backslashes).
  defp safe_bg_url(url) when is_binary(url) do
    trimmed = String.trim(url)

    if trimmed != "" and Regex.match?(~r/^https?:\/\/[^\s'"<>(){};\\]+$/, trimmed) do
      trimmed
    end
  end

  defp safe_bg_url(_), do: nil
end
