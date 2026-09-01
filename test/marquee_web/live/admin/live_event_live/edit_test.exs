defmodule MarqueeWeb.Admin.LiveEventLive.EditTest do
  use MarqueeWeb.ConnCase, async: true

  import Mox
  import Phoenix.LiveViewTest

  setup :verify_on_exit!

  describe "access control" do
    test "editor can access edit form", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)
      event = insert(:live_event, organization: org)

      {:ok, _view, html} =
        live(conn_for(membership), ~p"/admin/live-events/#{event.slug}/edit")

      assert html =~ "Edit Live Event"
      assert html =~ event.title
    end

    test "redirects to index for unknown slug", %{conn: _conn} do
      membership = insert(:membership, role: :editor)

      assert {:error, {:live_redirect, %{to: path}}} =
               live(conn_for(membership), ~p"/admin/live-events/nonexistent/edit")

      assert path == ~p"/admin/live-events"
    end

    test "unauthenticated user is redirected", %{conn: conn} do
      org = insert(:organization)
      event = insert(:live_event, organization: org)
      conn = Map.put(conn, :host, "#{org.slug}.localhost")

      assert {:error, {:redirect, %{to: path}}} =
               live(conn, ~p"/admin/live-events/#{event.slug}/edit")

      assert path == ~p"/users/log-in"
    end
  end

  describe "form rendering" do
    test "pre-populates form with existing values", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)

      event =
        insert(:live_event,
          organization: org,
          title: "Existing Title",
          description: "Existing description",
          access_type: "public"
        )

      {:ok, _view, html} =
        live(conn_for(membership), ~p"/admin/live-events/#{event.slug}/edit")

      assert html =~ "Existing Title"
      assert html =~ "Existing description"
    end

    test "shows PPV fields when event has pay_per_view access type", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)

      event =
        insert(:live_event,
          organization: org,
          access_type: "pay_per_view",
          ppv_price_cents: 999,
          ppv_access_window_hours: 24
        )

      {:ok, _view, html} =
        live(conn_for(membership), ~p"/admin/live-events/#{event.slug}/edit")

      assert html =~ ~s(data-test="ppv-fields")
    end

    test "PPV fields appear when access_type changed to pay_per_view", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)
      event = insert(:live_event, organization: org, access_type: "public")

      {:ok, view, html} =
        live(conn_for(membership), ~p"/admin/live-events/#{event.slug}/edit")

      refute html =~ ~s(data-test="ppv-fields")

      html =
        view
        |> element(~s(#live-event-edit-form))
        |> render_change(%{"live_event" => %{"access_type" => "pay_per_view"}})

      assert html =~ ~s(data-test="ppv-fields")
    end
  end

  describe "form submission" do
    test "updates event and redirects to show page", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)
      event = insert(:live_event, organization: org, title: "Original Title")

      {:ok, view, _html} =
        live(conn_for(membership), ~p"/admin/live-events/#{event.slug}/edit")

      assert {:error, {:live_redirect, %{to: redirect_path}}} =
               view
               |> element(~s(#live-event-edit-form))
               |> render_submit(%{
                 "live_event" => %{
                   "title" => "Updated Title",
                   "slug" => event.slug,
                   "scheduled_start_at" => "2026-06-01T18:00",
                   "access_type" => "subscribers_only"
                 }
               })

      assert redirect_path =~ "/admin/live-events/#{event.slug}"
    end

    test "shows validation errors on invalid submission", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)
      event = insert(:live_event, organization: org)

      {:ok, view, _html} =
        live(conn_for(membership), ~p"/admin/live-events/#{event.slug}/edit")

      html =
        view
        |> element(~s(#live-event-edit-form))
        |> render_submit(%{
          "live_event" => %{
            "title" => "",
            "slug" => "",
            "access_type" => "subscribers_only"
          }
        })

      assert html =~ "can&#39;t be blank"
    end

    test "updates PPV event with price in dollars (converted to cents)", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)

      event =
        insert(:live_event,
          organization: org,
          access_type: "pay_per_view",
          ppv_price_cents: 999,
          ppv_access_window_hours: 24
        )

      {:ok, view, _html} =
        live(conn_for(membership), ~p"/admin/live-events/#{event.slug}/edit")

      assert {:error, {:live_redirect, %{to: redirect_path}}} =
               view
               |> element(~s(#live-event-edit-form))
               |> render_submit(%{
                 "live_event" => %{
                   "title" => event.title,
                   "slug" => event.slug,
                   "scheduled_start_at" => "2026-06-01T18:00",
                   "access_type" => "pay_per_view",
                   "ppv_price_dollars" => "14.99",
                   "ppv_access_window_hours" => "48"
                 }
               })

      assert redirect_path =~ "/admin/live-events/#{event.slug}"
    end

    test "renders cancel link back to show page", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)
      event = insert(:live_event, organization: org)

      {:ok, _view, html} =
        live(conn_for(membership), ~p"/admin/live-events/#{event.slug}/edit")

      assert html =~ ~s(data-test="cancel-btn")
    end
  end
end
