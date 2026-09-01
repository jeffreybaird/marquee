defmodule MarqueeWeb.Viewer.RegisterLive do
  @moduledoc """
  Viewer registration page. Email + display name form with live validation.
  On success, sends a magic link for email verification.

  Events: validate, save
  Route: /register (viewer_auth session)
  """

  use MarqueeWeb, :live_view

  alias Marquee.Viewers
  alias MarqueeWeb.Components.ViewerLayout

  @impl true
  def mount(_params, _session, socket) do
    org = socket.assigns[:organization]
    changeset = if org, do: Viewers.change_viewer_registration(org), else: nil

    {:ok,
     socket
     |> assign(:page_title, "Register")
     |> assign(:check_email, false)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"viewer" => viewer_params}, socket) do
    org = socket.assigns.organization
    changeset = Viewers.change_viewer_registration(org, viewer_params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  @impl true
  def handle_event("save", %{"viewer" => viewer_params}, socket) do
    org = socket.assigns.organization

    case Viewers.register_viewer(org, viewer_params) do
      {:ok, viewer} ->
        Viewers.deliver_viewer_magic_link(org, viewer.email)

        {:noreply,
         socket
         |> assign(:check_email, true)
         |> put_flash(:info, "Check your email for a sign-in link.")}

      {:error, :validation, changeset} ->
        if has_email_taken_error?(changeset) do
          email = Ecto.Changeset.get_field(changeset, :email)
          Viewers.ViewerNotifier.deliver_already_registered(email, org)

          {:noreply,
           socket
           |> assign(:check_email, true)
           |> put_flash(:info, "Check your email for a sign-in link.")}
        else
          {:noreply, assign_form(socket, changeset)}
        end
    end
  end

  defp has_email_taken_error?(changeset) do
    Enum.any?(changeset.errors, fn
      {_field, {_msg, opts}} -> Keyword.get(opts, :constraint) == :unique
      _ -> false
    end)
  end

  defp assign_form(socket, nil), do: assign(socket, :form, nil)

  defp assign_form(socket, %Ecto.Changeset{} = changeset),
    do: assign(socket, :form, to_form(changeset))

  @impl true
  def render(assigns) do
    ~H"""
    <ViewerLayout.viewer_layout
      organization={@organization}
      current_viewer={@current_viewer}
      impersonating_viewer={@impersonating_viewer}
      current_path="/register"
      theme={@theme}
      flash={@flash}
    >
      <div class="max-w-md mx-auto px-4 py-8 sm:px-6 lg:px-8">
        <.header>
          Create your account
          <:subtitle>
            {if @organization, do: "on #{@organization.name}", else: ""}
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
          :if={!@check_email && @form}
          id="register-form"
          phx-change="validate"
          phx-submit="save"
          data-test="register-form"
          class="mt-6 space-y-4"
        >
          <.input
            field={@form[:email]}
            type="email"
            label="Email"
            required
            data-test="register-email-input"
          />
          <.input
            field={@form[:display_name]}
            type="text"
            label="Display name (optional)"
            data-test="register-display-name-input"
          />
          <.input
            field={@form[:marketing_opt_in]}
            type="checkbox"
            label="Send me updates and announcements"
            data-test="register-marketing-opt-in"
          />
          <.button
            phx-disable-with="Creating account..."
            class="w-full"
            data-test="register-submit-btn"
          >
            Create account
          </.button>
        </form>

        <p class="mt-4 text-center text-sm text-base-content/60">
          Already have an account?
          <.link navigate={~p"/login"} class="font-semibold text-primary hover:underline">
            Sign in
          </.link>
        </p>
      </div>
    </ViewerLayout.viewer_layout>
    """
  end
end
