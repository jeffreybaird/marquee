defmodule Marquee.Billing do
  @moduledoc """
  Viewer-facing billing operations via Stripe Connect.

  Separate from `Marquee.PlatformBilling` which handles org-to-Marquee subscriptions.
  This context manages plans, coupons, checkout sessions, and viewer subscriptions
  on each organization's connected Stripe account.
  """

  import Ecto.Query, warn: false
  alias Marquee.Accounts.Organization
  alias Marquee.Audit
  alias Marquee.Events
  alias Marquee.Pagination
  alias Marquee.Repo
  alias MarqueeWeb.OrgURL

  require Marquee.Otel
  require Logger

  alias Marquee.Billing.Plan
  alias Marquee.Streaming.LiveEvent

  @doc """
  Returns a paginated list of plans, excluding soft-deleted records.

  Exempt from doctest — hits the database.
  """
  def list_plans(%Organization{id: org_id}, opts \\ []) do
    Plan
    |> where(organization_id: ^org_id)
    |> where([p], is_nil(p.deleted_at))
    |> order_by(desc: :inserted_at)
    |> Pagination.paginate(opts)
  end

  @doc """
  Returns a paginated list of active plans, excluding soft-deleted and
  inactive records. Use this for viewer-facing plan selection.

  Exempt from doctest — hits the database.
  """
  def list_active_plans(%Organization{id: org_id}, opts \\ []) do
    Plan
    |> where(organization_id: ^org_id)
    |> where([p], is_nil(p.deleted_at))
    |> where([p], p.active == true)
    |> order_by(desc: :inserted_at)
    |> Pagination.paginate(opts)
  end

  @doc """
  Returns the list of plans for an organization, including soft-deleted
  records.

  Exempt from doctest — hits the database.
  """
  def list_plans_including_deleted(%Organization{id: org_id}) do
    Plan
    |> where(organization_id: ^org_id)
    |> Repo.all()
  end

  @doc """
  Creates a plan.

  Accepts an optional scope so the broadcast + audit subscriber can
  attribute the action to the acting user/org.

  Exempt from doctest — hits the database.
  """
  def create_plan(scope \\ nil, attrs) do
    Marquee.Otel.with_span "marquee.billing.create_plan", otel_attrs(scope) do
      case %Plan{} |> Plan.changeset(attrs) |> Repo.insert() do
        {:ok, plan} ->
          Events.broadcast(scope, {:plan_created, plan})
          {:ok, plan}

        {:error, changeset} ->
          {:error, :validation, changeset}
      end
    end
  end

  @doc """
  Updates a plan.

  Accepts an optional scope so the broadcast + audit subscriber can
  attribute the action to the acting user/org.

  Exempt from doctest — hits the database.
  """
  def update_plan(scope \\ nil, %Plan{} = plan, attrs) do
    Marquee.Otel.with_span "marquee.billing.update_plan",
                           plan |> otel_attrs_for_plan(scope) do
      case plan |> Plan.changeset(attrs) |> Repo.update() do
        {:ok, plan} ->
          Events.broadcast(scope, {:plan_updated, plan})
          {:ok, plan}

        {:error, changeset} ->
          {:error, :validation, changeset}
      end
    end
  end

  @doc """
  Soft-deletes a plan by setting `deleted_at`.

  Exempt from doctest — hits the database.
  """
  def delete_plan(%Plan{} = plan) do
    Marquee.Otel.with_span "marquee.billing.delete_plan", otel_attrs_for_plan(plan, nil) do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      case plan |> Ecto.Changeset.change(deleted_at: now) |> Repo.update() do
        {:ok, plan} -> {:ok, plan}
        {:error, changeset} -> {:error, :validation, changeset}
      end
    end
  end

  @doc """
  Restores a soft-deleted plan by clearing `deleted_at`.

  Exempt from doctest — hits the database.
  """
  def restore_plan(%Plan{} = plan) do
    Marquee.Otel.with_span "marquee.billing.restore_plan", otel_attrs_for_plan(plan, nil) do
      case plan |> Ecto.Changeset.change(deleted_at: nil) |> Repo.update() do
        {:ok, plan} -> {:ok, plan}
        {:error, changeset} -> {:error, :validation, changeset}
      end
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking plan changes.

  ## Examples

      iex> changeset = change_plan(%Marquee.Billing.Plan{}, %{name: "Monthly", stripe_price_id: "price_example", stripe_product_id: "prod_example", amount: 1000, interval: :monthly, organization_id: "00000000-0000-0000-0000-000000000001"})
      iex> changeset.valid?
      true

  """
  def change_plan(%Plan{} = plan, attrs \\ %{}) do
    Plan.changeset(plan, attrs)
  end

  alias Marquee.Billing.Subscription

  @doc """
  Returns a paginated list of subscriptions for an organization.

  Exempt from doctest — hits the database.
  """
  def list_subscriptions(%Organization{id: org_id}, opts \\ []) do
    Subscription
    |> where(organization_id: ^org_id)
    |> order_by(desc: :inserted_at)
    |> Pagination.paginate(opts)
  end

  @doc """
  Gets a subscription by ID scoped to an organization. Raises on not found.

  Exempt from doctest — hits the database.
  """
  def get_subscription!(%Organization{id: org_id}, id) do
    Repo.get_by!(Subscription, id: id, organization_id: org_id)
  end

  @doc """
  Creates a subscription.

  Accepts an optional scope so the broadcast + audit subscriber can
  attribute the action to the acting user/org.

  Exempt from doctest — hits the database.
  """
  def create_subscription(scope \\ nil, attrs) do
    Marquee.Otel.with_span "marquee.billing.create_subscription" do
      case %Subscription{} |> Subscription.changeset(attrs) |> Repo.insert() do
        {:ok, sub} ->
          Events.broadcast(scope, {:subscription_created, sub})
          {:ok, sub}

        {:error, changeset} ->
          {:error, :validation, changeset}
      end
    end
  end

  @doc """
  Updates a subscription.

  Exempt from doctest — hits the database.
  """
  def update_subscription(%Subscription{} = subscription, attrs) do
    Marquee.Otel.with_span "marquee.billing.update_subscription",
                           %{"marquee.org.id" => subscription.organization_id} do
      case subscription |> Subscription.changeset(attrs) |> Repo.update() do
        {:ok, sub} -> {:ok, sub}
        {:error, changeset} -> {:error, :validation, changeset}
      end
    end
  end

  @doc """
  Deletes a subscription.

  Hard-deletes the subscription row and broadcasts a
  `{:subscription_deleted, sub}` event so the audit subscriber can
  record the action. Accepts an optional scope so the audit entry
  attributes the action.

  Exempt from doctest — hits the database.
  """
  def delete_subscription(scope \\ nil, %Subscription{} = subscription) do
    Marquee.Otel.with_span "marquee.billing.delete_subscription",
                           %{"marquee.org.id" => subscription.organization_id} do
      case Repo.delete(subscription) do
        {:ok, deleted} ->
          Events.broadcast(scope, {:subscription_deleted, deleted})
          {:ok, deleted}

        {:error, changeset} ->
          {:error, :validation, changeset}
      end
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking subscription changes.

  ## Examples

      iex> changeset = change_subscription(%Marquee.Billing.Subscription{}, %{stripe_subscription_id: "sub_example", status: :active, current_period_end: ~U[2027-01-01 00:00:00Z], organization_id: "00000000-0000-0000-0000-000000000001", user_id: "00000000-0000-0000-0000-000000000001", plan_id: "00000000-0000-0000-0000-000000000001"})
      iex> changeset.valid?
      true

  """
  def change_subscription(%Subscription{} = subscription, attrs \\ %{}) do
    Subscription.changeset(subscription, attrs)
  end

  # ── Plan management with Stripe sync ────────────────────────────────────

  @doc """
  Creates a plan on the org's connected Stripe account and stores it locally.

  Creates a Stripe Product and Price on the connected account, then inserts
  the Plan record with the Stripe IDs.

  Exempt from doctest — calls external API.
  """
  def create_plan_with_stripe(%Organization{} = org, attrs) do
    Marquee.Otel.with_span "marquee.billing.create_plan",
                           %{"marquee.org.id" => org.id} do
      with :ok <- ensure_stripe_connected(org),
           {:ok, product} <- create_connected_product(org, attrs),
           {:ok, price} <- create_connected_price(org, product, attrs) do
        plan_attrs =
          attrs
          |> stringify_keys()
          |> Map.merge(%{
            "organization_id" => org.id,
            "stripe_product_id" => product.id,
            "stripe_price_id" => price.id,
            "active" => true
          })

        scope = %Marquee.Accounts.Scope{organization: org}

        case create_plan(scope, plan_attrs) do
          {:ok, plan} ->
            Audit.log(scope, "plan.created", plan, %{
              amount: plan.amount,
              interval: plan.interval
            })

            {:ok, plan}

          error ->
            error
        end
      end
    end
  end

  @doc """
  Updates a plan. If the price changed, creates a new Stripe Price on the
  connected account (Stripe Prices are immutable).

  Exempt from doctest — calls external API.
  """
  def update_plan_with_stripe(%Organization{} = org, %Plan{} = plan, attrs) do
    Marquee.Otel.with_span "marquee.billing.update_plan",
                           %{"marquee.org.id" => org.id} do
      scope = %Marquee.Accounts.Scope{organization: org}

      if price_changed?(plan, attrs) do
        with :ok <- ensure_stripe_connected(org),
             {:ok, new_price} <- create_connected_price(org, plan, attrs) do
          update_plan(scope, plan, Map.put(attrs, :stripe_price_id, new_price.id))
        end
      else
        update_plan(scope, plan, attrs)
      end
    end
  end

  @doc """
  Deactivates a plan by setting `active: false`. The plan remains in the
  database but is hidden from the subscriber-facing page.

  Exempt from doctest — hits the database.
  """
  def deactivate_plan(%Plan{} = plan) do
    case plan |> Ecto.Changeset.change(active: false) |> Repo.update() do
      {:ok, plan} -> {:ok, plan}
      {:error, changeset} -> {:error, :validation, changeset}
    end
  end

  @doc """
  Reactivates a deactivated plan.

  Exempt from doctest — hits the database.
  """
  def reactivate_plan(%Plan{} = plan) do
    case plan |> Ecto.Changeset.change(active: true) |> Repo.update() do
      {:ok, plan} -> {:ok, plan}
      {:error, changeset} -> {:error, :validation, changeset}
    end
  end

  @doc """
  Gets a plan by ID scoped to an organization.

  Returns `{:ok, plan}` or `{:error, :not_found}`.

  Exempt from doctest — hits the database.
  """
  def get_plan(%Organization{id: org_id}, id) do
    Plan
    |> where(organization_id: ^org_id, id: ^id)
    |> where([p], is_nil(p.deleted_at))
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      plan -> {:ok, plan}
    end
  end

  @doc """
  Gets a plan by ID scoped to an organization. Raises on not found.

  Exempt from doctest — hits the database.
  """
  def get_plan!(%Organization{id: org_id}, id) do
    Plan
    |> where(organization_id: ^org_id, id: ^id)
    |> where([p], is_nil(p.deleted_at))
    |> Repo.one!()
  end

  defp price_changed?(plan, attrs) do
    amount = get_attr(attrs, :amount)
    interval = get_attr(attrs, :interval)
    currency = get_attr(attrs, :currency)

    (amount && amount != plan.amount) ||
      (interval && interval != plan.interval) ||
      (currency && currency != plan.currency)
  end

  defp create_connected_product(org, attrs) do
    stripe_client().create_connected_product(
      %{name: get_attr(attrs, :name), description: get_attr(attrs, :description)},
      connect_account: org.stripe_connect_account_id
    )
  end

  defp create_connected_price(org, product_or_plan, attrs) do
    product_id =
      case product_or_plan do
        %{stripe_product_id: id} -> id
        %{id: id} -> id
      end

    stripe_client().create_connected_price(
      %{
        product: product_id,
        unit_amount: get_attr(attrs, :amount),
        currency: get_attr(attrs, :currency) || "usd",
        recurring: %{interval: stripe_interval(get_attr(attrs, :interval))}
      },
      connect_account: org.stripe_connect_account_id
    )
  end

  defp get_attr(map, key) when is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp stripe_interval(:monthly), do: "month"
  defp stripe_interval(:yearly), do: "year"
  defp stripe_interval("monthly"), do: "month"
  defp stripe_interval("yearly"), do: "year"
  defp stripe_interval(other), do: to_string(other)

  # ── Coupons ─────────────────────────────────────────────────────────────

  alias Marquee.Billing.Coupon

  @doc """
  Returns a paginated list of coupons for an organization, excluding soft-deleted records.

  Exempt from doctest — hits the database.
  """
  def list_coupons(%Organization{id: org_id}, opts \\ []) do
    Coupon
    |> where(organization_id: ^org_id)
    |> where([c], is_nil(c.deleted_at))
    |> order_by(desc: :inserted_at)
    |> Pagination.paginate(opts)
  end

  @doc """
  Creates a coupon on the org's connected Stripe account and stores it locally.

  Exempt from doctest — calls external API.
  """
  def create_coupon(%Organization{} = org, attrs) do
    Marquee.Otel.with_span "marquee.billing.create_coupon",
                           %{"marquee.org.id" => org.id} do
      with :ok <- ensure_stripe_connected(org),
           {:ok, stripe_coupon} <-
             stripe_client().create_connected_coupon(
               build_stripe_coupon_params(attrs),
               connect_account: org.stripe_connect_account_id
             ),
           {:ok, promo_code} <-
             stripe_client().create_connected_promotion_code(
               %{
                 coupon: stripe_coupon.id,
                 code: String.upcase(to_string(attrs[:code] || attrs["code"]))
               },
               connect_account: org.stripe_connect_account_id
             ) do
        coupon_attrs =
          Map.merge(attrs, %{
            organization_id: org.id,
            stripe_coupon_id: stripe_coupon.id,
            stripe_promotion_code_id: promo_code.id,
            active: true
          })

        case %Coupon{} |> Coupon.changeset(coupon_attrs) |> Repo.insert() do
          {:ok, coupon} ->
            Events.broadcast(%{organization: org}, {:coupon_created, coupon})
            Audit.log(nil, "coupon.created", coupon, %{code: coupon.code})
            {:ok, coupon}

          {:error, changeset} ->
            {:error, :validation, changeset}
        end
      end
    end
  end

  @doc """
  Deactivates a coupon locally. The Stripe promotion code remains but is
  no longer referenced by new checkouts.

  Exempt from doctest — hits the database.
  """
  def deactivate_coupon(%Coupon{} = coupon) do
    case coupon |> Ecto.Changeset.change(active: false) |> Repo.update() do
      {:ok, coupon} -> {:ok, coupon}
      {:error, changeset} -> {:error, :validation, changeset}
    end
  end

  @doc """
  Soft-deletes a coupon.

  Exempt from doctest — hits the database.
  """
  def delete_coupon(%Coupon{} = coupon) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    case coupon |> Ecto.Changeset.change(deleted_at: now) |> Repo.update() do
      {:ok, coupon} -> {:ok, coupon}
      {:error, changeset} -> {:error, :validation, changeset}
    end
  end

  @doc """
  Returns a changeset for coupon form tracking.

  ## Examples

      iex> changeset = change_coupon(%Marquee.Billing.Coupon{}, %{organization_id: "00000000-0000-0000-0000-000000000001", code: "welcome", duration: :once, percent_off: 10})
      iex> changeset.valid?
      true
  """
  def change_coupon(%Coupon{} = coupon, attrs \\ %{}) do
    Coupon.changeset(coupon, attrs)
  end

  defp build_stripe_coupon_params(attrs) do
    duration = attr_value(attrs, :duration)

    %{name: attr_value(attrs, :name)}
    |> maybe_put_discount(attrs)
    |> Map.put(:duration, to_string(duration))
    |> maybe_put_duration_months(duration, attrs)
    |> maybe_put_max_redemptions(attrs)
  end

  defp maybe_put_discount(params, attrs) do
    cond do
      present?(attr_value(attrs, :percent_off)) ->
        Map.put(params, :percent_off, attr_value(attrs, :percent_off))

      present?(attr_value(attrs, :amount_off)) ->
        params
        |> Map.put(:amount_off, attr_value(attrs, :amount_off))
        |> Map.put(:currency, attr_value(attrs, :currency) || "usd")

      true ->
        params
    end
  end

  defp maybe_put_duration_months(params, duration, attrs) do
    case duration do
      :repeating -> Map.put(params, :duration_in_months, attr_value(attrs, :duration_in_months))
      "repeating" -> Map.put(params, :duration_in_months, attr_value(attrs, :duration_in_months))
      _ -> params
    end
  end

  defp maybe_put_max_redemptions(params, attrs) do
    case attr_value(attrs, :max_redemptions) do
      nil -> params
      max -> Map.put(params, :max_redemptions, max)
    end
  end

  defp attr_value(attrs, key) when is_atom(key) do
    Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))
  end

  defp present?(value), do: not is_nil(value)

  # ── Viewer checkout and subscription lifecycle ──────────────────────────

  alias Marquee.Billing.ViewerSubscription
  alias Marquee.Viewers.Viewer

  @doc """
  Creates a Stripe Checkout Session for a viewer to subscribe to a plan.

  Returns `{:ok, session}` with a `.url` field for redirect, or an error tuple.

  Exempt from doctest — calls external API.
  """
  def create_viewer_checkout(%Organization{} = org, %Viewer{} = viewer, %Plan{} = plan) do
    Marquee.Otel.with_span "marquee.billing.create_viewer_checkout",
                           %{"marquee.org.id" => org.id, "marquee.viewer.id" => viewer.id} do
      with :ok <- ensure_stripe_connected(org) do
        params = %{
          organization_id: org.id,
          viewer_id: viewer.id,
          viewer_email: viewer.email,
          stripe_connect_account_id: org.stripe_connect_account_id,
          line_items: [%{price: plan.stripe_price_id, quantity: 1}],
          success_url:
            OrgURL.org_url(
              "#{org_base_url(org)}/subscribe/success?session_id={CHECKOUT_SESSION_ID}",
              org
            ),
          cancel_url: OrgURL.org_url("#{org_base_url(org)}/subscribe", org),
          trial_period_days: plan.trial_period_days
        }

        case stripe_client().create_connected_checkout_session(params) do
          {:ok, session} ->
            Marquee.Metrics.checkout_initiated(org.id, plan.id)
            {:ok, session}

          {:error, :stripe_error, reason} ->
            Logger.error("Viewer checkout failed",
              org_id: org.id,
              viewer_id: viewer.id,
              reason: inspect(reason)
            )

            {:error, :stripe_error, reason}
        end
      end
    end
  end

  @doc """
  Creates a Stripe Customer Portal session for a viewer to manage their subscription.

  Exempt from doctest — calls external API.
  """
  def create_viewer_portal_session(%Organization{} = org, %Viewer{} = viewer) do
    Marquee.Otel.with_span "marquee.billing.create_viewer_portal_session",
                           %{"marquee.org.id" => org.id, "marquee.viewer.id" => viewer.id} do
      with :ok <- ensure_stripe_connected(org) do
        stripe_client().create_connected_portal_session(
          %{
            customer: viewer.stripe_customer_id,
            return_url: OrgURL.org_url("#{org_base_url(org)}/account", org)
          },
          connect_account: org.stripe_connect_account_id
        )
      end
    end
  end

  @doc """
  Creates a Stripe Checkout Session for a viewer to purchase a pay-per-view event.

  Returns `{:ok, session_url}` on success, or one of:
    * `{:error, :not_pay_per_view}` — event does not have pay_per_view access type
    * `{:error, :stripe_not_connected}` — org has not completed Stripe Connect onboarding
    * `{:error, :stripe_error, reason}` — Stripe API error

  Exempt from doctest — calls external API.
  """
  def create_ppv_checkout(
        %LiveEvent{access_type: "pay_per_view"} = event,
        %Viewer{} = viewer,
        %Organization{} = org,
        %{success_url: _, cancel_url: _} = urls
      ) do
    Marquee.Otel.with_span "marquee.billing.create_ppv_checkout",
                           %{"marquee.org.id" => org.id, "marquee.viewer.id" => viewer.id} do
      with :ok <- ensure_stripe_connected(org) do
        params = %{
          organization_id: org.id,
          viewer_id: viewer.id,
          viewer_email: viewer.email,
          live_event_id: event.id,
          stripe_connect_account_id: org.stripe_connect_account_id,
          line_items: [
            %{
              price_data: %{
                currency: "usd",
                unit_amount: event.ppv_price_cents,
                product_data: %{name: event.title}
              },
              quantity: 1
            }
          ],
          success_url: urls.success_url,
          cancel_url: urls.cancel_url
        }

        case stripe_client().create_connected_payment_checkout_session(params) do
          {:ok, session} ->
            Marquee.Metrics.checkout_initiated(org.id, event.id)
            {:ok, session.url}

          {:error, :stripe_error, reason} ->
            Logger.error("PPV checkout failed",
              org_id: org.id,
              viewer_id: viewer.id,
              live_event_id: event.id,
              reason: inspect(reason)
            )

            {:error, :stripe_error, reason}
        end
      end
    end
  end

  def create_ppv_checkout(%LiveEvent{}, %Viewer{}, %Organization{}, _urls) do
    {:error, :not_pay_per_view}
  end

  @doc """
  Creates a ViewerSubscription record from a completed Stripe Checkout session.

  Exempt from doctest — hits the database.
  """
  def create_subscription_from_checkout(%Organization{} = org, %Viewer{} = viewer, session) do
    Marquee.Otel.with_span "marquee.billing.create_subscription_from_checkout",
                           %{"marquee.org.id" => org.id, "marquee.viewer.id" => viewer.id} do
      stripe_sub_id = session["subscription"]
      stripe_customer_id = session["customer"]

      plan = find_plan_by_stripe_price(org, session)

      attrs = %{
        organization_id: org.id,
        viewer_id: viewer.id,
        plan_id: plan && plan.id,
        stripe_subscription_id: stripe_sub_id,
        stripe_customer_id: stripe_customer_id,
        status: "active"
      }

      case %ViewerSubscription{} |> ViewerSubscription.changeset(attrs) |> Repo.insert() do
        {:ok, subscription} ->
          Events.broadcast(%{organization: org}, {:viewer_subscription_created, subscription})
          Audit.log(nil, "viewer_subscription.created", subscription, %{viewer_id: viewer.id})
          {:ok, subscription}

        {:error, changeset} ->
          {:error, :validation, changeset}
      end
    end
  end

  @doc """
  Activates a viewer's subscription status based on the subscription state.

  Exempt from doctest — hits the database.
  """
  def activate_viewer_subscription(%Organization{} = org, %Viewer{} = viewer, subscription) do
    status = if subscription.trial_end, do: "trial", else: "active"

    attrs = %{subscription_status: status}

    attrs =
      if subscription.trial_end do
        Map.put(attrs, :trial_expires_at, subscription.trial_end)
      else
        attrs
      end

    viewer
    |> Viewer.subscription_changeset(attrs)
    |> Repo.update!()

    Events.broadcast(%{organization: org}, {:subscription_activated, viewer})
    :ok
  end

  @doc """
  Gets a ViewerSubscription by its Stripe subscription ID, scoped to an org.

  Returns `{:ok, subscription}` or `{:error, :not_found}`.

  Exempt from doctest — hits the database.
  """
  def get_viewer_subscription_by_stripe_id(%Organization{id: org_id}, stripe_sub_id) do
    ViewerSubscription
    |> where(organization_id: ^org_id, stripe_subscription_id: ^stripe_sub_id)
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      sub -> {:ok, sub}
    end
  end

  @doc """
  Updates a ViewerSubscription from Stripe webhook data.

  Exempt from doctest — hits the database.
  """
  def update_subscription_from_stripe(%Organization{} = org, %ViewerSubscription{} = sub, data) do
    new_plan = find_plan_from_subscription_data(org, data)

    attrs = %{
      status: data["status"],
      current_period_start: parse_stripe_timestamp(data["current_period_start"]),
      current_period_end: parse_stripe_timestamp(data["current_period_end"]),
      cancel_at_period_end: data["cancel_at_period_end"] || false,
      canceled_at: parse_stripe_timestamp(data["canceled_at"]),
      trial_start: parse_stripe_timestamp(get_in(data, ["trial_start"])),
      trial_end: parse_stripe_timestamp(get_in(data, ["trial_end"]))
    }

    attrs =
      if new_plan && new_plan.id != sub.plan_id do
        Logger.info("Viewer plan changed",
          org_id: org.id,
          viewer_id: sub.viewer_id,
          old_plan_id: sub.plan_id,
          new_plan_id: new_plan.id
        )

        Map.put(attrs, :plan_id, new_plan.id)
      else
        attrs
      end

    sub
    |> ViewerSubscription.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Syncs the viewer's subscription_status field with the ViewerSubscription state.

  Exempt from doctest — hits the database.
  """
  def sync_viewer_subscription_status(%Viewer{} = viewer, %ViewerSubscription{} = sub) do
    attrs = %{subscription_status: sub.status}

    attrs =
      if sub.cancel_at_period_end do
        Map.put(attrs, :subscription_expires_at, sub.current_period_end)
      else
        attrs
      end

    viewer
    |> Viewer.subscription_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Marks a viewer's subscription as past_due after payment failure.

  Exempt from doctest — hits the database.
  """
  def mark_payment_failed(%Organization{} = org, %Viewer{} = viewer, %ViewerSubscription{} = sub) do
    Marquee.Otel.with_span "marquee.billing.mark_payment_failed",
                           %{"marquee.org.id" => org.id, "marquee.viewer.id" => viewer.id} do
      sub |> Ecto.Changeset.change(status: "past_due") |> Repo.update!()

      viewer
      |> Viewer.subscription_changeset(%{subscription_status: "past_due"})
      |> Repo.update!()

      Events.broadcast(%{organization: org}, {:payment_failed, viewer, sub})
      Audit.log(nil, "subscription.payment_failed", sub, %{viewer_id: viewer.id})
      :ok
    end
  end

  @doc """
  Restores a viewer's subscription to active after successful payment recovery.

  Exempt from doctest — hits the database.
  """
  def mark_payment_succeeded(
        %Organization{} = org,
        %Viewer{} = viewer,
        %ViewerSubscription{} = sub
      ) do
    if viewer.subscription_status == "past_due" do
      sub |> Ecto.Changeset.change(status: "active") |> Repo.update!()
      viewer |> Viewer.subscription_changeset(%{subscription_status: "active"}) |> Repo.update!()

      Events.broadcast(%{organization: org}, {:payment_recovered, viewer, sub})
    end

    :ok
  end

  @doc """
  Cancels a viewer's subscription from a Stripe webhook.

  Exempt from doctest — hits the database.
  """
  def cancel_subscription_from_stripe(
        %Organization{} = org,
        %Viewer{} = viewer,
        %ViewerSubscription{} = sub
      ) do
    sub
    |> Ecto.Changeset.change(
      status: "canceled",
      canceled_at: DateTime.utc_now() |> DateTime.truncate(:second)
    )
    |> Repo.update!()

    viewer
    |> Viewer.subscription_changeset(%{subscription_status: "canceled"})
    |> Repo.update!()

    Events.broadcast(%{organization: org}, {:subscription_canceled, viewer, sub})
    Audit.log(nil, "subscription.canceled", sub, %{viewer_id: viewer.id})
    :ok
  end

  @doc """
  Gets the active ViewerSubscription for a viewer.

  Exempt from doctest — hits the database.
  """
  def get_active_viewer_subscription(%Organization{id: org_id}, %Viewer{id: viewer_id}) do
    ViewerSubscription
    |> where(organization_id: ^org_id, viewer_id: ^viewer_id)
    |> where([s], s.status in ["active", "trialing", "past_due"])
    |> where([s], is_nil(s.deleted_at))
    |> order_by(desc: :inserted_at)
    |> limit(1)
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      sub -> {:ok, sub}
    end
  end

  defp find_plan_by_stripe_price(org, session) do
    price_id = extract_price_id(session, "line_items")

    if price_id do
      Plan
      |> where(organization_id: ^org.id, stripe_price_id: ^price_id)
      |> Repo.one()
    end
  end

  defp find_plan_from_subscription_data(org, data) do
    price_id = extract_price_id(data, "items")

    if price_id do
      Plan
      |> where(organization_id: ^org.id, stripe_price_id: ^price_id)
      |> Repo.one()
    end
  end

  defp extract_price_id(data, items_key) do
    case get_in(data, [items_key, "data"]) do
      [%{"price" => %{"id" => id}} | _] -> id
      [%{"price" => price_id} | _] when is_binary(price_id) -> price_id
      _ -> nil
    end
  end

  defp parse_stripe_timestamp(nil), do: nil
  defp parse_stripe_timestamp(ts) when is_integer(ts), do: DateTime.from_unix!(ts)
  defp parse_stripe_timestamp(%DateTime{} = dt), do: dt
  defp parse_stripe_timestamp(_), do: nil

  # ── Stripe Connect onboarding ──────────────────────────────────────────

  @doc """
  Initiates Stripe Connect onboarding for an organization.

  Creates a Stripe Connect account if one doesn't exist, then returns
  the onboarding URL. Returns `{:ok, url}` or `{:error, :stripe_error, reason}`.

  Exempt from doctest — calls external API.
  """
  def initiate_connect_onboarding(%Organization{} = org) do
    Marquee.Otel.with_span "marquee.billing.initiate_connect_onboarding",
                           %{"marquee.org.id" => org.id} do
      with {:ok, account_id} <- ensure_connect_account(org),
           {:ok, link} <-
             stripe_client().create_connect_account_link(account_id, %{
               return_url:
                 OrgURL.org_url("#{org_base_url(org)}/admin/settings/stripe/return", org),
               refresh_url:
                 OrgURL.org_url("#{org_base_url(org)}/admin/settings/stripe/refresh", org)
             }) do
        {:ok, link.url}
      else
        {:error, :stripe_error, reason} ->
          Logger.error(
            "Stripe Connect onboarding failed org_id=#{org.id} reason=#{inspect(reason)}"
          )

          {:error, :stripe_error, reason}

        {:error, reason} ->
          Logger.error(
            "Stripe Connect onboarding failed org_id=#{org.id} reason=#{inspect(reason)}"
          )

          {:error, :stripe_error, reason}
      end
    end
  end

  @doc """
  Completes Stripe Connect onboarding by storing the account ID and setting
  the onboarding complete flag.

  Exempt from doctest — hits the database.
  """
  def complete_connect_onboarding(%Organization{} = org, stripe_account_id) do
    Marquee.Otel.with_span "marquee.billing.complete_connect_onboarding",
                           %{"marquee.org.id" => org.id} do
      org
      |> Organization.changeset(%{
        stripe_connect_account_id: stripe_account_id,
        stripe_connect_onboarding_complete: true
      })
      |> Repo.update()
      |> case do
        {:ok, org} ->
          Events.broadcast(%{organization: org}, {:stripe_connected, org})
          Audit.log(nil, "organization.stripe_connected", org, %{})
          {:ok, org}

        {:error, changeset} ->
          {:error, :validation, changeset}
      end
    end
  end

  @doc """
  Checks whether the organization has completed Stripe Connect onboarding.

  Returns `:ok` if connected, `{:error, :stripe_not_connected}` otherwise.

  ## Examples

      iex> ensure_stripe_connected(%Marquee.Accounts.Organization{stripe_connect_onboarding_complete: true})
      :ok

      iex> ensure_stripe_connected(%Marquee.Accounts.Organization{stripe_connect_onboarding_complete: false})
      {:error, :stripe_not_connected}
  """
  def ensure_stripe_connected(%Organization{stripe_connect_onboarding_complete: true}), do: :ok
  def ensure_stripe_connected(%Organization{}), do: {:error, :stripe_not_connected}

  defp ensure_connect_account(%Organization{stripe_connect_account_id: id})
       when is_binary(id) and id != "" do
    {:ok, id}
  end

  defp ensure_connect_account(%Organization{} = org) do
    case stripe_client().create_connect_account(%{
           type: :standard,
           metadata: %{"marquee_org_id" => org.id}
         }) do
      {:ok, account} ->
        org
        |> Ecto.Changeset.change(stripe_connect_account_id: account.id)
        |> Repo.update!()

        {:ok, account.id}

      {:error, :stripe_error, reason} ->
        {:error, :stripe_error, reason}
    end
  end

  defp otel_attrs(%{organization: %{id: id}}), do: %{"marquee.org.id" => id}
  defp otel_attrs(_), do: %{}

  defp otel_attrs_for_plan(%Plan{organization_id: id, id: plan_id}, _scope),
    do: %{"marquee.org.id" => id, "marquee.plan.id" => plan_id}

  defp stripe_client,
    do: Application.get_env(:marquee, :stripe_client, Marquee.Billing.StripeClient)

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {key, value} when is_atom(key) -> {Atom.to_string(key), value}
      {key, value} -> {key, value}
    end)
  end

  defp org_base_url(%Organization{custom_domain: domain})
       when is_binary(domain) and domain != "" do
    "https://#{domain}"
  end

  defp org_base_url(%Organization{slug: slug}) do
    endpoint_config = Application.get_env(:marquee, MarqueeWeb.Endpoint, [])
    host = get_in(endpoint_config, [:url, :host]) || "localhost"

    port =
      get_in(endpoint_config, [:http, :port]) || get_in(endpoint_config, [:url, :port]) || 4000

    if host =~ "localhost" do
      "http://#{host}:#{port}"
    else
      "https://#{slug}.#{host}"
    end
  end
end
