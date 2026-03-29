defmodule BobineWeb.Super.OrganizationNewLive do
  use BobineWeb, :live_view

  alias Bobine.Admin
  alias Bobine.Accounts
  alias Bobine.Accounts.Organization

  @impl true
  def mount(_params, _session, socket) do
    changeset = Organization.changeset(%Organization{}, %{})

    {:ok,
     socket
     |> assign(:page_title, "New Organization")
     |> assign(:current_path, "/super/organizations/new")
     |> assign(:current_user, socket.assigns.current_scope.user)
     |> assign(:owner_email, "")
     |> assign(:form, to_form(changeset, as: "org"))}
  end

  @impl true
  def handle_event("validate", %{"org" => params} = event_params, socket) do
    owner_email = Map.get(event_params, "owner_email", socket.assigns.owner_email)

    slug =
      if params["slug"] == auto_slug(socket.assigns.form.source.changes[:name] |> to_string()) do
        auto_slug(params["name"])
      else
        params["slug"]
      end

    changeset =
      Organization.changeset(%Organization{}, Map.put(params, "slug", slug))
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:form, to_form(changeset, as: "org"))
     |> assign(:owner_email, owner_email)}
  end

  @impl true
  def handle_event("save", %{"org" => org_params, "owner_email" => owner_email}, socket) do
    with {:ok, org} <- Admin.create_organization(org_params),
         {:ok, user} <- find_or_create_user(owner_email),
         {:ok, _membership} <- Admin.create_owner_membership(org, user) do
      {:noreply,
       socket
       |> put_flash(:info, "Organization created.")
       |> redirect(to: ~p"/super/organizations/#{org.id}")}
    else
      {:error, :already_has_owner} ->
        {:noreply, put_flash(socket, :error, "That organization already has an owner.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: "org"))}
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
      <.header>New Organization</.header>

      <div class="mt-8 max-w-lg">
        <.form for={@form} phx-change="validate" phx-submit="save">
          <div class="space-y-4">
            <.input
              field={@form[:name]}
              type="text"
              label="Name"
              required
              data-test="org-name-input"
            />
            <.input
              field={@form[:slug]}
              type="text"
              label="Slug"
              required
              data-test="org-slug-input"
            />
            <.input
              field={@form[:custom_domain]}
              type="text"
              label="Custom Domain (optional)"
              data-test="org-domain-input"
            />
            <.input
              type="email"
              name="owner_email"
              value={@owner_email}
              label="Owner Email"
              required
              data-test="owner-email-input"
            />
          </div>

          <div class="mt-6 flex gap-3">
            <.button type="submit" data-test="create-org-btn">Create Organization</.button>
            <.link navigate={~p"/super/organizations"} class="btn btn-ghost">
              Cancel
            </.link>
          </div>
        </.form>
      </div>
    </BobineWeb.Components.SuperLayout.super_layout>
    """
  end

  defp auto_slug(nil), do: ""
  defp auto_slug(""), do: ""

  defp auto_slug(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s-]/, "")
    |> String.replace(~r/\s+/, "-")
    |> String.trim("-")
  end

  defp find_or_create_user(email) do
    case Accounts.get_user_by_email(email) do
      nil -> Accounts.register_user(%{email: email})
      user -> {:ok, user}
    end
  end
end
