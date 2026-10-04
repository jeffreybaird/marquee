defmodule MarqueeWeb.UserLive.Login do
  use MarqueeWeb, :live_view

  alias Marquee.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-sm space-y-4">
        <div class="text-center">
          <.header>
            <p>Log in</p>
            <:subtitle>
              <%= if @current_scope do %>
                You need to reauthenticate to perform sensitive actions on your account.
              <% else %>
                Don't have an account? <.link
                  navigate={~p"/users/register"}
                  class="font-semibold text-brand hover:underline"
                  phx-no-format
                >Sign up</.link> for an account now.
              <% end %>
            </:subtitle>
          </.header>
        </div>

        <div :if={dev_mailbox_available?()} class="alert alert-info">
          <.icon name="hero-information-circle" class="size-6 shrink-0" />
          <div>
            <p>You are running the local mail adapter.</p>
            <p>
              To see sent emails, visit <.link href="/dev/mailbox" class="underline">the mailbox page</.link>.
            </p>
          </div>
        </div>

        <.form
          :let={f}
          for={@form}
          id="login_form_magic"
          action={~p"/users/log-in"}
          phx-submit="submit_magic"
          phx-change="validate"
        >
          <.input
            readonly={!!@current_scope}
            field={f[:email]}
            type="email"
            label="Email"
            autocomplete="username"
            spellcheck="false"
            required
            phx-mounted={JS.focus()}
          />
          <.button class="btn btn-primary w-full">
            Log in with email <span aria-hidden="true">→</span>
          </.button>
        </.form>

        <div class="divider">or</div>

        <.form
          :let={f}
          for={@form}
          id="login_form_password"
          action={~p"/users/log-in"}
          phx-submit="submit_password"
          phx-change="validate"
          phx-trigger-action={@trigger_submit}
        >
          <.input
            readonly={!!@current_scope}
            field={f[:email]}
            type="email"
            label="Email"
            autocomplete="username"
            spellcheck="false"
            required
          />
          <.input
            field={@form[:password]}
            type="password"
            label="Password"
            autocomplete="current-password"
            spellcheck="false"
          />
          <.button class="btn btn-primary w-full" name={@form[:remember_me].name} value="true">
            Log in and stay logged in <span aria-hidden="true">→</span>
          </.button>
          <.button class="btn btn-primary btn-soft w-full mt-2">
            Log in only this time
          </.button>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    email =
      Phoenix.Flash.get(socket.assigns.flash, :email) ||
        get_in(socket.assigns, [:current_scope, Access.key(:user), Access.key(:email)])

    form = to_form(%{"email" => email}, as: "user")

    org =
      if Application.get_env(:marquee, :org_resolution) == :hostname do
        uri = Phoenix.LiveView.get_connect_info(socket, :uri) || socket.host_uri

        case MarqueeWeb.OrgURL.resolve_host(uri && uri.host) do
          {:ok, org} -> org
          _ -> nil
        end
      end

    {:ok, assign(socket, form: form, trigger_submit: false, login_organization: org)}
  end

  @impl true
  def handle_event("validate", %{"user" => user_params}, socket) do
    form = to_form(user_params, as: "user")
    {:noreply, assign(socket, form: form)}
  end

  @impl true
  def handle_event("submit_password", _params, socket) do
    {:noreply, assign(socket, :trigger_submit, true)}
  end

  def handle_event("submit_magic", %{"user" => %{"email" => email}}, socket) do
    if user = Accounts.get_user_by_email(email) do
      org = socket.assigns[:login_organization] || Accounts.get_user_primary_organization(user)

      url_fun =
        case org do
          nil -> &url(~p"/users/log-in/#{&1}")
          org -> &MarqueeWeb.OrgURL.org_url(login_base_url() <> ~p"/users/log-in/#{&1}", org)
        end

      Accounts.deliver_login_instructions(user, url_fun)
    end

    info =
      "If your email is in our system, you will receive instructions for logging in shortly."

    {:noreply,
     socket
     |> put_flash(:info, info)
     |> push_navigate(to: ~p"/users/log-in")}
  end

  defp login_base_url do
    config = Application.get_env(:marquee, MarqueeWeb.Endpoint, [])[:url] || []

    %{
      URI.new!("#{config[:scheme] || "http"}://#{config[:host] || "localhost"}")
      | port: config[:port]
    }
    |> URI.to_string()
  end

  # The banner links to /dev/mailbox, which the router mounts only when
  # :dev_routes is set (dev). It must never render in prod — where the mailer
  # can also fall back to the local adapter — so gate on both the dev-routes
  # flag and the local adapter actually being in use.
  defp dev_mailbox_available? do
    Application.get_env(:marquee, :dev_routes, false) and local_mail_adapter?()
  end

  defp local_mail_adapter? do
    Application.get_env(:marquee, Marquee.Mailer)[:adapter] == Swoosh.Adapters.Local
  end
end
