defmodule BobineWeb.Super.OrganizationEditLive do
  use BobineWeb, :live_view

  alias Bobine.Admin

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    org = Admin.get_organization!(id)

    form_params = %{
      "name" => org.name,
      "slug" => org.slug,
      "custom_domain" => org.custom_domain || ""
    }

    {:ok,
     socket
     |> assign(:page_title, "Edit #{org.name}")
     |> assign(:current_path, "/super/organizations")
     |> assign(:current_user, socket.assigns.current_scope.user)
     |> assign(:org, org)
     |> assign(:form, to_form(form_params))}
  end

  @impl true
  def handle_event("validate", params, socket) do
    {:noreply, assign(socket, :form, to_form(params))}
  end

  @impl true
  def handle_event("save", params, socket) do
    %{"name" => name, "slug" => slug, "custom_domain" => custom_domain} = params

    attrs = %{
      name: name,
      slug: slug,
      custom_domain: presence(custom_domain)
    }

    case Admin.update_organization(socket.assigns.org, attrs) do
      {:ok, org} ->
        {:noreply,
         socket
         |> put_flash(:info, "Organization updated.")
         |> redirect(to: ~p"/super/organizations/#{org.id}")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset_to_params(changeset, params)))}
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
      <.header>Edit {@org.name}</.header>

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
          </div>

          <div class="mt-6 flex gap-3">
            <.button type="submit" data-test="save-org-btn">Save Changes</.button>
            <.link navigate={~p"/super/organizations/#{@org.id}"} class="btn btn-ghost">
              Cancel
            </.link>
          </div>
        </.form>
      </div>
    </BobineWeb.Components.SuperLayout.super_layout>
    """
  end

  defp presence(""), do: nil
  defp presence(val), do: val

  defp changeset_to_params(changeset, original_params) do
    Ecto.Changeset.apply_changes(changeset)
    |> Map.from_struct()
    |> Enum.into(original_params, fn {k, v} -> {Atom.to_string(k), v} end)
  end
end
