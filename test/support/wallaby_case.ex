defmodule BobineWeb.WallabyCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      use Wallaby.DSL
      import Wallaby.Query
      import Bobine.Factory
      import BobineWeb.WallabyCase, only: [log_in_session: 2, log_in_session: 3]

      alias BobineWeb.Endpoint

      @endpoint BobineWeb.Endpoint
    end
  end

  setup tags do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Bobine.Repo)

    unless tags[:async] do
      Ecto.Adapters.SQL.Sandbox.mode(Bobine.Repo, {:shared, self()})
    end

    metadata = Phoenix.Ecto.SQL.Sandbox.metadata_for(Bobine.Repo, self())
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
    import Bobine.AccountsFixtures, only: [generate_user_magic_link_token: 1]

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
    # Visit the org-specific admin page to seed organization_id into the new session
    |> Wallaby.Browser.visit("/admin?org=#{org.slug}")
  end

  @doc """
  Logs a user in via magic link without navigating to an org page.
  Use for tests that don't require org resolution (e.g. auth page tests).
  """
  def log_in_session(session, user) do
    import Bobine.AccountsFixtures, only: [generate_user_magic_link_token: 1]

    {encoded_token, _raw_token} = generate_user_magic_link_token(user)

    session = Wallaby.Browser.visit(session, "/users/log-in/#{encoded_token}")

    button_text =
      if Wallaby.Browser.has?(session, Wallaby.Query.button("Confirm and stay logged in")) do
        "Confirm and stay logged in"
      else
        "Keep me logged in on this device"
      end

    Wallaby.Browser.click(session, Wallaby.Query.button(button_text))
  end
end
