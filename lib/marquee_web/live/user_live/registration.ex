defmodule MarqueeWeb.UserLive.Registration do
  use MarqueeWeb, :live_view

  alias Marquee.Accounts
  alias Marquee.Branding.Theme

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-md">
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

          <fieldset class="fieldset mb-4">
            <legend class="label mb-2">Choose a starter theme</legend>
            <div
              class="grid grid-cols-2 gap-3"
              role="radiogroup"
              aria-label="Starter theme"
              data-test="registration-theme-presets"
            >
              <label
                :for={{key, preset} <- @theme_presets}
                class={[
                  "cursor-pointer rounded-lg border-2 p-3 transition",
                  "focus-within:ring-2 focus-within:ring-offset-2 focus-within:ring-primary",
                  if(@form[:theme_preset].value == key,
                    do: "border-primary",
                    else: "border-base-300 hover:border-base-content/40"
                  )
                ]}
                data-test={"registration-theme-preset-#{key}"}
              >
                <input
                  type="radio"
                  name={@form[:theme_preset].name}
                  id={"#{@form[:theme_preset].id}_#{key}"}
                  value={key}
                  checked={@form[:theme_preset].value == key}
                  class="sr-only"
                  required
                />
                <div
                  class="mb-2 h-16 w-full overflow-hidden rounded border border-black/10"
                  style={"background: #{preset.background};"}
                  aria-hidden="true"
                >
                  <div class="flex h-full items-end gap-1 p-2">
                    <span
                      class="block h-6 w-6 rounded-full"
                      style={"background: #{preset.brand_primary};"}
                    >
                    </span>
                    <span
                      class="block h-2 flex-1 rounded"
                      style={"background: #{preset.text_primary};"}
                    >
                    </span>
                  </div>
                </div>
                <div class="text-sm font-semibold">{preset.label}</div>
                <div class="text-xs opacity-70">{preset.description}</div>
              </label>
            </div>
            <p
              :for={msg <- @form[:theme_preset].errors |> Enum.map(&translate_error/1)}
              class="mt-2 text-sm text-error"
            >
              {msg}
            </p>
          </fieldset>

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
    {:ok, redirect(socket, to: MarqueeWeb.UserAuth.signed_in_path(socket))}
  end

  def mount(_params, _session, socket) do
    changeset = Accounts.registration_changeset(%{})

    {:ok,
     socket
     |> assign(form: to_form(changeset, as: "user"))
     |> assign(theme_presets: Theme.presets()), temporary_assigns: [form: nil]}
  end

  @impl true
  def handle_event("save", %{"user" => params}, socket) do
    changeset =
      Accounts.registration_changeset(params)
      |> Map.put(:action, :validate)

    if changeset.valid? do
      org_name = params["organization_name"]
      theme_preset = params["theme_preset"]

      case Accounts.register_user_with_organization(params, org_name, theme_preset) do
        {:ok, user, org} ->
          {:ok, _} =
            Accounts.deliver_login_instructions(
              user,
              &MarqueeWeb.OrgURL.org_url(url(~p"/users/log-in/#{&1}"), org)
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
