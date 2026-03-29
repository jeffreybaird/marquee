defmodule Bobine.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :bobine

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  @doc """
  Creates a super admin user. Run from the deployed instance:

      bin/bobine eval "Bobine.Release.create_admin(\"you@example.com\")"
  """
  def create_admin(email) do
    start_app()

    case Bobine.Accounts.register_user(%{email: email}) do
      {:ok, user} ->
        {:ok, user} = Bobine.Admin.grant_super_admin(user)
        IO.puts("Created super admin: #{user.email} (id: #{user.id})")

      {:error, :validation, changeset} ->
        # User may already exist — find and promote
        case Bobine.Accounts.get_user_by_email(email) do
          nil ->
            IO.puts("Failed to create user: #{inspect(changeset.errors)}")

          user ->
            {:ok, user} = Bobine.Admin.grant_super_admin(user)
            IO.puts("Promoted existing user to super admin: #{user.email}")
        end
    end
  end

  @doc """
  Creates a super admin and prints a magic login URL.
  No email delivery needed.

      bin/bobine eval "Bobine.Release.create_admin_with_login(\"you@example.com\", \"yourdomain.com\")"
  """
  def create_admin_with_login(email, host \\ "localhost:4000") do
    start_app()

    user =
      case Bobine.Accounts.get_user_by_email(email) do
        nil ->
          {:ok, user} = Bobine.Accounts.register_user(%{email: email})
          user

        user ->
          user
      end

    {:ok, _} = Bobine.Admin.grant_super_admin(user)

    {encoded_token, user_token} =
      Bobine.Accounts.UserToken.build_email_token(user, "magic_link")

    Bobine.Repo.insert!(user_token)

    url = "https://#{host}/users/log-in/#{encoded_token}"
    IO.puts("\nSuper admin created: #{email}")
    IO.puts("\nLogin URL (use within 30 minutes):\n")
    IO.puts(url)
    IO.puts("")
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    # Many platforms require SSL when connecting to the database
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end

  defp start_app do
    load_app()
    Application.ensure_all_started(@app)
  end
end
