defmodule BobineWeb.Super.DashboardLive do
  use BobineWeb, :live_view

  alias Bobine.Admin

  @impl true
  def mount(_params, _session, socket) do
    stats = Admin.platform_stats()

    {:ok,
     socket
     |> assign(:page_title, "Platform Dashboard")
     |> assign(:current_path, "/super")
     |> assign(:current_user, socket.assigns.current_scope.user)
     |> assign(:stats, stats)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <BobineWeb.Components.SuperLayout.super_layout
      current_path={@current_path}
      current_user={@current_user}
      flash={@flash}
    >
      <.header>Platform Dashboard</.header>

      <div class="mt-8 grid grid-cols-2 gap-6 lg:grid-cols-4">
        <.stat_card
          label="Organizations"
          value={@stats.total_organizations}
          data_test="stat-total-orgs"
        />
        <.stat_card label="Users" value={@stats.total_users} data_test="stat-total-users" />
        <.stat_card label="Videos" value={@stats.total_videos} data_test="stat-total-videos" />
        <.stat_card
          label="Subscribers"
          value={@stats.total_subscribers}
          data_test="stat-total-subscribers"
        />
      </div>
    </BobineWeb.Components.SuperLayout.super_layout>
    """
  end

  attr :label, :string, required: true
  attr :value, :integer, required: true
  attr :data_test, :string, required: true

  defp stat_card(assigns) do
    ~H"""
    <div
      class="rounded-lg border border-base-300 bg-base-200 p-6"
      data-test={@data_test}
    >
      <p class="text-sm text-base-content/60">{@label}</p>
      <p class="mt-1 text-3xl font-bold text-base-content">{@value}</p>
    </div>
    """
  end
end
