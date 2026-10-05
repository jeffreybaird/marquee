defmodule Marquee.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :marquee

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  @doc """
  Seeds the content-rich demo organizations from a running release (no Mix).

  Boots the full application (Repo, PubSub, Req, Mux client) — `migrate/0`'s
  `with_repo` starts only the Repo, which is not enough for the seeder's
  Pexels/Mux calls — then delegates to `Marquee.DemoSeeder.seed/1`. Accepts the
  same options: `:pexels_key` (falls back to the `PEXELS_API_KEY` env var),
  `:org` (single slug), `:force` (recreate existing).

  Run on the droplet's migrate runner:

      docker compose --profile tools run --rm migrate \\
        bin/marquee eval 'Marquee.Release.seed_demo([])'
  """
  def seed_demo(opts \\ []) do
    start_app()
    Marquee.DemoSeeder.seed(opts)
  end

  @doc "Seeds the Workshop subscriber portfolio demo using a reviewed configured media manifest."
  def seed_subscriber_demo do
    start_app()
    Marquee.DemoSeeder.seed_subscriber_demo()
  end

  @doc """
  Reconciles pending Mux assets against Mux's current state from a running
  release (no Mix). Boots the full app, then delegates to
  `Marquee.Content.reconcile_pending_mux_assets/1`.

  Use after a bulk seed or a domain move, when assets finished processing while
  no webhook endpoint was reachable, to flip them `preparing` -> `ready`.

      docker compose --profile tools run --rm migrate \\
        bin/marquee eval 'Marquee.Release.reconcile_mux()'
  """
  def reconcile_mux(opts \\ []) do
    start_app()
    Marquee.Content.reconcile_pending_mux_assets(opts)
  end

  @doc """
  Creates (or promotes) a super admin and prints a one-time magic-link login
  URL for `host`, so platform access can be bootstrapped on a fresh deploy with
  no mailer configured. The link is valid for 15 minutes.

      docker compose --profile tools run --rm migrate \\
        bin/marquee eval 'Marquee.Release.create_super_admin("me@example.com", "marquee.jeffreybaird.com")'
  """
  def create_super_admin(email, host) do
    start_app()

    case Marquee.Accounts.create_super_admin_with_login(email) do
      {:ok, %{user: user, token: token}} ->
        url = "https://#{host}/users/log-in/#{token}"
        IO.puts("\nSuper admin ready: #{user.email}\nMagic login (15 min): #{url}\n")
        {:ok, url}

      {:error, _, _} = error ->
        IO.puts("\nFailed to create super admin: #{inspect(error)}\n")
        error
    end
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  @doc "Prepares and enqueues only the exact configured admin-demo service hostname, even while visitor access is disabled."
  def configure_admin_demo_host do
    with_tenant_repo(fn ->
      with_tenant_enqueue_services(fn ->
        configure_admin_demo_host_with_services()
      end)
    end)
  end

  defp configure_admin_demo_host_with_services do
    with {:ok, org} <-
           Marquee.AdminDemo.configure_host(Application.get_env(:marquee, :admin_demo, [])[:host]),
         {:ok, domain} <- Marquee.TenantDomains.request_demo_host_provisioning(org) do
      IO.puts(Jason.encode!(%{hostname: domain.hostname, status: domain.status}))
      {:ok, %{organization: org, domain: domain}}
    end
  end

  @doc "Prints a sanitized JSON hostname migration plan using only Repo. Accepts bounded cutoff, slug allowlist and keyset options."
  def tenant_domain_snapshot(opts \\ []) do
    with_tenant_repo(fn ->
      plan = Marquee.TenantDomains.migration_snapshot(opts)

      printable = %{
        plan
        | cursor: encode_tenant_cursor(plan.cursor),
          next_cursor: encode_tenant_cursor(plan.next_cursor)
      }

      IO.puts(Jason.encode!(printable))
      plan
    end)
  end

  @doc "Applies the exact reviewed JSON plan from a file, durably enqueueing jobs without starting any worker queues."
  def tenant_domain_apply(path) do
    with {:ok, bytes} <- File.read(path),
         {:ok, json} <- Jason.decode(bytes),
         {:ok, plan} <- decode_tenant_plan(json) do
      with_tenant_repo(fn -> apply_tenant_plan(plan) end)
    else
      _ -> {:error, :invalid_snapshot}
    end
  end

  @doc "Prints one sanitized page of hostname provisioning statuses. Uses Repo only."
  def tenant_domain_status(opts \\ []) do
    with_tenant_repo(fn ->
      page = Marquee.Admin.list_organizations(opts)

      results =
        Enum.map(page.results, fn org ->
          domain = Marquee.TenantDomains.get_domain(org)

          %{
            organization_id: org.id,
            slug: org.slug,
            hostname: domain && domain.hostname,
            status: domain && domain.status,
            last_error: domain && domain.last_error
          }
        end)

      result = %{page | results: results}
      IO.puts(Jason.encode!(result))
      result
    end)
  end

  @doc "Retries one explicitly identified organization's existing allocation without running provider work in the release process."
  def tenant_domain_retry(organization_id) do
    with_tenant_repo(fn ->
      with {:ok, org} <- Marquee.Accounts.get_organization(organization_id),
           domain when not is_nil(domain) <- Marquee.TenantDomains.get_domain(org) do
        retry_tenant_domain(org, domain)
      else
        _ -> {:error, :not_found}
      end
    end)
  end

  defp apply_tenant_plan(plan) do
    with_tenant_enqueue_services(fn ->
      result = Marquee.TenantDomains.apply_snapshot(plan)
      print_tenant_result(result)
      result
    end)
  end

  defp retry_tenant_domain(org, domain) do
    with_tenant_enqueue_services(fn ->
      result = Marquee.TenantDomains.request_provisioning(org, source: domain.eligibility_source)
      print_tenant_result(result)
      result
    end)
  end

  defp with_tenant_repo(fun) do
    load_app()
    {:ok, result, _} = Ecto.Migrator.with_repo(Marquee.Repo, fn _repo -> fun.() end)
    result
  end

  defp with_tenant_enqueue_services(fun) do
    {:ok, _} = Application.ensure_all_started(:oban)

    if Oban.whereis(Oban) do
      fun.()
    else
      {:ok, _} = Application.ensure_all_started(:phoenix_pubsub)

      children = [
        {Phoenix.PubSub, name: Marquee.PubSub},
        Marquee.Events.AuditSubscriber,
        {Oban, repo: Marquee.Repo, queues: false, plugins: false, peer: false, testing: :manual}
      ]

      {:ok, supervisor} = Supervisor.start_link(children, strategy: :one_for_one)

      try do
        result = fun.()
        :sys.get_state(Marquee.Events.AuditSubscriber)
        result
      after
        Supervisor.stop(supervisor)
      end
    end
  end

  defp encode_tenant_cursor(nil), do: nil
  defp encode_tenant_cursor({time, id}), do: [DateTime.to_iso8601(time), id]

  defp decode_tenant_plan(%{
         "cutoff" => cutoff,
         "host_pattern" => pattern,
         "organizations" => entries
       })
       when is_binary(cutoff) and is_binary(pattern) and is_list(entries) and
              length(entries) <= 100 do
    with {:ok, cutoff, _} <- DateTime.from_iso8601(cutoff),
         {:ok, organizations} <- decode_tenant_entries(entries) do
      {:ok, %{cutoff: cutoff, host_pattern: pattern, organizations: organizations}}
    else
      _ -> {:error, :invalid_snapshot}
    end
  end

  defp decode_tenant_plan(_), do: {:error, :invalid_snapshot}

  defp decode_tenant_entries(entries) do
    Enum.reduce_while(entries, {:ok, []}, fn entry, {:ok, acc} ->
      case decode_tenant_entry(entry) do
        {:ok, decoded} -> {:cont, {:ok, [decoded | acc]}}
        _ -> {:halt, {:error, :invalid_snapshot}}
      end
    end)
  end

  defp decode_tenant_entry(%{
         "organization_id" => id,
         "slug" => slug,
         "hostname" => host,
         "inserted_at" => time
       })
       when is_binary(id) and is_binary(slug) and is_binary(host) and is_binary(time) do
    with {:ok, _} <- Ecto.UUID.cast(id), {:ok, time, _} <- DateTime.from_iso8601(time) do
      {:ok, %{organization_id: id, slug: slug, hostname: host, inserted_at: time}}
    end
  end

  defp decode_tenant_entry(_), do: {:error, :invalid_snapshot}

  defp print_tenant_result({:ok, result}) do
    count = if is_list(result), do: length(result), else: 1
    IO.puts(Jason.encode!(%{enqueued: count}))
  end

  defp print_tenant_result({:error, reason}), do: IO.puts(Jason.encode!(%{error: reason}))

  defp load_app do
    # Many platforms require SSL when connecting to the database
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end

  defp start_app do
    Application.ensure_all_started(:ssl)
    {:ok, _} = Application.ensure_all_started(@app)
    :ok
  end
end
