defmodule BobineWeb.Viewer.HomeLive do
  use BobineWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Home")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {if @organization, do: @organization.name, else: "Welcome"}
      </.header>
      <p class="mt-4 text-base-content/70">Video catalog coming soon.</p>
    </Layouts.app>
    """
  end
end
