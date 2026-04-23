defmodule BobineWeb.Admin.LiveEventLive.NewTest do
  use BobineWeb.ConnCase, async: true

  import Mox
  import Phoenix.LiveViewTest

  alias Bobine.Content.MockMuxClient

  setup :verify_on_exit!

  defp mux_stream_stub do
    Mox.stub(MockMuxClient, :create_live_stream, fn _params ->
      {:ok,
       %{
         "id" => "mux_stream_test",
         "playback_ids" => [%{"id" => "pb_test", "policy" => "public"}],
         "stream_key" => "sk_test"
       }}
    end)
  end

  describe "access control" do
    test "admin can access new live event form", %{conn: _conn} do
      membership = insert(:membership, role: :admin)
      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/live-events/new")
      assert html =~ "New Live Event"
    end

    test "editor can access new live event form", %{conn: _conn} do
      membership = insert(:membership, role: :editor)
      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/live-events/new")
      assert html =~ "New Live Event"
    end

    test "unauthenticated user is redirected", %{conn: conn} do
      org = insert(:organization)
      conn = Map.put(conn, :host, "#{org.slug}.localhost")
      assert {:error, {:redirect, %{to: path}}} = live(conn, ~p"/admin/live-events/new")
      assert path == ~p"/users/log-in"
    end
  end

  describe "form rendering" do
    test "renders all required fields", %{conn: _conn} do
      membership = insert(:membership, role: :editor)
      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/live-events/new")

      assert html =~ ~s(data-test="title-input")
      assert html =~ ~s(data-test="slug-input")
      assert html =~ ~s(data-test="description-input")
      assert html =~ ~s(data-test="scheduled-start-input")
      assert html =~ ~s(data-test="access-type-select")
      assert html =~ ~s(data-test="save-btn")
      assert html =~ ~s(data-test="cancel-btn")
    end

    test "PPV fields are hidden by default", %{conn: _conn} do
      membership = insert(:membership, role: :editor)
      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/live-events/new")

      refute html =~ ~s(data-test="ppv-fields")
    end

    test "PPV fields appear when access_type is pay_per_view", %{conn: _conn} do
      membership = insert(:membership, role: :editor)
      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/live-events/new")

      html =
        view
        |> element(~s(#live-event-form))
        |> render_change(%{"live_event" => %{"access_type" => "pay_per_view"}})

      assert html =~ ~s(data-test="ppv-fields")
      assert html =~ ~s(data-test="ppv-price-input")
      assert html =~ ~s(data-test="ppv-window-input")
    end

    test "PPV fields disappear when access_type changes to public", %{conn: _conn} do
      membership = insert(:membership, role: :editor)
      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/live-events/new")

      # First enable PPV fields
      view
      |> element(~s(#live-event-form))
      |> render_change(%{"live_event" => %{"access_type" => "pay_per_view"}})

      # Then switch to public
      html =
        view
        |> element(~s(#live-event-form))
        |> render_change(%{"live_event" => %{"access_type" => "public"}})

      refute html =~ ~s(data-test="ppv-fields")
    end
  end

  describe "form submission" do
    test "creates live event and redirects to show page", %{conn: _conn} do
      membership = insert(:membership, role: :editor)
      mux_stream_stub()

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/live-events/new")

      assert {:error, {:live_redirect, %{to: redirect_path}}} =
               view
               |> element(~s(#live-event-form))
               |> render_submit(%{
                 "live_event" => %{
                   "title" => "Test Stream",
                   "slug" => "test-stream",
                   "scheduled_start_at" => "2026-06-01T18:00",
                   "access_type" => "subscribers_only"
                 }
               })

      assert redirect_path =~ "/admin/live-events/test-stream"
    end

    test "shows validation errors on invalid submission", %{conn: _conn} do
      membership = insert(:membership, role: :editor)

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/live-events/new")

      html =
        view
        |> element(~s(#live-event-form))
        |> render_submit(%{
          "live_event" => %{
            "title" => "",
            "slug" => "",
            "access_type" => "subscribers_only"
          }
        })

      assert html =~ "can&#39;t be blank"
    end

    test "shows error when Mux provisioning fails", %{conn: _conn} do
      membership = insert(:membership, role: :editor)

      Mox.stub(MockMuxClient, :create_live_stream, fn _params ->
        {:error, :mux_error, %{type: "api_error", messages: ["quota exceeded"]}}
      end)

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/live-events/new")

      view
      |> element(~s(#live-event-form))
      |> render_submit(%{
        "live_event" => %{
          "title" => "Test Stream",
          "slug" => "test-stream",
          "scheduled_start_at" => "2026-06-01T18:00",
          "access_type" => "subscribers_only"
        }
      })

      # Flash is rendered in the next render cycle
      html = render(view)
      assert html =~ "Could not provision Mux stream"
    end

    test "creates PPV event with price in dollars (converted to cents)", %{conn: _conn} do
      membership = insert(:membership, role: :editor)
      mux_stream_stub()

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/live-events/new")

      assert {:error, {:live_redirect, %{to: redirect_path}}} =
               view
               |> element(~s(#live-event-form))
               |> render_submit(%{
                 "live_event" => %{
                   "title" => "PPV Stream",
                   "slug" => "ppv-stream",
                   "scheduled_start_at" => "2026-06-01T18:00",
                   "access_type" => "pay_per_view",
                   "ppv_price_dollars" => "9.99",
                   "ppv_access_window_hours" => "48"
                 }
               })

      assert redirect_path =~ "/admin/live-events/ppv-stream"
    end
  end

  describe "slug auto-generation" do
    test "blurring the title field auto-generates slug", %{conn: _conn} do
      membership = insert(:membership, role: :editor)
      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/live-events/new")

      html =
        view
        |> element(~s([data-test="title-input"]))
        |> render_blur(%{"title" => "My Awesome Stream"})

      assert html =~ "my-awesome-stream"
    end
  end
end
