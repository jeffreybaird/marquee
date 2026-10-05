defmodule MarqueeWeb.Components.AdminDemo do
  @moduledoc "Persistent private-demo controls using the existing application design tokens."
  use MarqueeWeb, :html
  attr :organization, :any, required: true

  def bar(assigns) do
    ~H"""
    <aside
      :if={@organization && @organization.demo_kind == :admin_sandbox}
      class="border-b border-admin-border bg-admin-card text-admin-fg font-ui px-4 py-2 flex flex-wrap gap-x-4 gap-y-1 items-center text-sm"
      data-test="admin-demo-bar"
    >
      <strong>Private admin demo · Two-hour sandbox</strong>
      <span>Sample analytics · External services disabled</span>
      <.link
        href="/?preview=member"
        data-test="admin-demo-preview"
        class="inline-flex min-h-11 items-center rounded px-2 underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2"
      >
        Preview viewer site
      </.link>
      <.link
        href="/admin/demo/library"
        class="inline-flex min-h-11 items-center rounded px-2 underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2"
      >
        Travel library
      </.link>
      <.form for={%{}} action="/demo/admin/reset" method="post">
        <button
          data-test="admin-demo-reset"
          class="inline-flex min-h-11 items-center rounded px-2 underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2"
        >
          Reset demo
        </button>
      </.form>
      <.form for={%{}} action="/demo/admin/exit" method="post">
        <button
          data-test="admin-demo-exit"
          class="inline-flex min-h-11 items-center rounded px-2 underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2"
        >
          Exit demo
        </button>
      </.form>
      <a
        href="https://www.pexels.com/"
        target="_blank"
        rel="noopener noreferrer"
        class="inline-flex min-h-11 items-center rounded px-2 underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2"
      >
        Travel footage by Pexels creators
      </a>
    </aside>
    """
  end
end
