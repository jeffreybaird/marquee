defmodule MarqueeWeb.Admin.DashboardNudges do
  @moduledoc """
  Setup-nudge catalog for the operator dashboard.

  A nudge points an operator at an incomplete setup step — Stripe payouts,
  a subscription plan, branding, a homepage catalog. Each nudge is keyed so a
  per-user dismissal can suppress it. A nudge whose underlying step is
  complete never appears, dismissed or not.

  Pure — gathering the conditions (which hits contexts) lives in the LiveView.
  """

  @type condition_key :: :stripe_connected | :has_plans | :has_theme | :has_catalog_rows

  @type nudge :: %{
          key: String.t(),
          condition: condition_key(),
          title: String.t(),
          body: String.t(),
          cta_label: String.t(),
          cta_path: String.t()
        }

  @catalog [
    %{
      key: "connect_stripe",
      condition: :stripe_connected,
      title: "Connect Stripe to accept payments",
      body: "Finish Stripe Connect onboarding before you can charge viewers.",
      cta_label: "Set up payments",
      cta_path: "/admin/settings"
    },
    %{
      key: "create_plan",
      condition: :has_plans,
      title: "Create a subscription plan",
      body: "Viewers need at least one active plan before they can subscribe.",
      cta_label: "Add a plan",
      cta_path: "/admin/plans"
    },
    %{
      key: "customize_branding",
      condition: :has_theme,
      title: "Customize your branding",
      body: "Choose colors and fonts so your site matches your brand.",
      cta_label: "Edit appearance",
      cta_path: "/admin/branding"
    },
    %{
      key: "build_catalog",
      condition: :has_catalog_rows,
      title: "Build your homepage",
      body: "Add rows to your homepage so viewers have something to browse.",
      cta_label: "Edit homepage",
      cta_path: "/admin/catalog"
    }
  ]

  @doc """
  The full nudge catalog, in display order.

      iex> MarqueeWeb.Admin.DashboardNudges.catalog() |> Enum.map(& &1.key)
      ["connect_stripe", "create_plan", "customize_branding", "build_catalog"]
  """
  @spec catalog() :: [nudge()]
  def catalog, do: @catalog

  @doc """
  Nudges to show: the setup step is incomplete AND this user has not
  dismissed it.

  `conditions` maps each condition key to whether that step is COMPLETE.
  `dismissed` is the list of nudge keys the user has dismissed. A missing
  condition key is treated as incomplete.

      iex> conds = %{stripe_connected: false, has_plans: true, has_theme: true, has_catalog_rows: true}
      iex> MarqueeWeb.Admin.DashboardNudges.active(conds, []) |> Enum.map(& &1.key)
      ["connect_stripe"]

      iex> conds = %{stripe_connected: false, has_plans: false, has_theme: true, has_catalog_rows: true}
      iex> MarqueeWeb.Admin.DashboardNudges.active(conds, ["connect_stripe"]) |> Enum.map(& &1.key)
      ["create_plan"]

      iex> conds = %{stripe_connected: true, has_plans: true, has_theme: true, has_catalog_rows: true}
      iex> MarqueeWeb.Admin.DashboardNudges.active(conds, [])
      []
  """
  @spec active(map(), [String.t()]) :: [nudge()]
  def active(conditions, dismissed) when is_map(conditions) and is_list(dismissed) do
    Enum.filter(@catalog, fn nudge ->
      incomplete? = Map.get(conditions, nudge.condition) != true
      incomplete? and nudge.key not in dismissed
    end)
  end
end
