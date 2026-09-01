defmodule MarqueeWeb.WallabyCase do
  @moduledoc false
  use ExUnit.CaseTemplate

  using do
    quote do
      use Wallaby.DSL
      import Wallaby.Query
      import Marquee.Factory
      import MarqueeWeb.WallabyCase, only: [log_in_session: 2, log_in_session: 3]

      alias MarqueeWeb.Endpoint

      @endpoint MarqueeWeb.Endpoint
    end
  end

  setup tags do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Marquee.Repo)

    unless tags[:async] do
      Ecto.Adapters.SQL.Sandbox.mode(Marquee.Repo, {:shared, self()})
    end

    metadata = Phoenix.Ecto.SQL.Sandbox.metadata_for(Marquee.Repo, self())
    {:ok, session} = Wallaby.start_session(metadata: metadata)
    {:ok, session: session}
  end

  @doc """
  Logs a user in via magic link and navigates to the given org's admin dashboard.

  The `org` argument is required for admin-route E2E tests because login clears
  the session (session fixation protection), so the `organization_id` must be
  re-seeded by visiting a page with `?org=slug` AFTER the new session is created.
  """
  def log_in_session(session, user, org) do
    import Marquee.AccountsFixtures, only: [generate_user_magic_link_token: 1]

    {encoded_token, _raw_token} = generate_user_magic_link_token(user)

    session = Wallaby.Browser.visit(session, "/users/log-in/#{encoded_token}")

    # Confirmed users see "Keep me logged in", unconfirmed see "Confirm and stay logged in"
    button_text =
      if Wallaby.Browser.has?(session, Wallaby.Query.button("Confirm and stay logged in")) do
        "Confirm and stay logged in"
      else
        "Keep me logged in on this device"
      end

    session
    |> Wallaby.Browser.click(Wallaby.Query.button(button_text))
    # `phx-trigger-action` submits the login form asynchronously after the
    # LiveView re-render, so Wallaby's click returns before the redirect
    # that sets the session cookie has landed. Wait for the confirmation
    # button to disappear before forcing the org context — otherwise the
    # follow-up visit races the cookie write and lands back on /log-in.
    |> wait_until_gone(Wallaby.Query.button(button_text))
    # Visit the org-specific admin page to seed organization_id into the new session
    |> Wallaby.Browser.visit("/admin?org=#{org.slug}")
  end

  @doc """
  Logs a user in via magic link without navigating to an org page.
  Use for tests that don't require org resolution (e.g. auth page tests).
  """
  def log_in_session(session, user) do
    import Marquee.AccountsFixtures, only: [generate_user_magic_link_token: 1]

    {encoded_token, _raw_token} = generate_user_magic_link_token(user)

    session = Wallaby.Browser.visit(session, "/users/log-in/#{encoded_token}")

    button_text =
      if Wallaby.Browser.has?(session, Wallaby.Query.button("Confirm and stay logged in")) do
        "Confirm and stay logged in"
      else
        "Keep me logged in on this device"
      end

    session
    |> Wallaby.Browser.click(Wallaby.Query.button(button_text))
    |> wait_until_gone(Wallaby.Query.button(button_text))
  end

  # Polls up to `timeout_ms` for the given query to stop matching. Used after
  # clicking a `phx-trigger-action` submit button so the subsequent navigation
  # step doesn't race the form POST that sets the session cookie.
  defp wait_until_gone(session, query, timeout_ms \\ 5_000, step_ms \\ 50) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_wait_until_gone(session, query, deadline, step_ms)
  end

  defp do_wait_until_gone(session, query, deadline, step_ms) do
    if Wallaby.Browser.has?(session, query) do
      if System.monotonic_time(:millisecond) >= deadline do
        session
      else
        Process.sleep(step_ms)
        do_wait_until_gone(session, query, deadline, step_ms)
      end
    else
      session
    end
  end
end
