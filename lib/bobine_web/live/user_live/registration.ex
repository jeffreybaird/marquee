defmodule BobineWeb.UserLive.Registration do
  use BobineWeb, :live_view

  alias Bobine.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-sm">
        <div class="text-center">
          <.header>
            Register for an account
            <:subtitle>
              Already registered?
              <.link navigate={~p"/users/log-in"} class="font-semibold text-brand hover:underline">
                Log in
              </.link>
              to your account now.
            </:subtitle>
          </.header>
        </div>

        <.form for={@form} id="registration_form" phx-submit="save" phx-change="validate">
          <.input
            field={@form[:organization_name]}
            type="text"
            label="Organization name"
            autocomplete="organization"
            required
            phx-mounted={JS.focus()}
            data-test="registration-org-name"
          />
          <.input
            field={@form[:email]}
            type="email"
            label="Email"
            autocomplete="username"
            spellcheck="false"
            required
            data-test="registration-email"
          />

          <.button
            phx-disable-with="Creating account..."
            class="btn btn-primary w-full"
            data-test="registration-submit"
          >
            Create an account
          </.button>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, %{assigns: %{current_scope: %{user: user}}} = socket)
      when not is_nil(user) do
    {:ok, redirect(socket, to: BobineWeb.UserAuth.signed_in_path(socket))}
  end

  def mount(_params, _session, socket) do
    changeset = Accounts.registration_changeset(%{})
    {:ok, assign(socket, form: to_form(changeset, as: "user")), temporary_assigns: [form: nil]}
  end

  @impl true
  def handle_event("save", %{"user" => params}, socket) do
    changeset =
      Accounts.registration_changeset(params)
      |> Map.put(:action, :validate)

    if changeset.valid? do
      org_name = params["organization_name"]

      case Accounts.register_user_with_organization(params, org_name) do
        {:ok, user} ->
          {:ok, _} =
            Accounts.deliver_login_instructions(
              user,
              &url(~p"/users/log-in/#{&1}")
            )

          {:noreply,
           socket
           |> put_flash(
             :info,
             "An email was sent to #{user.email}, please access it to confirm your account."
           )
           |> push_navigate(to: ~p"/users/log-in")}

        {:error, :validation, %Ecto.Changeset{} = user_changeset} ->
          # Merge user changeset errors back into our registration form
          merged =
            Accounts.registration_changeset(params)
            |> Accounts.merge_registration_errors(user_changeset)
            |> Map.put(:action, :validate)

          {:noreply, assign(socket, form: to_form(merged, as: "user"))}
      end
    else
      {:noreply, assign(socket, form: to_form(changeset, as: "user"))}
    end
  end

  def handle_event("validate", %{"user" => params}, socket) do
    changeset =
      Accounts.registration_changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset, as: "user"))}
  end
end
