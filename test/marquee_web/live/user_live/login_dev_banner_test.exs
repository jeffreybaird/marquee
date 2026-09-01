defmodule MarqueeWeb.UserLive.LoginDevBannerTest do
  # async: false — these tests mutate global Application env (:dev_routes and the
  # Mailer adapter), which would race other tests under async execution.
  use MarqueeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  setup do
    prev_dev_routes = Application.get_env(:marquee, :dev_routes, false)
    prev_mailer = Application.get_env(:marquee, Marquee.Mailer)

    on_exit(fn ->
      Application.put_env(:marquee, :dev_routes, prev_dev_routes)
      Application.put_env(:marquee, Marquee.Mailer, prev_mailer)
    end)

    :ok
  end

  test "hides the dev mailbox banner when dev routes are off (prod-like)", %{conn: conn} do
    # Simulate prod: dev routes disabled AND the local mail adapter in use.
    # The banner links to a dev-only route, so it must not render.
    Application.put_env(:marquee, :dev_routes, false)
    Application.put_env(:marquee, Marquee.Mailer, adapter: Swoosh.Adapters.Local)

    {:ok, _lv, html} = live(conn, ~p"/users/log-in")

    refute html =~ "/dev/mailbox"
    refute html =~ "local mail adapter"
  end

  test "shows the dev mailbox banner when dev routes and local adapter are on", %{conn: conn} do
    Application.put_env(:marquee, :dev_routes, true)
    Application.put_env(:marquee, Marquee.Mailer, adapter: Swoosh.Adapters.Local)

    {:ok, _lv, html} = live(conn, ~p"/users/log-in")

    assert html =~ "/dev/mailbox"
  end
end
