defmodule Bobine.Workers.StripeWebhookProcessorConnectedTest do
  use Bobine.DataCase, async: true
  use Oban.Testing, repo: Bobine.Repo

  alias Bobine.Billing.ViewerSubscription
  alias Bobine.Streaming.LiveEventTicket
  alias Bobine.Workers.StripeWebhookProcessor

  defp connected_org do
    insert(:organization,
      stripe_connect_account_id: "acct_connect_test",
      stripe_connect_onboarding_complete: true
    )
  end

  defp build_connected_event(type, object, org) do
    %{
      "id" => "evt_#{type}_#{System.unique_integer([:positive])}",
      "type" => type,
      "account" => org.stripe_connect_account_id,
      "data" => %{"object" => object}
    }
  end

  defp insert_viewer_sub(org, viewer, stripe_sub_id, attrs \\ []) do
    %ViewerSubscription{}
    |> ViewerSubscription.changeset(
      Enum.into(attrs, %{
        organization_id: org.id,
        viewer_id: viewer.id,
        stripe_subscription_id: stripe_sub_id,
        stripe_customer_id: "cus_test",
        status: "active"
      })
    )
    |> Repo.insert!()
  end

  # ══════════════════════════════════════════════════════════════════════════
  # checkout.session.completed
  # ══════════════════════════════════════════════════════════════════════════

  describe "connected checkout.session.completed" do
    test "creates viewer subscription and activates viewer" do
      org = connected_org()
      viewer = insert(:viewer, organization: org, subscription_status: "none")
      plan = insert(:plan, organization: org)

      event =
        build_connected_event(
          "checkout.session.completed",
          %{
            "subscription" => "sub_viewer_1",
            "customer" => "cus_viewer_1",
            "customer_email" => viewer.email,
            "line_items" => %{
              "data" => [%{"price" => %{"id" => plan.stripe_price_id}}]
            }
          },
          org
        )

      assert :ok = perform_job(StripeWebhookProcessor, %{event: event, event_id: event["id"]})

      updated_viewer = Repo.get!(Bobine.Viewers.Viewer, viewer.id)
      assert updated_viewer.subscription_status == "active"
      assert updated_viewer.stripe_customer_id == "cus_viewer_1"

      sub = Repo.one!(from(s in ViewerSubscription, where: s.viewer_id == ^viewer.id))
      assert sub.stripe_subscription_id == "sub_viewer_1"
      assert sub.status == "active"
      assert sub.organization_id == org.id
    end

    test "creates a new viewer when email not found in org" do
      org = connected_org()

      event =
        build_connected_event(
          "checkout.session.completed",
          %{
            "subscription" => "sub_new_viewer",
            "customer" => "cus_new_viewer",
            "customer_email" => "brand-new@example.com"
          },
          org
        )

      assert :ok = perform_job(StripeWebhookProcessor, %{event: event, event_id: event["id"]})

      new_viewer = Bobine.Viewers.get_viewer_by_email(org, "brand-new@example.com")
      assert new_viewer != nil
      assert new_viewer.stripe_customer_id == "cus_new_viewer"
      assert new_viewer.subscription_status == "active"
    end

    test "updates stripe_customer_id on existing viewer without one" do
      org = connected_org()
      viewer = insert(:viewer, organization: org, stripe_customer_id: nil)

      event =
        build_connected_event(
          "checkout.session.completed",
          %{
            "subscription" => "sub_existing",
            "customer" => "cus_new_id",
            "customer_email" => viewer.email
          },
          org
        )

      assert :ok = perform_job(StripeWebhookProcessor, %{event: event, event_id: event["id"]})

      updated = Repo.get!(Bobine.Viewers.Viewer, viewer.id)
      assert updated.stripe_customer_id == "cus_new_id"
    end

    test "uses customer_details.email when customer_email is nil" do
      org = connected_org()
      viewer = insert(:viewer, organization: org)

      event =
        build_connected_event(
          "checkout.session.completed",
          %{
            "subscription" => "sub_details",
            "customer" => "cus_details",
            "customer_email" => nil,
            "customer_details" => %{"email" => viewer.email}
          },
          org
        )

      assert :ok = perform_job(StripeWebhookProcessor, %{event: event, event_id: event["id"]})

      sub = Repo.one!(from(s in ViewerSubscription, where: s.viewer_id == ^viewer.id))
      assert sub.stripe_subscription_id == "sub_details"
    end

    test "returns :ok when connected account org not found" do
      event = %{
        "id" => "evt_no_org",
        "type" => "checkout.session.completed",
        "account" => "acct_nonexistent",
        "data" => %{
          "object" => %{
            "subscription" => "sub_x",
            "customer" => "cus_x",
            "customer_email" => "x@example.com"
          }
        }
      }

      assert :ok = perform_job(StripeWebhookProcessor, %{event: event, event_id: event["id"]})
    end

    test "does not trigger platform billing handlers" do
      org = connected_org()
      viewer = insert(:viewer, organization: org, subscription_status: "none")

      event =
        build_connected_event(
          "checkout.session.completed",
          %{
            "subscription" => "sub_viewer_2",
            "customer" => "cus_viewer_2",
            "customer_email" => viewer.email,
            "metadata" => %{}
          },
          org
        )

      assert :ok = perform_job(StripeWebhookProcessor, %{event: event, event_id: event["id"]})
      # No platform subscription created — only viewer subscription
      sub = Repo.one(from(s in ViewerSubscription, where: s.viewer_id == ^viewer.id))
      assert sub != nil
    end
  end

  # ══════════════════════════════════════════════════════════════════════════
  # customer.subscription.updated
  # ══════════════════════════════════════════════════════════════════════════

  describe "connected customer.subscription.updated" do
    test "updates subscription fields and syncs viewer status" do
      org = connected_org()
      viewer = insert(:viewer, organization: org, subscription_status: "active")
      sub = insert_viewer_sub(org, viewer, "sub_update_1")

      now = DateTime.utc_now() |> DateTime.to_unix()
      period_end = DateTime.utc_now() |> DateTime.add(30, :day) |> DateTime.to_unix()

      event =
        build_connected_event(
          "customer.subscription.updated",
          %{
            "id" => "sub_update_1",
            "status" => "active",
            "cancel_at_period_end" => true,
            "current_period_start" => now,
            "current_period_end" => period_end,
            "canceled_at" => nil,
            "trial_start" => nil,
            "trial_end" => nil
          },
          org
        )

      assert :ok = perform_job(StripeWebhookProcessor, %{event: event, event_id: event["id"]})

      updated_sub = Repo.get!(ViewerSubscription, sub.id)
      assert updated_sub.cancel_at_period_end == true
      assert updated_sub.current_period_end != nil
    end

    test "updates plan_id when viewer changes plan" do
      org = connected_org()
      viewer = insert(:viewer, organization: org, subscription_status: "active")
      old_plan = insert(:plan, organization: org, name: "Monthly", stripe_price_id: "price_old")
      new_plan = insert(:plan, organization: org, name: "Annual", stripe_price_id: "price_new")
      sub = insert_viewer_sub(org, viewer, "sub_plan_change", plan_id: old_plan.id)

      assert sub.plan_id == old_plan.id

      now = DateTime.utc_now() |> DateTime.to_unix()
      period_end = DateTime.utc_now() |> DateTime.add(365, :day) |> DateTime.to_unix()

      event =
        build_connected_event(
          "customer.subscription.updated",
          %{
            "id" => "sub_plan_change",
            "status" => "active",
            "cancel_at_period_end" => false,
            "current_period_start" => now,
            "current_period_end" => period_end,
            "canceled_at" => nil,
            "trial_start" => nil,
            "trial_end" => nil,
            "items" => %{
              "data" => [%{"price" => %{"id" => "price_new"}}]
            }
          },
          org
        )

      assert :ok = perform_job(StripeWebhookProcessor, %{event: event, event_id: event["id"]})

      updated_sub = Repo.get!(ViewerSubscription, sub.id)
      assert updated_sub.plan_id == new_plan.id
    end

    test "keeps plan_id when price not in items data" do
      org = connected_org()
      viewer = insert(:viewer, organization: org, subscription_status: "active")
      plan = insert(:plan, organization: org, name: "Monthly")
      sub = insert_viewer_sub(org, viewer, "sub_no_items", plan_id: plan.id)

      event =
        build_connected_event(
          "customer.subscription.updated",
          %{
            "id" => "sub_no_items",
            "status" => "active",
            "cancel_at_period_end" => false,
            "current_period_start" => DateTime.utc_now() |> DateTime.to_unix(),
            "current_period_end" =>
              DateTime.utc_now() |> DateTime.add(30, :day) |> DateTime.to_unix(),
            "canceled_at" => nil,
            "trial_start" => nil,
            "trial_end" => nil
          },
          org
        )

      assert :ok = perform_job(StripeWebhookProcessor, %{event: event, event_id: event["id"]})

      updated_sub = Repo.get!(ViewerSubscription, sub.id)
      assert updated_sub.plan_id == plan.id
    end

    test "returns :ok when subscription not found" do
      org = connected_org()

      event =
        build_connected_event(
          "customer.subscription.updated",
          %{
            "id" => "sub_nonexistent",
            "status" => "active",
            "cancel_at_period_end" => false
          },
          org
        )

      assert :ok = perform_job(StripeWebhookProcessor, %{event: event, event_id: event["id"]})
    end

    test "returns :ok when org not found for connect account" do
      event = %{
        "id" => "evt_sub_upd_no_org",
        "type" => "customer.subscription.updated",
        "account" => "acct_ghost",
        "data" => %{
          "object" => %{"id" => "sub_ghost", "status" => "active"}
        }
      }

      assert :ok = perform_job(StripeWebhookProcessor, %{event: event, event_id: event["id"]})
    end
  end

  # ══════════════════════════════════════════════════════════════════════════
  # invoice.payment_failed
  # ══════════════════════════════════════════════════════════════════════════

  describe "connected invoice.payment_failed" do
    test "sets viewer and subscription to past_due" do
      org = connected_org()
      viewer = insert(:viewer, organization: org, subscription_status: "active")
      _sub = insert_viewer_sub(org, viewer, "sub_fail_1")

      event =
        build_connected_event(
          "invoice.payment_failed",
          %{"subscription" => "sub_fail_1"},
          org
        )

      assert :ok = perform_job(StripeWebhookProcessor, %{event: event, event_id: event["id"]})

      updated_viewer = Repo.get!(Bobine.Viewers.Viewer, viewer.id)
      assert updated_viewer.subscription_status == "past_due"
    end

    test "returns :ok when subscription not found" do
      org = connected_org()

      event =
        build_connected_event(
          "invoice.payment_failed",
          %{"subscription" => "sub_nonexistent"},
          org
        )

      assert :ok = perform_job(StripeWebhookProcessor, %{event: event, event_id: event["id"]})
    end
  end

  # ══════════════════════════════════════════════════════════════════════════
  # invoice.payment_succeeded
  # ══════════════════════════════════════════════════════════════════════════

  describe "connected invoice.payment_succeeded" do
    test "restores viewer access after payment recovery" do
      org = connected_org()
      viewer = insert(:viewer, organization: org, subscription_status: "past_due")
      _sub = insert_viewer_sub(org, viewer, "sub_recover_1", status: "past_due")

      event =
        build_connected_event(
          "invoice.payment_succeeded",
          %{"subscription" => "sub_recover_1"},
          org
        )

      assert :ok = perform_job(StripeWebhookProcessor, %{event: event, event_id: event["id"]})

      updated_viewer = Repo.get!(Bobine.Viewers.Viewer, viewer.id)
      assert updated_viewer.subscription_status == "active"
    end

    test "no-op when viewer already active" do
      org = connected_org()
      viewer = insert(:viewer, organization: org, subscription_status: "active")
      _sub = insert_viewer_sub(org, viewer, "sub_already_active")

      event =
        build_connected_event(
          "invoice.payment_succeeded",
          %{"subscription" => "sub_already_active"},
          org
        )

      assert :ok = perform_job(StripeWebhookProcessor, %{event: event, event_id: event["id"]})

      updated_viewer = Repo.get!(Bobine.Viewers.Viewer, viewer.id)
      assert updated_viewer.subscription_status == "active"
    end

    test "returns :ok when subscription not found" do
      org = connected_org()

      event =
        build_connected_event(
          "invoice.payment_succeeded",
          %{"subscription" => "sub_nonexistent"},
          org
        )

      assert :ok = perform_job(StripeWebhookProcessor, %{event: event, event_id: event["id"]})
    end
  end

  # ══════════════════════════════════════════════════════════════════════════
  # customer.subscription.deleted
  # ══════════════════════════════════════════════════════════════════════════

  describe "connected customer.subscription.deleted" do
    test "cancels viewer subscription and removes access" do
      org = connected_org()
      viewer = insert(:viewer, organization: org, subscription_status: "active")
      sub = insert_viewer_sub(org, viewer, "sub_delete_1")

      event =
        build_connected_event(
          "customer.subscription.deleted",
          %{"id" => "sub_delete_1"},
          org
        )

      assert :ok = perform_job(StripeWebhookProcessor, %{event: event, event_id: event["id"]})

      updated_viewer = Repo.get!(Bobine.Viewers.Viewer, viewer.id)
      assert updated_viewer.subscription_status == "canceled"

      updated_sub = Repo.get!(ViewerSubscription, sub.id)
      assert updated_sub.status == "canceled"
      assert updated_sub.canceled_at != nil
    end

    test "returns :ok when subscription not found" do
      org = connected_org()

      event =
        build_connected_event(
          "customer.subscription.deleted",
          %{"id" => "sub_nonexistent"},
          org
        )

      assert :ok = perform_job(StripeWebhookProcessor, %{event: event, event_id: event["id"]})
    end
  end

  # ══════════════════════════════════════════════════════════════════════════
  # customer.subscription.trial_will_end
  # ══════════════════════════════════════════════════════════════════════════

  describe "connected customer.subscription.trial_will_end" do
    test "handles trial ending notification gracefully" do
      org = connected_org()

      event =
        build_connected_event(
          "customer.subscription.trial_will_end",
          %{
            "id" => "sub_trial_end",
            "trial_end" => DateTime.utc_now() |> DateTime.add(3, :day) |> DateTime.to_unix()
          },
          org
        )

      assert :ok = perform_job(StripeWebhookProcessor, %{event: event, event_id: event["id"]})
    end
  end

  # ══════════════════════════════════════════════════════════════════════════
  # Unhandled connected account events (catch-all)
  # These are events Stripe sends that we don't process but must accept.
  # ══════════════════════════════════════════════════════════════════════════

  describe "unhandled connected account events" do
    @unhandled_events [
      {"charge.succeeded",
       %{"id" => "ch_1", "amount" => 999, "currency" => "usd", "status" => "succeeded"}},
      {"charge.updated", %{"id" => "ch_1", "amount" => 999}},
      {"payment_intent.created",
       %{"id" => "pi_1", "amount" => 999, "status" => "requires_payment_method"}},
      {"payment_intent.succeeded", %{"id" => "pi_1", "amount" => 999, "status" => "succeeded"}},
      {"payment_method.attached", %{"id" => "pm_1", "type" => "card", "customer" => "cus_1"}},
      {"customer.created", %{"id" => "cus_1", "email" => "test@example.com"}},
      {"customer.updated", %{"id" => "cus_1", "email" => "test@example.com"}},
      {"customer.subscription.created",
       %{"id" => "sub_1", "status" => "active", "customer" => "cus_1"}},
      {"invoice.created", %{"id" => "in_1", "subscription" => "sub_1", "status" => "draft"}},
      {"invoice.finalized", %{"id" => "in_2", "subscription" => "sub_1", "status" => "open"}},
      {"invoice.updated", %{"id" => "in_3", "subscription" => "sub_1", "status" => "open"}},
      {"invoice.paid", %{"id" => "in_4", "subscription" => "sub_1", "status" => "paid"}},
      {"invoice_payment.paid", %{"id" => "inpay_1", "invoice" => "in_1", "status" => "paid"}},
      {"setup_intent.created", %{"id" => "seti_1", "status" => "requires_payment_method"}},
      {"mandate.updated", %{"id" => "mandate_1", "status" => "active"}}
    ]

    for {event_type, object} <- @unhandled_events do
      @event_type event_type
      @object object

      test "#{event_type} returns :ok without error" do
        org = connected_org()

        event =
          build_connected_event(
            @event_type,
            @object,
            org
          )

        assert :ok = perform_job(StripeWebhookProcessor, %{event: event, event_id: event["id"]})
      end
    end
  end

  # ══════════════════════════════════════════════════════════════════════════
  # Event routing
  # ══════════════════════════════════════════════════════════════════════════

  describe "event routing" do
    test "connected event does NOT trigger platform billing handlers" do
      org = insert(:organization)
      plan = insert(:platform_plan, slug: "route_test_plan")

      insert(:platform_subscription,
        organization: org,
        platform_plan: plan,
        stripe_subscription_id: "sub_route_test_2"
      )

      event = %{
        "id" => "evt_connected_route",
        "type" => "customer.subscription.deleted",
        "account" => "acct_route_test",
        "data" => %{
          "object" => %{"id" => "sub_route_test_2"}
        }
      }

      assert :ok = perform_job(StripeWebhookProcessor, %{event: event, event_id: event["id"]})

      # Platform subscription should NOT be canceled
      assert {:ok, sub} = Bobine.PlatformBilling.get_subscription(org)
      assert sub.status == :active
    end

    test "platform event does NOT trigger connected account handlers" do
      event = %{
        "id" => "evt_platform_only",
        "type" => "checkout.session.completed",
        "data" => %{
          "object" => %{
            "metadata" => %{
              "organization_id" => Ecto.UUID.generate(),
              "platform_plan_id" => Ecto.UUID.generate()
            },
            "subscription" => "sub_plat_1",
            "customer" => "cus_plat_1"
          }
        }
      }

      assert :ok = perform_job(StripeWebhookProcessor, %{event: event, event_id: event["id"]})
      assert Repo.aggregate(ViewerSubscription, :count) == 0
    end

    test "unhandled platform event returns :ok" do
      event = %{
        "id" => "evt_platform_unknown",
        "type" => "some.unknown.event.type",
        "data" => %{"object" => %{}}
      }

      assert :ok = perform_job(StripeWebhookProcessor, %{event: event, event_id: event["id"]})
    end
  end

  # ══════════════════════════════════════════════════════════════════════════
  # Idempotency
  # ══════════════════════════════════════════════════════════════════════════

  describe "idempotency" do
    test "duplicate webhook does not create duplicate subscriptions" do
      org = connected_org()
      viewer = insert(:viewer, organization: org, subscription_status: "none")

      event =
        build_connected_event(
          "checkout.session.completed",
          %{
            "subscription" => "sub_idempotent",
            "customer" => "cus_idempotent",
            "customer_email" => viewer.email
          },
          org
        )

      assert :ok = perform_job(StripeWebhookProcessor, %{event: event, event_id: event["id"]})

      # Process again with a different event_id (simulating Stripe retry)
      _result =
        perform_job(StripeWebhookProcessor, %{
          event: event,
          event_id: "evt_connect_idempotent_2"
        })

      subs = Repo.all(from(s in ViewerSubscription, where: s.viewer_id == ^viewer.id))
      assert length(subs) == 1
    end

    test "payment_failed twice does not error" do
      org = connected_org()
      viewer = insert(:viewer, organization: org, subscription_status: "active")
      _sub = insert_viewer_sub(org, viewer, "sub_fail_twice")

      event =
        build_connected_event(
          "invoice.payment_failed",
          %{"subscription" => "sub_fail_twice"},
          org
        )

      assert :ok = perform_job(StripeWebhookProcessor, %{event: event, event_id: event["id"]})
      assert :ok = perform_job(StripeWebhookProcessor, %{event: event, event_id: "evt_retry"})

      updated_viewer = Repo.get!(Bobine.Viewers.Viewer, viewer.id)
      assert updated_viewer.subscription_status == "past_due"
    end
  end

  # ══════════════════════════════════════════════════════════════════════════
  # payment_intent.succeeded — PPV
  # ══════════════════════════════════════════════════════════════════════════

  describe "connected payment_intent.succeeded (PPV)" do
    test "creates a ticket when bobine_type is ppv" do
      org = connected_org()
      viewer = insert(:viewer, organization: org)

      event =
        insert(:live_event,
          organization: org,
          access_type: "pay_per_view",
          ppv_price_cents: 999
        )

      stripe_event =
        build_connected_event(
          "payment_intent.succeeded",
          %{
            "id" => "pi_ppv_001",
            "amount" => 999,
            "metadata" => %{
              "bobine_type" => "ppv",
              "bobine_org_id" => org.id,
              "bobine_viewer_id" => viewer.id,
              "bobine_live_event_id" => event.id
            }
          },
          org
        )

      assert :ok =
               perform_job(StripeWebhookProcessor, %{
                 event: stripe_event,
                 event_id: stripe_event["id"]
               })

      ticket = Repo.one!(from(t in LiveEventTicket, where: t.viewer_id == ^viewer.id))
      assert ticket.stripe_payment_intent_id == "pi_ppv_001"
      assert ticket.live_event_id == event.id
      assert ticket.organization_id == org.id
      assert ticket.refunded_at == nil
    end

    test "is idempotent — skips creation when ticket already exists for payment_intent" do
      org = connected_org()
      viewer = insert(:viewer, organization: org)

      event =
        insert(:live_event,
          organization: org,
          access_type: "pay_per_view",
          ppv_price_cents: 999
        )

      # Pre-insert the ticket as if the webhook was already processed
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      insert(:live_event_ticket,
        organization: org,
        live_event: event,
        viewer: viewer,
        stripe_payment_intent_id: "pi_ppv_idem",
        amount_cents: 999,
        access_starts_at: now,
        access_ends_at: DateTime.add(now, 48 * 3600, :second)
      )

      stripe_event =
        build_connected_event(
          "payment_intent.succeeded",
          %{
            "id" => "pi_ppv_idem",
            "amount" => 999,
            "metadata" => %{
              "bobine_type" => "ppv",
              "bobine_org_id" => org.id,
              "bobine_viewer_id" => viewer.id,
              "bobine_live_event_id" => event.id
            }
          },
          org
        )

      # Should not raise or create a second ticket
      assert :ok =
               perform_job(StripeWebhookProcessor, %{
                 event: stripe_event,
                 event_id: stripe_event["id"]
               })

      count =
        Repo.aggregate(from(t in LiveEventTicket, where: t.viewer_id == ^viewer.id), :count)

      assert count == 1
    end

    test "ignores payment_intent.succeeded without ppv metadata" do
      org = connected_org()

      stripe_event =
        build_connected_event(
          "payment_intent.succeeded",
          %{
            "id" => "pi_not_ppv",
            "amount" => 999,
            "metadata" => %{}
          },
          org
        )

      assert :ok =
               perform_job(StripeWebhookProcessor, %{
                 event: stripe_event,
                 event_id: stripe_event["id"]
               })

      assert 0 == Repo.aggregate(LiveEventTicket, :count)
    end

    test "handles unknown org gracefully" do
      org = connected_org()
      viewer = insert(:viewer, organization: org)

      event =
        insert(:live_event,
          organization: org,
          access_type: "pay_per_view",
          ppv_price_cents: 999
        )

      stripe_event = %{
        "id" => "evt_unknown_org",
        "type" => "payment_intent.succeeded",
        "account" => "acct_nonexistent",
        "data" => %{
          "object" => %{
            "id" => "pi_ppv_unknown",
            "amount" => 999,
            "metadata" => %{
              "bobine_type" => "ppv",
              "bobine_org_id" => org.id,
              "bobine_viewer_id" => viewer.id,
              "bobine_live_event_id" => event.id
            }
          }
        }
      }

      assert :ok =
               perform_job(StripeWebhookProcessor, %{
                 event: stripe_event,
                 event_id: stripe_event["id"]
               })

      assert 0 == Repo.aggregate(LiveEventTicket, :count)
    end
  end
end
