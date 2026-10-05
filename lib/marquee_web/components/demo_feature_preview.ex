defmodule MarqueeWeb.Components.DemoFeaturePreview do
  @moduledoc "Read-only examples of services that cannot be connected in a private demo."
  use MarqueeWeb, :html

  @doc """
  Assigns a static preview without loading provider-backed state.

      iex> socket = %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}}}
      iex> {:ok, preview} = MarqueeWeb.Components.DemoFeaturePreview.mount(socket, :plans)
      iex> {preview.assigns.page_title, length(preview.assigns.demo_rows)}
      {"Plans", 2}
  """
  def mount(socket, feature) do
    {title, description, action, rows} = content(feature)
    rows = viewer_rows(feature, socket.assigns[:current_viewer], rows)

    {:ok,
     Phoenix.Component.assign(socket,
       demo_feature: feature,
       page_title: title,
       demo_description: description,
       demo_action: action,
       demo_rows: rows
     )}
  end

  def render(%{demo_feature: feature} = assigns) when feature in [:account, :subscribe] do
    ~H"""
    <MarqueeWeb.Components.ViewerLayout.viewer_layout
      organization={@organization}
      current_viewer={@current_viewer}
      impersonating_viewer={@impersonating_viewer}
      current_path={@current_path}
      theme={@theme}
      flash={@flash}
    >
      <div class="sv-page-content"><.preview_content {assigns} /></div>
    </MarqueeWeb.Components.ViewerLayout.viewer_layout>
    """
  end

  def render(assigns) do
    ~H"""
    <MarqueeWeb.Components.AdminLayout.admin_layout
      current_path={@current_path}
      organization={@organization}
      current_user={@current_user}
      flash={@flash}
    >
      <.preview_content {assigns} />
    </MarqueeWeb.Components.AdminLayout.admin_layout>
    """
  end

  defp preview_content(assigns) do
    ~H"""
    <section class="space-y-6" data-test="admin-demo-feature-sample">
      <div class="flex flex-wrap items-start justify-between gap-4">
        <div>
          <p class="text-sm font-ui uppercase tracking-wider text-admin-muted">
            Sample · Read-only preview
          </p>
          <h1 class="text-3xl font-display mt-2">{@page_title}</h1>
        </div>
        <button
          disabled
          data-test="admin-demo-feature-action"
          class="min-h-11 rounded border border-admin-border px-4 py-2 opacity-60"
        >
          {@demo_action}
        </button>
      </div>
      <p class="max-w-3xl text-admin-muted">
        {@demo_description} External actions are disabled in this private demo.
      </p>
      <div class="grid gap-4 sm:grid-cols-2">
        <article
          :for={{title, detail, status} <- @demo_rows}
          data-test="admin-demo-feature-row"
          class="rounded-lg border border-admin-border bg-admin-card p-5 space-y-3"
        >
          <h2 class="font-display text-xl">{title}</h2>
          <p>{detail}</p>
          <span class="inline-block rounded-full border border-admin-border px-3 py-1 text-sm font-ui">
            {status}
          </span>
        </article>
      </div>
      <div class="flex flex-wrap gap-3">
        <.link
          href="/admin/members"
          class="inline-flex min-h-11 items-center rounded px-3 underline focus-visible:outline-2"
        >
          Explore sample members
        </.link>
        <.link
          href="/admin/podcasts"
          class="inline-flex min-h-11 items-center rounded px-3 underline focus-visible:outline-2"
        >
          Edit podcast shows
        </.link>
        <.link
          href="/admin/content"
          class="inline-flex min-h-11 items-center rounded px-3 underline focus-visible:outline-2"
        >
          Edit your catalog
        </.link>
      </div>
    </section>
    """
  end

  defp viewer_rows(feature, viewer, _rows)
       when feature in [:account, :subscribe] and not is_nil(viewer) do
    [
      {viewer.display_name || "Sample member", viewer.email, "Sample · Read-only"},
      {"Membership", "Access: #{viewer.subscription_status}", "Account: #{viewer.status}"}
    ]
  end

  defp viewer_rows(_, _, rows), do: rows

  defp content(:plans),
    do:
      {"Plans", "Offer monthly and annual access to your video library.",
       "Connect Stripe to create a plan",
       [
         {"Explorer Monthly", "$12 / month · Full travel catalog", "Sample plan"},
         {"Explorer Annual", "$120 / year · Two months included", "Sample plan"}
       ]}

  defp content(:coupons),
    do:
      {"Coupons", "Create promotions for new subscribers and seasonal campaigns.",
       "Create coupon",
       [
         {"WELCOME20", "20% off the first month", "Sample · One-time discount"},
         {"TRAVEL30", "$30 off an annual membership", "Sample · Limited campaign"}
       ]}

  defp content(:webhooks),
    do:
      {"Webhooks", "Send subscription and content updates to your connected systems.",
       "Add endpoint",
       [
         {"Membership updates", "subscription.created · subscription.canceled",
          "Sample endpoint · No deliveries"},
         {"Catalog updates", "video.published · video.updated", "Sample endpoint · Not connected"}
       ]}

  defp content(:live),
    do:
      {"Live Events", "Schedule a premiere, notify your audience, and broadcast live.",
       "Schedule broadcast",
       [
         {"Postcards from Portugal", "A sample live travel Q&A · 45 minutes",
          "Sample · Scheduled"},
         {"Behind the Journey", "A conversation with the filmmakers · 30 minutes",
          "Sample · Draft"}
       ]}

  defp content(:billing),
    do:
      {"Billing", "Review the platform plan and usage for a growing video business.",
       "Manage billing",
       [
         {"Creator plan", "Sample subscription · Monthly billing", "Demo · No charges"},
         {"Catalog usage", "Private travel library and sample members", "Sample usage"}
       ]}

  defp content(:settings),
    do:
      {"Settings", "Connect payments and manage organization settings in your own workspace.",
       "Connect Stripe",
       [
         {"Payments", "Accept viewer subscriptions through Stripe Connect", "Not connected"},
         {"Workspace", "This private demo expires automatically", "Temporary sample workspace"}
       ]}

  defp content(:landing),
    do:
      {"Landing Page", "Arrange a branded welcome page for prospective subscribers.",
       "Publish landing page",
       [
         {"Your next adventure starts here", "Hero image, headline, and catalog invitation",
          "Sample hero section"},
         {"Explore the collection", "Featured journeys and membership benefits",
          "Sample content section"}
       ]}

  defp content(:account),
    do:
      {"Account",
       "Preview member profile and membership options without changing login or billing details.",
       "Manage subscription",
       [
         {"Member profile", "Your selected sample member stays read-only", "Sample identity"},
         {"Membership", "Access reflects the selected member's local status",
          "No billing connection"}
       ]}

  defp content(:subscribe),
    do:
      {"Subscription",
       "This sample member needs access to watch subscriber content. Grant local access from Members to explore the experience.",
       "Subscribe",
       [{"Explorer membership", "Watch the full travel library", "Sample · Checkout disabled"}]}
end
