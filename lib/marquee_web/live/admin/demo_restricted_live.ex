defmodule MarqueeWeb.Admin.DemoRestrictedLive do
  @moduledoc "Explains unavailable external services in the private admin demo."
  use MarqueeWeb, :live_view
  def mount(_, _, socket), do: {:ok, assign(socket, :page_title, "Demo restrictions")}

  def render(assigns) do
    ~H"""
    <MarqueeWeb.Components.AdminLayout.admin_layout
      current_path="/admin/demo/restricted"
      organization={@organization}
      current_user={@current_user}
    >
      <section data-test="admin-demo-restricted">
        <h1 class="text-3xl">Explore safely in your private demo</h1>
        <p class="my-4">
          Payments, uploads, invitations, webhooks, DNS changes and live broadcasts are unavailable. Edit your catalog, collections and branding, or try the approved travel library.
        </p>
        <.link
          href="/admin"
          class="inline-flex min-h-11 items-center rounded px-2 underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2"
        >
          Back to dashboard
        </.link>
      </section>
    </MarqueeWeb.Components.AdminLayout.admin_layout>
    """
  end
end
