defmodule BobineWeb.Viewer.AccountLive do
  use BobineWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Account")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>Account</.header>
      <p class="mt-4 text-base-content/70">Account management coming soon.</p>
    </Layouts.app>
    """
  end
end
