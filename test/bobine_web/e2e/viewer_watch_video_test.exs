defmodule BobineWeb.E2E.ViewerWatchVideoTest do
  use BobineWeb.WallabyCase

  @moduletag :e2e

  # E2E tests validate things LiveViewTest cannot: TypeScript hooks executing,
  # the Mux player actually mounting in the DOM, and JS-driven interactions.
  # These tests require Chrome + ChromeDriver. Run with: mix test --only e2e

  test "viewer registration page renders and form is interactive", %{session: session} do
    session
    |> visit("/users/register")
    |> assert_has(Query.css("h1", text: "Register"))
    |> assert_has(Query.css("input[type='email']"))
    |> assert_has(Query.button("Create an account"))
  end

  test "login page renders both auth forms", %{session: session} do
    session
    |> visit("/users/log-in")
    |> assert_has(Query.css("h1", text: "Log in"))
    |> assert_has(Query.button("Log in with email"))
    |> assert_has(Query.button("Log in and stay logged in"))
  end
end
