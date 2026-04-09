defmodule Bobine.PlatformBilling do
  @moduledoc """
  Platform-level billing context for organizations subscribing to Bobine.

  This is separate from `Bobine.Billing`, which handles viewer subscriptions
  to individual organizations. Platform billing operates against Bobine's own
  Stripe account (NOT Connect).
  """

  import Ecto.Query, warn: false

  require Logger

  alias Bobine.Accounts.Organization
  alias Bobine.Audit
  alias Bobine.Billing.{PlatformPlan, PlatformSubscription}
  alias Bobine.Events
  alias Bobine.Pagination
  alias Bobine.Repo
  alias BobineWeb.OrgURL

  require Bobine.Otel

  ## -----------------------------------------------------------------------
  ## Plan management (super admin)
  ## -----------------------------------------------------------------------

  @doc """
  Returns a paginated list of active platform plans.

  Exempt from doctest — hits the database.
  """
  def list_platform_plans(opts \\ []) do
    include_inactive = Keyword.get(opts, :include_inactive, false)

    PlatformPlan
    |> then(fn q ->
      if include_inactive, do: q, else: where(q, [p], p.active == true and is_nil(p.deleted_at))
    end)
    |> order_by(asc: :position, asc: :name)
    |> Pagination.paginate(opts)
  end

  @doc """
  Gets a single platform plan by ID.

  Returns `{:ok, plan}` or `{:error, :not_found}`.

  Exempt from doctest — hits the database.
  """
  def get_platform_plan(id) do
    case Repo.get(PlatformPlan, id) do
      nil -> {:error, :not_found}
      plan -> {:ok, plan}
    end
  end

  @doc """
  Gets a single platform plan by ID. Raises on not found.

  Exempt from doctest — hits the database.
  """
  def get_platform_plan!(id), do: Repo.get!(PlatformPlan, id)

  @doc """
  Gets a single platform plan by slug.

  Returns `{:ok, plan}` or `{:error, :not_found}`.

  Exempt from doctest — hits the database.
  """
  def get_platform_plan_by_slug(slug) do
    case Repo.get_by(PlatformPlan, slug: slug) do
      nil -> {:error, :not_found}
      plan -> {:ok, plan}
    end
  end

  @doc """
  Creates a platform plan.

  Exempt from doctest — hits the database.
  """
  def create_platform_plan(attrs) do
    Bobine.Otel.with_span "bobine.platform_billing.create_platform_plan" do
      with {:ok, plan} <- insert_platform_plan(attrs),
           {:ok, plan} <- sync_plan_to_stripe(plan) do
        Events.broadcast(nil, {:platform_plan_created, plan})
        {:ok, plan}
      end
    end
  end

  defp billing_attributes(%PlatformPlan{} = plan) do
    %{
      amount: plan.amount,
      currency: plan.currency,
      interval: plan.interval
    }
  end

  defp product_attributes(%PlatformPlan{} = plan) do
    attrs =
      %{
        name: plan.name,
        metadata: %{platform_plan_id: plan.id}
      }

    case plan.description do
      description when is_binary(description) and description != "" ->
        Map.put(attrs, :description, description)

      _ ->
        attrs
    end
  end

  defp billing_attributes_changed?(%PlatformPlan{} = original, %PlatformPlan{} = updated) do
    billing_attributes(original) != billing_attributes(updated)
  end

  defp product_attributes_changed?(%PlatformPlan{} = original, %PlatformPlan{} = updated) do
    original.name != updated.name || original.description != updated.description
  end

  defp create_stripe_price(%PlatformPlan{} = plan, product_id) do
    stripe_client().create_price(%{
      product: product_id,
      unit_amount: plan.amount,
      currency: plan.currency,
      recurring: %{interval: stripe_interval(plan.interval)}
    })
  end

  defp insert_platform_plan(attrs) do
    case %PlatformPlan{} |> PlatformPlan.changeset(attrs) |> Repo.insert() do
      {:ok, plan} -> {:ok, plan}
      {:error, changeset} -> {:error, :validation, changeset}
    end
  end

  defp sync_plan_to_stripe(%PlatformPlan{} = plan) do
    with {:ok, product} <-
           stripe_client().create_product(product_attributes(plan)),
         {:ok, price} <- create_stripe_price(plan, product.id) do
      plan
      |> PlatformPlan.changeset(%{
        stripe_product_id: product.id,
        stripe_price_id: price.id
      })
      |> Repo.update()
    else
      {:error, :stripe_error, reason} ->
        Logger.error("Failed to sync plan to Stripe",
          plan_id: plan.id,
          error: inspect(reason)
        )

        {:error, :stripe_error, reason}
    end
  end

  defp do_update_platform_plan(plan, attrs) do
    case plan |> PlatformPlan.changeset(attrs) |> Repo.update() do
      {:ok, plan} -> {:ok, plan}
      {:error, changeset} -> {:error, :validation, changeset}
    end
  end

  defp sync_updated_plan_to_stripe(_original, %PlatformPlan{stripe_product_id: nil} = updated) do
    sync_plan_to_stripe(updated)
  end

  defp sync_updated_plan_to_stripe(_original, %PlatformPlan{stripe_price_id: nil} = updated) do
    sync_plan_to_stripe(updated)
  end

  defp sync_updated_plan_to_stripe(%PlatformPlan{} = original, %PlatformPlan{} = updated) do
    with :ok <- maybe_update_stripe_product(original, updated) do
      maybe_replace_stripe_price(original, updated)
    end
  end

  defp maybe_update_stripe_product(%PlatformPlan{} = original, %PlatformPlan{} = updated) do
    if product_attributes_changed?(original, updated) do
      case stripe_client().update_product(updated.stripe_product_id, product_attributes(updated)) do
        {:ok, _product} -> :ok
        {:error, :stripe_error, reason} -> {:error, :stripe_error, reason}
        {:error, reason} -> {:error, :stripe_error, reason}
      end
    else
      :ok
    end
  end

  defp maybe_replace_stripe_price(%PlatformPlan{} = original, %PlatformPlan{} = updated) do
    if billing_attributes_changed?(original, updated) do
      with {:ok, new_price} <- create_stripe_price(updated, updated.stripe_product_id),
           {:ok, updated} <-
             updated
             |> PlatformPlan.changeset(%{stripe_price_id: new_price.id})
             |> Repo.update(),
           {:ok, _old_price} <- stripe_client().deactivate_price(original.stripe_price_id) do
        {:ok, updated}
      else
        {:error, :stripe_error, reason} ->
          Logger.error("Failed to replace Stripe price for plan",
            plan_id: updated.id,
            error: inspect(reason)
          )

          {:error, :stripe_error, reason}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:error, :validation, changeset}

        {:error, reason} ->
          Logger.error("Failed to replace Stripe price for plan",
            plan_id: updated.id,
            error: inspect(reason)
          )

          {:error, :stripe_error, reason}
      end
    else
      {:ok, updated}
    end
  end

  defp stripe_interval(:monthly), do: "month"
  defp stripe_interval(:yearly), do: "year"

  @doc """
  Updates a platform plan.

  Exempt from doctest — hits the database.
  """
  def update_platform_plan(%PlatformPlan{} = plan, attrs) do
    Bobine.Otel.with_span "bobine.platform_billing.update_platform_plan" do
      Repo.transaction(fn ->
        with {:ok, updated} <- do_update_platform_plan(plan, attrs),
             {:ok, updated} <- sync_updated_plan_to_stripe(plan, updated) do
          updated
        else
          {:error, type, detail} ->
            Repo.rollback({type, detail})
        end
      end)
      |> case do
        {:ok, updated} ->
          Events.broadcast(nil, {:platform_plan_updated, updated})
          {:ok, updated}

        {:error, {:validation, changeset}} ->
          {:error, :validation, changeset}

        {:error, {:stripe_error, reason}} ->
          Logger.error("Failed to update plan in Stripe",
            plan_id: plan.id,
            error: inspect(reason)
          )

          {:error, :stripe_error, reason}
      end
    end
  end

  @doc """
  Deactivates a platform plan, hiding it from plan selection.

  Exempt from doctest — hits the database.
  """
  def deactivate_platform_plan(%PlatformPlan{} = plan) do
    Bobine.Otel.with_span "bobine.platform_billing.deactivate_platform_plan" do
      case plan |> PlatformPlan.changeset(%{active: false}) |> Repo.update() do
        {:ok, plan} ->
          Events.broadcast(nil, {:platform_plan_deactivated, plan})
          {:ok, plan}

        {:error, changeset} ->
          {:error, :validation, changeset}
      end
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking platform plan changes.

  ## Examples

      iex> change_platform_plan(%Bobine.Billing.PlatformPlan{})
      %Ecto.Changeset{data: %Bobine.Billing.PlatformPlan{}}

  """
  def change_platform_plan(%PlatformPlan{} = plan, attrs \\ %{}) do
    PlatformPlan.changeset(plan, attrs)
  end

  ## -----------------------------------------------------------------------
  ## Org subscription management
  ## -----------------------------------------------------------------------

  @doc """
  Gets the org's current platform subscription.

  Returns `{:ok, subscription}` or `{:error, :not_found}`.

  Exempt from doctest — hits the database.
  """
  def get_subscription(%Organization{id: org_id}) do
    case Repo.get_by(PlatformSubscription, organization_id: org_id) do
      nil -> {:error, :not_found}
      sub -> {:ok, sub}
    end
  end

  @doc """
  Gets a platform subscription by its Stripe subscription ID.

  Returns `{:ok, subscription}` or `{:error, :not_found}`.

  Exempt from doctest — hits the database.
  """
  def get_subscription_by_stripe_id(stripe_subscription_id) do
    case Repo.get_by(PlatformSubscription, stripe_subscription_id: stripe_subscription_id) do
      nil -> {:error, :not_found}
      sub -> {:ok, sub}
    end
  end

  @doc """
  Creates a Stripe Checkout Session for an org to subscribe to a platform plan.

  This hits Bobine's own Stripe account (NOT Connect).

  Exempt from doctest — calls Stripe API.
  """
  def create_org_checkout(%Organization{}, %PlatformPlan{stripe_price_id: nil}, _user) do
    {:error, :plan_not_configured}
  end

  def create_org_checkout(%Organization{} = organization, %PlatformPlan{} = plan, user) do
    Bobine.Otel.with_span "bobine.platform_billing.create_checkout",
                          %{"bobine.org.id" => organization.id} do
      key = Bobine.Idempotency.key("platform_checkout", organization.id, plan.id)

      params = %{
        mode: "subscription",
        line_items: [%{price: plan.stripe_price_id, quantity: 1}],
        success_url:
          OrgURL.org_url(
            "#{base_url()}/admin/settings/billing/success?session_id={CHECKOUT_SESSION_ID}",
            organization
          ),
        cancel_url: OrgURL.org_url("#{base_url()}/admin/settings/billing", organization),
        customer_email: user.email,
        metadata: %{
          organization_id: organization.id,
          platform_plan_id: plan.id
        }
      }

      stripe_client().create_checkout_session(params, idempotency_key: key)
    end
  end

  @doc """
  Creates a Stripe Customer Portal session for an org to manage their subscription.

  Exempt from doctest — calls Stripe API.
  """
  def create_org_portal_session(%Organization{} = organization) do
    Bobine.Otel.with_span "bobine.platform_billing.create_portal_session",
                          %{"bobine.org.id" => organization.id} do
      case get_subscription(organization) do
        {:ok, sub} when not is_nil(sub.stripe_customer_id) ->
          return_url =
            OrgURL.org_url("#{base_url()}/admin/settings/billing", organization)

          stripe_client().create_billing_portal_session(sub.stripe_customer_id, return_url)

        _ ->
          {:error, :no_subscription}
      end
    end
  end

  @doc """
  Creates a platform subscription record from a completed Stripe checkout.

  Exempt from doctest — hits the database.
  """
  def create_subscription_from_checkout(
        %Organization{} = organization,
        %PlatformPlan{} = plan,
        session
      ) do
    Bobine.Otel.with_span "bobine.platform_billing.create_subscription",
                          %{"bobine.org.id" => organization.id} do
      attrs = %{
        organization_id: organization.id,
        platform_plan_id: plan.id,
        stripe_subscription_id: session["subscription"],
        stripe_customer_id: session["customer"],
        status: :active,
        current_period_start: DateTime.utc_now() |> DateTime.truncate(:second),
        current_period_end:
          DateTime.utc_now() |> DateTime.add(30, :day) |> DateTime.truncate(:second)
      }

      case %PlatformSubscription{} |> PlatformSubscription.changeset(attrs) |> Repo.insert() do
        {:ok, sub} ->
          Audit.log(nil, "platform_subscription.created", sub)
          Events.broadcast(nil, {:platform_subscription_created, sub})
          Bobine.Metrics.platform_subscription_created(organization.id, plan.slug)
          {:ok, sub}

        {:error, changeset} ->
          {:error, :validation, changeset}
      end
    end
  end

  @doc """
  Updates a platform subscription from Stripe webhook data.

  Exempt from doctest — hits the database.
  """
  def update_subscription_from_stripe(%PlatformSubscription{} = sub, stripe_data) do
    Bobine.Otel.with_span "bobine.platform_billing.update_subscription" do
      attrs = %{
        status: normalize_status(stripe_data["status"]),
        current_period_start: parse_stripe_timestamp(stripe_data["current_period_start"]),
        current_period_end: parse_stripe_timestamp(stripe_data["current_period_end"]),
        cancel_at_period_end: stripe_data["cancel_at_period_end"] || false,
        canceled_at: parse_stripe_timestamp(stripe_data["canceled_at"])
      }

      # If the plan changed, update the plan reference
      attrs =
        case get_plan_from_stripe_items(stripe_data) do
          nil -> attrs
          plan -> Map.put(attrs, :platform_plan_id, plan.id)
        end

      case sub |> PlatformSubscription.changeset(attrs) |> Repo.update() do
        {:ok, sub} ->
          Audit.log(nil, "platform_subscription.updated", sub, attrs)
          {:ok, sub}

        {:error, changeset} ->
          {:error, :validation, changeset}
      end
    end
  end

  @doc """
  Cancels a platform subscription record (from Stripe webhook).

  Exempt from doctest — hits the database.
  """
  def cancel_subscription_from_stripe(%PlatformSubscription{} = sub) do
    Bobine.Otel.with_span "bobine.platform_billing.cancel_subscription" do
      attrs = %{
        status: :canceled,
        canceled_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }

      case sub |> PlatformSubscription.changeset(attrs) |> Repo.update() do
        {:ok, sub} ->
          Audit.log(nil, "platform_subscription.canceled", sub)
          Events.broadcast(nil, {:platform_subscription_canceled, sub})
          Bobine.Metrics.platform_subscription_canceled(sub.organization_id)
          {:ok, sub}

        {:error, changeset} ->
          {:error, :validation, changeset}
      end
    end
  end

  @doc """
  Marks a platform subscription as past_due after payment failure.

  Exempt from doctest — hits the database.
  """
  def mark_platform_payment_failed(%PlatformSubscription{} = sub) do
    Bobine.Otel.with_span "bobine.platform_billing.mark_payment_failed" do
      case sub |> PlatformSubscription.changeset(%{status: :past_due}) |> Repo.update() do
        {:ok, sub} ->
          Audit.log(nil, "platform_subscription.payment_failed", sub)
          Events.broadcast(nil, {:platform_payment_failed, sub})
          {:ok, sub}

        {:error, changeset} ->
          {:error, :validation, changeset}
      end
    end
  end

  @doc """
  Restores a platform subscription to active after successful payment.

  Exempt from doctest — hits the database.
  """
  def mark_platform_payment_succeeded(%PlatformSubscription{} = sub) do
    Bobine.Otel.with_span "bobine.platform_billing.mark_payment_succeeded" do
      case sub |> PlatformSubscription.changeset(%{status: :active}) |> Repo.update() do
        {:ok, sub} ->
          Audit.log(nil, "platform_subscription.payment_succeeded", sub)
          {:ok, sub}

        {:error, changeset} ->
          {:error, :validation, changeset}
      end
    end
  end

  ## -----------------------------------------------------------------------
  ## Feature flag syncing
  ## -----------------------------------------------------------------------

  @doc """
  Syncs an organization's feature flags to match a platform plan's enabled_features.

  Exempt from doctest — hits the database.
  """
  def sync_features_to_plan(%Organization{} = organization, %PlatformPlan{} = plan) do
    Bobine.Otel.with_span "bobine.platform_billing.sync_features",
                          %{"bobine.org.id" => organization.id} do
      features =
        plan.enabled_features
        |> Enum.map(fn feature -> {feature, true} end)
        |> Map.new()

      organization
      |> Organization.changeset(%{features: features})
      |> Repo.update()
    end
  end

  @doc """
  Returns a default plan struct for orgs without a subscription.

  ## Examples

      iex> plan = Bobine.PlatformBilling.default_free_plan()
      iex> plan.max_videos
      5
  """
  def default_free_plan do
    %PlatformPlan{
      name: "Free",
      slug: "free",
      amount: 0,
      usage_tier: :basic,
      business_tier: :individual,
      max_videos: 5,
      max_monthly_views: 500,
      max_team_seats: 1,
      max_webhook_endpoints: 0,
      enabled_features: []
    }
  end

  ## -----------------------------------------------------------------------
  ## Private helpers
  ## -----------------------------------------------------------------------

  defp normalize_status("active"), do: :active
  defp normalize_status("past_due"), do: :past_due
  defp normalize_status("canceled"), do: :canceled
  defp normalize_status("trialing"), do: :trialing
  defp normalize_status("unpaid"), do: :unpaid
  defp normalize_status(other) when is_atom(other), do: other
  defp normalize_status(_), do: :active

  defp parse_stripe_timestamp(nil), do: nil

  defp parse_stripe_timestamp(ts) when is_integer(ts) do
    DateTime.from_unix!(ts) |> DateTime.truncate(:second)
  end

  defp parse_stripe_timestamp(%DateTime{} = dt), do: dt
  defp parse_stripe_timestamp(_), do: nil

  defp get_plan_from_stripe_items(%{"items" => %{"data" => [item | _]}}) do
    price_id = get_in(item, ["price", "id"])

    if price_id do
      Repo.get_by(PlatformPlan, stripe_price_id: price_id)
    end
  end

  defp get_plan_from_stripe_items(_), do: nil

  defp stripe_client do
    Application.get_env(:bobine, :stripe_client, Bobine.Billing.StripeClient)
  end

  defp base_url do
    Application.get_env(:bobine, :base_url, "http://localhost:4000")
  end
end
