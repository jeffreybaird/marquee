defmodule BobineWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use BobineWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  alias Bobine.Accounts
  alias Bobine.Accounts.{Membership, Scope, User}
  alias Bobine.AccountsFixtures
  alias Bobine.Repo
  alias Bobine.Viewers
  alias Bobine.Viewers.Viewer

  using do
    quote do
      # The default endpoint for testing
      @endpoint BobineWeb.Endpoint

      use BobineWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import BobineWeb.ConnCase
      import Bobine.Factory
    end
  end

  setup tags do
    Bobine.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc """
  Setup helper that registers and logs in users.

      setup :register_and_log_in_user

  It stores an updated connection and a registered user in the
  test context.
  """
  def register_and_log_in_user(%{conn: conn} = context) do
    user = AccountsFixtures.user_fixture()
    scope = Scope.for_user(user)

    opts =
      context
      |> Map.take([:token_authenticated_at])
      |> Enum.into([])

    %{conn: log_in_user(conn, user, opts), user: user, scope: scope}
  end

  @doc """
  Builds an authenticated conn for the given membership.

  Sets the conn host to `<org.slug>.localhost` so that the SetOrganization
  plug resolves the organization via subdomain, and logs in as the
  membership's user. Used in RBAC and multi-tenant tests.
  """
  def conn_for(%Membership{} = membership) do
    membership = Repo.preload(membership, [:user, :organization])

    Phoenix.ConnTest.build_conn()
    |> Map.put(:host, "#{membership.organization.slug}.localhost")
    |> log_in_user(membership.user)
  end

  @doc """
  Builds an authenticated conn for a super admin user.

  The host is left as `localhost` (no subdomain) since super admin routes do
  not resolve an organization.
  """
  def conn_for_super_admin(%User{is_super_admin: true} = user) do
    Phoenix.ConnTest.build_conn()
    |> log_in_user(user)
  end

  @doc """
  Logs the given `user` into the `conn`.

  It returns an updated `conn`.
  """
  def log_in_user(conn, user, opts \\ []) do
    token = Accounts.generate_user_session_token(user)

    maybe_set_token_authenticated_at(token, opts[:token_authenticated_at])

    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_token, token)
  end

  defp maybe_set_token_authenticated_at(_token, nil), do: nil

  defp maybe_set_token_authenticated_at(token, authenticated_at) do
    AccountsFixtures.override_token_authenticated_at(token, authenticated_at)
  end

  @doc """
  Builds a conn authenticated as a viewer on the given organization.

  Sets the conn host to `<org.slug>.localhost` and puts the viewer session token.
  """
  def conn_for_viewer(%Viewer{} = viewer) do
    viewer = Repo.preload(viewer, [:organization])
    token = Viewers.generate_viewer_session_token(viewer)

    Phoenix.ConnTest.build_conn()
    |> Map.put(:host, "#{viewer.organization.slug}.localhost")
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:viewer_token, token)
  end

  @doc """
  Builds a conn authenticated as both an operator and viewing as a viewer (impersonation).
  """
  def conn_for_impersonating_viewer(
        %Membership{} = membership,
        %Viewer{} = viewer
      ) do
    membership = Repo.preload(membership, [:user, :organization])

    conn_for(membership)
    |> Plug.Conn.put_session(:impersonating_viewer_id, viewer.id)
    |> Plug.Conn.put_session(:impersonating_admin_user_id, membership.user.id)
    |> Plug.Conn.put_session(:impersonating_return_path, "/admin/members")
    |> Plug.Conn.put_session(:impersonation_started_at, System.system_time(:second))
  end
end
