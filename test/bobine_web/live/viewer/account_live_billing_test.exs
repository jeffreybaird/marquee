defmodule BobineWeb.Viewer.AccountLiveBillingTest do
  use BobineWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "GET /account — subscription section" do
    test "active subscriber sees plan info and manage button", %{conn: _conn} do
      org =
        insert(:organization,
          stripe_connect_onboarding_complete: true,
          stripe_connect_account_id: "acct_test"
        )

      viewer =
        insert(:viewer,
          organization: org,
          subscription_status: "active",
          stripe_customer_id: "cus_test"
        )

      {:ok, view, _html} = live(conn_for_viewer(viewer), ~p"/account")
      assert has_element?(view, "[data-test='subscription-active-status']")
      assert has_element?(view, "[data-test='manage-subscription-btn']")
    end

    test "trialing viewer sees trial end date", %{conn: _conn} do
      org = insert(:organization)
      trial_end = DateTime.add(DateTime.utc_now(), 14, :day) |> DateTime.truncate(:second)

      viewer =
        insert(:viewer,
          organization: org,
          subscription_status: "trial",
          trial_expires_at: trial_end
        )

      {:ok, view, _html} = live(conn_for_viewer(viewer), ~p"/account")
      assert has_element?(view, "[data-test='subscription-trial-status']")
    end

    test "past_due viewer sees warning and update payment button", %{conn: _conn} do
      org = insert(:organization)

      viewer =
        insert(:viewer,
          organization: org,
          subscription_status: "past_due",
          stripe_customer_id: "cus_test"
        )

      {:ok, view, _html} = live(conn_for_viewer(viewer), ~p"/account")
      assert has_element?(view, "[data-test='subscription-past-due-status']")
      assert has_element?(view, "[data-test='update-payment-btn']")
    end

    test "canceled viewer sees resubscribe link", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org, subscription_status: "canceled")

      {:ok, view, _html} = live(conn_for_viewer(viewer), ~p"/account")
      assert has_element?(view, "[data-test='subscription-canceled-status']")
      assert has_element?(view, "[data-test='resubscribe-link']")
    end

    test "no subscription shows subscribe link", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org, subscription_status: "none")

      {:ok, view, _html} = live(conn_for_viewer(viewer), ~p"/account")
      assert has_element?(view, "[data-test='subscription-none-status']")
      assert has_element?(view, "[data-test='subscribe-link']")
    end
  end
end
