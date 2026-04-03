defmodule Bobine.Billing.SubscriptionLifecycleTest do
  use Bobine.DataCase, async: true
  use Oban.Testing, repo: Bobine.Repo

  alias Bobine.Billing.ViewerSubscription
  alias Bobine.Workers.StripeWebhookProcessor

  defp connected_org do
    insert(:organization,
      stripe_connect_account_id: "acct_lifecycle",
      stripe_connect_onboarding_complete: true
    )
  end

  defp build_event(type, object, connect_account_id) do
    %{
      "id" => "evt_#{type}_#{System.unique_integer([:positive])}",
      "type" => type,
      "account" => connect_account_id,
      "data" => %{"object" => object}
    }
  end

  describe "complete lifecycle: subscribe → pay → fail → recover → cancel" do
    test "full viewer subscription lifecycle" do
      org = connected_org()
      viewer = insert(:viewer, organization: org, subscription_status: "none")

      # 1. checkout.session.completed → viewer active
      checkout_event =
        build_event(
          "checkout.session.completed",
          %{
            "subscription" => "sub_lifecycle",
            "customer" => "cus_lifecycle",
            "customer_email" => viewer.email
          },
          org.stripe_connect_account_id
        )

      assert :ok =
               perform_job(StripeWebhookProcessor, %{
                 event: checkout_event,
                 event_id: checkout_event["id"]
               })

      viewer = Repo.get!(Bobine.Viewers.Viewer, viewer.id)
      assert viewer.subscription_status == "active"

      # 2. invoice.payment_succeeded → still active
      success_event =
        build_event(
          "invoice.payment_succeeded",
          %{
            "subscription" => "sub_lifecycle"
          },
          org.stripe_connect_account_id
        )

      assert :ok =
               perform_job(StripeWebhookProcessor, %{
                 event: success_event,
                 event_id: success_event["id"]
               })

      viewer = Repo.get!(Bobine.Viewers.Viewer, viewer.id)
      assert viewer.subscription_status == "active"

      # 3. invoice.payment_failed → past_due, access removed
      fail_event =
        build_event(
          "invoice.payment_failed",
          %{
            "subscription" => "sub_lifecycle"
          },
          org.stripe_connect_account_id
        )

      assert :ok =
               perform_job(StripeWebhookProcessor, %{
                 event: fail_event,
                 event_id: fail_event["id"]
               })

      viewer = Repo.get!(Bobine.Viewers.Viewer, viewer.id)
      assert viewer.subscription_status == "past_due"
      # past_due viewers are redirected to payment-issue page by RequireSubscription hook
      # even though SubscriptionAccess.has_access? returns true for grace period

      # 4. invoice.payment_succeeded → active again, access restored
      recover_event =
        build_event(
          "invoice.payment_succeeded",
          %{
            "subscription" => "sub_lifecycle"
          },
          org.stripe_connect_account_id
        )

      assert :ok =
               perform_job(StripeWebhookProcessor, %{
                 event: recover_event,
                 event_id: recover_event["id"]
               })

      viewer = Repo.get!(Bobine.Viewers.Viewer, viewer.id)
      assert viewer.subscription_status == "active"

      # 5. customer.subscription.updated cancel_at_period_end → still active
      update_event =
        build_event(
          "customer.subscription.updated",
          %{
            "id" => "sub_lifecycle",
            "status" => "active",
            "cancel_at_period_end" => true,
            "current_period_start" => DateTime.to_unix(DateTime.utc_now()),
            "current_period_end" => DateTime.to_unix(DateTime.add(DateTime.utc_now(), 30, :day)),
            "canceled_at" => nil,
            "trial_start" => nil,
            "trial_end" => nil
          },
          org.stripe_connect_account_id
        )

      assert :ok =
               perform_job(StripeWebhookProcessor, %{
                 event: update_event,
                 event_id: update_event["id"]
               })

      viewer = Repo.get!(Bobine.Viewers.Viewer, viewer.id)
      assert viewer.subscription_status == "active"

      sub =
        Repo.one!(
          from s in ViewerSubscription, where: s.stripe_subscription_id == "sub_lifecycle"
        )

      assert sub.cancel_at_period_end == true

      # 6. customer.subscription.deleted → canceled, access removed
      delete_event =
        build_event(
          "customer.subscription.deleted",
          %{
            "id" => "sub_lifecycle"
          },
          org.stripe_connect_account_id
        )

      assert :ok =
               perform_job(StripeWebhookProcessor, %{
                 event: delete_event,
                 event_id: delete_event["id"]
               })

      viewer = Repo.get!(Bobine.Viewers.Viewer, viewer.id)
      assert viewer.subscription_status == "canceled"
      refute Bobine.Viewers.SubscriptionAccess.has_access?(viewer)
    end
  end
end
