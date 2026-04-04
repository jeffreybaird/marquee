defmodule BobineWeb.Super.OrganizationShowLive do
  @moduledoc """
  Organization detail page. Shows memberships, video count, subscriber count,
  and provides impersonation and soft-delete controls.

  Events: soft_delete, restore
  Route: /super/organizations/:id
  """

  use BobineWeb, :live_view

  alias Bobine.Admin

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    org = Admin.get_organization!(id)
    memberships = Admin.list_memberships(org)
    video_count = Admin.video_count(org)
    subscriber_count = Admin.subscriber_count(org)

    {:ok,
     socket
     |> assign(:page_title, org.name)
     |> assign(:current_path, "/super/organizations")
     |> assign(:current_user, socket.assigns.current_scope.user)
     |> assign(:org, org)
     |> assign(:memberships, memberships)
     |> assign(:video_count, video_count)
     |> assign(:subscriber_count, subscriber_count)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <BobineWeb.Components.SuperLayout.super_layout
      current_path={@current_path}
      current_user={@current_user}
      flash={@flash}
    >
      <div class="flex items-start justify-between">
        <.header>
          {@org.name}
          <:subtitle>{@org.slug}</:subtitle>
        </.header>

        <div class="flex gap-3 mt-1">
          <.link navigate={~p"/super/organizations/#{@org.id}/edit"}>
            <.button>Edit</.button>
          </.link>
          <.link
            href={~p"/super/organizations/#{@org.id}/impersonate"}
            method="post"
            data-test="impersonate-btn"
          >
            <.button class="btn-warning">Open as Admin</.button>
          </.link>
        </div>
      </div>

      <div class="mt-8 grid grid-cols-2 gap-4 lg:grid-cols-4">
        <.detail_card label="Custom Domain" value={@org.custom_domain || "None"} />
        <.detail_card label="Members" value={length(@memberships)} />
        <.detail_card label="Videos" value={@video_count} />
        <.detail_card label="Subscribers" value={@subscriber_count} />
      </div>

      <section class="mt-8">
        <h2 class="text-base font-semibold mb-3">Members</h2>
        <table class="table w-full" data-test="members-table">
          <thead>
            <tr>
              <th>Email</th>
              <th>Role</th>
              <th>Joined</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={m <- @memberships} data-test={"member-row-#{m.id}"}>
              <td>{m.user.email}</td>
              <td>
                <span class="badge badge-sm">{m.role}</span>
              </td>
              <td class="text-sm text-base-content/60">
                {Calendar.strftime(m.inserted_at, "%b %d, %Y")}
              </td>
            </tr>
          </tbody>
        </table>

        <p :if={@memberships == []} class="py-4 text-base-content/60" data-test="no-members">
          No members yet.
        </p>
      </section>

      <section :if={@org.themes != []} class="mt-8">
        <h2 class="text-base font-semibold mb-3">Theme</h2>
        <div class="flex gap-2">
          <.color_swatch color={hd(@org.themes).brand_primary} label="Brand Primary" />
          <.color_swatch color={hd(@org.themes).brand_secondary} label="Brand Secondary" />
          <.color_swatch color={hd(@org.themes).background} label="Background" />
          <.color_swatch color={hd(@org.themes).accent} label="Accent" />
        </div>
      </section>
    </BobineWeb.Components.SuperLayout.super_layout>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true

  defp detail_card(assigns) do
    ~H"""
    <div class="rounded-lg border border-base-300 bg-base-200 p-4">
      <p class="text-xs text-base-content/60">{@label}</p>
      <p class="mt-1 font-semibold text-base-content">{@value}</p>
    </div>
    """
  end

  attr :color, :string, required: true
  attr :label, :string, required: true

  defp color_swatch(assigns) do
    ~H"""
    <div class="flex flex-col items-center gap-1">
      <div
        class="w-8 h-8 rounded border border-base-300"
        style={"background-color: #{@color}"}
      >
      </div>
      <span class="text-xs text-base-content/60">{@label}</span>
    </div>
    """
  end
end
