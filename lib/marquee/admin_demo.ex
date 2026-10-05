defmodule Marquee.AdminDemo do
  @moduledoc "Private, bounded admin sandboxes with independent capability sessions and permanent media protection."
  import Ecto.Query
  require Marquee.Otel

  alias Marquee.{Accounts, Admin, Events, Repo}
  alias Marquee.Accounts.{Membership, Organization, Scope, User}
  alias Marquee.AdminDemo.{Catalog, ProtectedAsset, Session}

  @doc "Checks the configured dedicated host exactly."
  def host?(host), do: is_binary(host) and host == config()[:host]

  @doc "Returns the public entry URL only after the configured service host is ready and visitor access is enabled. Requires database access."
  def entry_url do
    if enabled?(), do: ready_entry_url(Admin.admin_demo_host(config()[:host]))
  end

  defp ready_entry_url(%{demo_kind: :admin_demo_host} = org) do
    case Marquee.TenantDomains.ready_domain(org) do
      %{hostname: host} -> if host == config()[:host], do: "https://#{host}/demo/admin"
      _ -> nil
    end
  end

  defp ready_entry_url(_), do: nil

  @doc """
  Checks the server's visitor-entry switch.

      iex> previous = Application.fetch_env(:marquee, :admin_demo)
      iex> try do
      ...>   Application.put_env(:marquee, :admin_demo, enabled: true)
      ...>   Marquee.AdminDemo.enabled?()
      ...> after
      ...>   case previous do
      ...>     {:ok, config} -> Application.put_env(:marquee, :admin_demo, config)
      ...>     :error -> Application.delete_env(:marquee, :admin_demo)
      ...>   end
      ...> end
      true
  """
  def enabled?, do: config()[:enabled] == true

  @doc """
  Identifies an internal demo organization, including a retained tombstone.

      iex> Marquee.AdminDemo.demo_organization?(%{demo_kind: :admin_sandbox})
      true
      iex> Marquee.AdminDemo.demo_organization?(%{demo_kind: nil})
      false
  """
  def demo_organization?(%{demo_kind: kind}), do: kind in [:admin_demo_host, :admin_sandbox]
  def demo_organization?(_), do: false

  @doc "Authorizes a sandbox capability against its current persisted session and resource ownership. Requires database access."
  def authorize(scope, capability, resource \\ nil) do
    if demo_scope?(scope, resource) do
      authorize_demo(scope, capability, resource)
    else
      :ok
    end
  end

  @doc "Checks persisted ownership before an external side effect. Missing organizations fail closed. Requires database access."
  def allow_external_effect?(%{id: id}), do: allow_external_effect?(id)

  def allow_external_effect?(id) when is_binary(id) do
    case Repo.get(Organization, id) do
      %{demo_kind: nil, deleted_at: nil} -> true
      _ -> false
    end
  end

  def allow_external_effect?(_), do: false

  @doc "Returns an error before provider work for a demo or missing organization. Requires database access."
  def external_effect(org),
    do: if(allow_external_effect?(org), do: :ok, else: {:error, :demo_forbidden})

  @doc "Prevents synthetic users from entering normal authentication or mail flows. Requires database access."
  def normal_user?(%User{id: nil, demo_kind: nil}), do: true

  def normal_user?(%{id: id}) do
    case Repo.get(User, id) do
      %{demo_kind: nil} -> true
      _ -> false
    end
  end

  def normal_user?(_), do: false

  @doc "Checks the persisted resource's tenant before provider work, including supplied tenant consistency. Requires database access."
  def external_resource(schema, id, expected_org \\ nil) do
    case Repo.get(schema, id) do
      %{organization_id: org_id} when is_nil(expected_org) or expected_org == org_id ->
        external_effect(org_id)

      _ ->
        {:error, :demo_forbidden}
    end
  end

  @doc """
  Converts a provider authorization result into an Oban cancellation.

      iex> Marquee.AdminDemo.worker_permission(:ok)
      :ok
      iex> Marquee.AdminDemo.worker_permission({:error, :demo_forbidden})
      {:cancel, :demo_forbidden}
  """
  def worker_permission(:ok), do: :ok
  def worker_permission(_), do: {:cancel, :demo_forbidden}

  @doc "Validates editable attributes without accepting provider identity changes. Requires database access."
  def authorize_attributes(scope, capability, resource, attrs) do
    with :ok <- authorize(scope, capability, resource) do
      forbidden = ~w(mux_asset_id mux_playback_id mux_upload_id organization_id)

      if demo_scope?(scope, resource) and
           Enum.any?(Map.keys(attrs), &(to_string(&1) in forbidden)),
         do: {:error, :demo_forbidden},
         else: :ok
    end
  end

  @doc "Adds one approved local-template clip to the private sandbox, idempotently. Requires database and local template access."
  def add_sample_clip(scope, slug) when is_binary(slug) do
    with :ok <- authorize(scope, :content_edit),
         {:ok, manifest} <- Catalog.load(),
         clip when not is_nil(clip) <- Enum.find(manifest.clips, &(&1["slug"] == slug)) do
      Repo.transaction(fn ->
        Repo.one!(
          from o in Organization, where: o.id == ^scope.organization.id, lock: "FOR UPDATE"
        )

        register_assets(manifest)

        Repo.get_by(Marquee.Content.Video, organization_id: scope.organization.id, slug: slug) ||
          Catalog.insert_video(scope.organization, clip)
      end)
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :demo_forbidden}
    end
  end

  def add_sample_clip(_, _), do: {:error, :demo_forbidden}

  @doc "Resolves a persisted sample identity within an active private demo. Requires database access."
  def sample_viewer(scope, id) when is_binary(id) do
    with :ok <- authorize(scope, :members_read),
         %{admin_demo_session_id: session_id, organization: org} when is_binary(session_id) <-
           scope,
         {:ok, viewer} <- Marquee.Viewers.get_viewer(org, id),
         true <- viewer.metadata["admin_demo_sample"] == true do
      {:ok, %{viewer | __impersonating__: true}}
    else
      _ -> {:error, :demo_forbidden}
    end
  end

  def sample_viewer(_, _), do: {:error, :demo_forbidden}

  defp demo_scope?(scope, resource) do
    demo_identity?(scope) or demo_resource?(resource)
  end

  defp demo_resource?(%{__struct__: schema, id: id}) when is_binary(id) do
    case Repo.get(schema, id) do
      %{organization_id: org_id} -> demo_id?(org_id)
      %Organization{} = org -> not is_nil(org.demo_kind)
      _ -> false
    end
  end

  defp demo_resource?(resource), do: demo_id?(resource && Map.get(resource, :organization_id))

  defp demo_identity?(%{admin_demo_session_id: id}) when not is_nil(id), do: true

  defp demo_identity?(%{organization: org, user: user}) do
    demo_id?(org && org.id) or (not is_nil(user) and not normal_user?(user))
  end

  defp demo_identity?(_), do: false

  defp demo_id?(id) when is_binary(id) do
    case Repo.get(Organization, id) do
      %{demo_kind: kind} when not is_nil(kind) -> true
      _ -> false
    end
  end

  defp demo_id?(_), do: false

  defp authorize_demo(
         %Scope{admin_demo_session_id: id, user: user, organization: org},
         capability,
         resource
       )
       when is_binary(id) and not is_nil(user) and not is_nil(org) do
    with true <- enabled?(),
         %Session{} = session <- Repo.get(Session, id),
         :ok <- valid_session(session),
         true <- session.organization_id == org.id and session.user_id == user.id,
         %Membership{role: :admin} <- Accounts.get_membership(org, user),
         %User{demo_kind: :admin_demo_visitor, demo_revoked_at: nil} <- Repo.get(User, user.id),
         true <-
           capability in [
             :content_edit,
             :catalog_edit,
             :branding_edit,
             :analytics_read,
             :members_read,
             :members_edit,
             :podcast_edit,
             :viewer_preview,
             :tour
           ],
         true <- resource_owned?(resource, org.id) do
      :ok
    else
      {:error, :expired} -> {:error, :demo_expired}
      _ -> {:error, :demo_forbidden}
    end
  end

  defp authorize_demo(_, _, _), do: {:error, :demo_forbidden}

  defp resource_owned?(nil, _org_id), do: true
  defp resource_owned?(%Organization{id: id}, org_id), do: id == org_id

  defp resource_owned?(%{__struct__: schema, id: id}, org_id) do
    case Repo.get(schema, id) do
      %{organization_id: ^org_id} -> true
      _ -> false
    end
  end

  defp resource_owned?(%{organization_id: id}, org_id), do: id == org_id
  defp resource_owned?(_, _), do: false

  @doc "Checks all resources participating in a tenant-scoped mutation. Requires database access."
  def authorize_resources(scope, capability, resources) do
    Enum.reduce_while(resources, :ok, fn resource, :ok ->
      case authorize(scope, capability, resource) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  @doc "Checks creation attributes against the authorized tenant. Requires database access."
  def authorize_creation(scope, capability, attrs) do
    org_id =
      Map.get(attrs, :organization_id) || Map.get(attrs, "organization_id") ||
        (scope && scope.organization && scope.organization.id)

    authorize(scope, capability, %{organization_id: org_id})
  end

  @doc "Configures the exact dedicated service host without enabling visitor access. Requires database and local template access."
  def configure_host(host) do
    with true <- is_binary(host) and host == config()[:host] and valid_host?(host),
         {:ok, manifest} <- Catalog.load() do
      Repo.transaction(fn ->
        org = configure_host_locked(host)

        register_assets(manifest)
        Events.broadcast_platform(nil, {:admin_demo_host_configured, org})
        org
      end)
    else
      _ -> {:error, :demo_unavailable}
    end
  end

  @doc "Registers approved shared media independently of sandbox lifetime. Requires database and local template access."
  def register_catalog_assets do
    with {:ok, manifest} <- Catalog.load(),
         do: Repo.transaction(fn -> register_assets(manifest) end)
  end

  @doc "Checks permanent protection for a provider asset ID. Requires database access."
  def protected_asset?(asset_id) when is_binary(asset_id),
    do: Repo.exists?(from a in ProtectedAsset, where: a.mux_asset_id == ^asset_id)

  def protected_asset?(_), do: false

  @doc "Starts or retries an entry allocation under a serialized capacity limit. Requires database and local template access."
  def start_session(opts \\ []) do
    entry_key = Keyword.get_lazy(opts, :entry_key, fn -> :crypto.strong_rand_bytes(32) end)

    if enabled?() and is_binary(entry_key) and byte_size(entry_key) == 32 do
      token = capability("start-v1", entry_key)
      allocation_transaction(fn -> start_locked(token, hash(entry_key)) end)
    else
      {:error, :disabled}
    end
  end

  @doc "Resolves an enabled, unexpired, host-bound demo capability to a private admin scope. Requires database access."
  def get_session(token) when is_binary(token) do
    with true <- enabled?(),
         %Session{} = session <- Repo.get_by(Session, token_hash: hash(token)),
         :ok <- valid_session(session),
         %User{demo_kind: :admin_demo_visitor, demo_revoked_at: nil} = user <-
           Repo.get(User, session.user_id),
         %Organization{demo_kind: :admin_sandbox, demo_purged_at: nil} = org <-
           Repo.get(Organization, session.organization_id),
         %Membership{role: :admin} = membership <- Accounts.get_membership(org, user) do
      {:ok,
       %{
         session: session,
         scope: %Scope{
           user: user,
           organization: org,
           membership: membership,
           admin_demo_session_id: session.id
         }
       }}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :not_found}
    end
  end

  def get_session(_), do: {:error, :not_found}

  @doc "Atomically replaces a sandbox; retries return the same still-active replacement. Requires database access."
  def reset_session(token) when is_binary(token) do
    if enabled?() do
      allocation_transaction(fn -> reset_token_locked(token) end)
    else
      {:error, :disabled}
    end
  end

  def reset_session(_), do: {:error, :not_found}

  @doc "Revokes one demo capability and its synthetic user, leaving ordinary login untouched. Requires database access."
  def revoke_session(token) when is_binary(token) do
    Repo.transaction(fn ->
      case Repo.one(from s in Session, where: s.token_hash == ^hash(token), lock: "FOR UPDATE") do
        nil -> :ok
        session -> revoke_locked(session, DateTime.utc_now())
      end
    end)

    :ok
  end

  @doc "Revokes expired demos, purges disposable data after 24 hours and sessions after 30 days. Bounded database work only."
  def cleanup_expired(opts \\ []) do
    now = Keyword.get(opts, :now, DateTime.utc_now())
    limit = opts |> Keyword.get(:per_page, 100) |> min(100) |> max(1)
    sessions = Admin.expired_admin_demo_sessions(now, limit)

    Repo.transaction(fn ->
      Enum.reduce(sessions, %{revoked: 0, purged: 0}, fn session, counts ->
        cleanup_one(session, now, counts)
      end)
    end)
  end

  defp allocation_transaction(fun) do
    Marquee.Otel.with_span "marquee.admin_demo.allocate" do
      Repo.transaction(fn ->
        case Admin.admin_demo_host(config()[:host], true) do
          %{demo_kind: :admin_demo_host, deleted_at: nil} -> fun.()
          _ -> Repo.rollback(:demo_unavailable)
        end
      end)
    end
  end

  defp configure_host_locked(host) do
    case Admin.admin_demo_host(host, true) do
      nil ->
        Repo.insert!(%Organization{
          name: "Wanderlust demo service",
          slug: "admin-demo-host-" <> short_hash(host),
          custom_domain: host,
          demo_kind: :admin_demo_host
        })

      %{demo_kind: :admin_demo_host} = org ->
        org

      _ ->
        Repo.rollback(:host_conflict)
    end
  end

  defp reset_token_locked(token) do
    case Repo.one(from s in Session, where: s.token_hash == ^hash(token), lock: "FOR UPDATE") do
      nil ->
        Repo.rollback(:not_found)

      %{replacement_session_id: id} when not is_nil(id) ->
        result_for_token(capability("reset-v1", token))

      old ->
        reset_locked(old, token)
    end
  end

  defp start_locked(token, key_hash) do
    case Repo.get_by(Session, token_hash: hash(token)) do
      %Session{} ->
        result_for_token(token)

      nil ->
        if Admin.admin_demo_entry_consumed?(key_hash), do: Repo.rollback(:revoked)

        if Admin.active_admin_demo_count(DateTime.utc_now()) >=
             (config()[:max_active_sessions] || 100),
           do: Repo.rollback(:capacity_reached)

        allocate(token, key_hash, load_catalog!())
    end
  end

  defp reset_locked(old, token) do
    case valid_session(old) do
      :ok -> :ok
      {:error, reason} -> Repo.rollback(reason)
    end

    manifest = load_catalog!()
    new_token = capability("reset-v1", token)
    fresh = allocate(new_token, hash(new_token), manifest)
    revoke_locked(old, DateTime.utc_now())
    Repo.update!(Ecto.Changeset.change(old, replacement_session_id: fresh.session.id))
    fresh
  end

  defp allocate(token, key_hash, manifest) do
    now = DateTime.utc_now()
    expires = DateTime.add(now, 7200)
    id = Ecto.UUID.generate()

    org =
      Repo.insert!(%Organization{
        name: "Wanderlust",
        slug: "wanderlust-demo-" <> id,
        demo_kind: :admin_sandbox,
        demo_entry_key_hash: key_hash,
        demo_expires_at: expires,
        onboarding_completed_at: DateTime.truncate(now, :second),
        preset_name: "catalog_cinema",
        accent_color_base: "#dba958"
      })

    owner = synthetic_user(:admin_demo_owner, id, now)
    user = synthetic_user(:admin_demo_visitor, id, nil)
    Repo.insert!(%Membership{organization_id: org.id, user_id: owner.id, role: :owner})
    Repo.insert!(%Membership{organization_id: org.id, user_id: user.id, role: :admin})
    register_assets(manifest)
    Catalog.seed(org, manifest)

    session =
      Repo.insert!(%Session{
        organization_id: org.id,
        user_id: user.id,
        owner_user_id: owner.id,
        token_hash: hash(token),
        entry_key_hash: key_hash,
        hostname: config()[:host],
        generation: Ecto.UUID.generate(),
        template_version: manifest.version,
        expires_at: expires
      })

    Events.broadcast(%Scope{user: user, organization: org}, {:admin_demo_started, session})
    %{session: session, token: token, organization: org, user: user}
  end

  defp synthetic_user(kind, id, revoked) do
    Repo.insert!(%User{
      email: "#{kind}-#{id}@demo.invalid",
      demo_kind: kind,
      demo_revoked_at: revoked,
      confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
  end

  defp result_for_token(token) do
    case get_session(token) do
      {:ok, %{session: session, scope: scope}} ->
        %{session: session, token: token, organization: scope.organization, user: scope.user}

      {:error, reason} ->
        Repo.rollback(reason)
    end
  end

  defp valid_session(session) do
    cond do
      session.hostname != config()[:host] -> {:error, :not_found}
      not is_nil(session.revoked_at) or not is_nil(session.purged_at) -> {:error, :revoked}
      DateTime.compare(session.expires_at, DateTime.utc_now()) != :gt -> {:error, :expired}
      true -> :ok
    end
  end

  defp revoke_locked(%{revoked_at: nil} = session, now) do
    session = Repo.update!(Ecto.Changeset.change(session, revoked_at: now))

    Repo.update_all(
      from(u in User, where: u.id == ^session.user_id and u.demo_kind == :admin_demo_visitor),
      set: [demo_revoked_at: now]
    )

    org = Repo.get!(Organization, session.organization_id)
    Events.broadcast(%Scope{organization: org}, {:admin_demo_revoked, session})
    MarqueeWeb.Endpoint.broadcast("admin_demo:#{session.id}", "disconnect", %{})
    :ok
  end

  defp revoke_locked(_, _), do: :ok

  defp register_assets(manifest) do
    Enum.each(manifest.clips, fn clip ->
      Repo.insert!(
        %ProtectedAsset{
          mux_asset_id: clip["mux_asset_id"],
          mux_playback_id: clip["mux_playback_id"],
          template_version: manifest.version
        },
        on_conflict: :nothing,
        conflict_target: :mux_asset_id
      )
    end)

    length(manifest.clips)
  end

  defp load_catalog! do
    case Catalog.load() do
      {:ok, manifest} -> manifest
      _ -> Repo.rollback(:demo_unavailable)
    end
  end

  defp cleanup_one(session, now, counts) do
    revoked = if is_nil(session.revoked_at), do: 1, else: 0
    revoke_locked(session, now)

    ended_at =
      if session.revoked_at && DateTime.before?(session.revoked_at, session.expires_at),
        do: session.revoked_at,
        else: session.expires_at

    purge? = is_nil(session.purged_at) and DateTime.diff(now, ended_at) >= 86_400
    if purge?, do: purge_sandbox(session, now)

    if DateTime.diff(now, session.expires_at) >= 30 * 86_400 do
      Repo.update_all(from(s in Session, where: s.replacement_session_id == ^session.id),
        set: [replacement_session_id: nil]
      )

      Repo.delete_all(
        from log in Marquee.Audit.Log, where: log.organization_id == ^session.organization_id
      )

      Repo.delete_all(from s in Session, where: s.id == ^session.id)

      Repo.delete_all(
        from u in User,
          where: u.id in ^[session.user_id, session.owner_user_id] and not is_nil(u.demo_kind)
      )
    end

    %{revoked: counts.revoked + revoked, purged: counts.purged + if(purge?, do: 1, else: 0)}
  end

  defp purge_sandbox(session, now) do
    org = Repo.get!(Organization, session.organization_id)

    viewer_ids =
      from v in Marquee.Viewers.Viewer, where: v.organization_id == ^org.id, select: v.id

    Repo.delete_all(
      from t in Marquee.Viewers.ViewerToken, where: t.viewer_id in subquery(viewer_ids)
    )

    for schema <- [
          Marquee.Podcasts.AudioRequest,
          Marquee.Podcasts.FeedToken,
          Marquee.Podcasts.Episode,
          Marquee.Podcasts.ShowTier,
          Marquee.Podcasts.Show,
          Marquee.Engagement.ContinueWatchingDismissal,
          Marquee.Engagement.PlaybackDropOff,
          Marquee.Engagement.QueueItem,
          Marquee.Engagement.Favorite,
          Marquee.Engagement.WatchHistory,
          Marquee.Engagement.Progress,
          Marquee.Engagement.WatchlistItem,
          Marquee.Catalog.HeroSlide,
          Marquee.Catalog.RowItem,
          Marquee.Content.CollectionItem,
          Marquee.Content.VideoTag,
          Marquee.Content.Tag,
          Marquee.Content.Episode,
          Marquee.Content.Season,
          Marquee.Content.Series,
          Marquee.Content.Collection,
          Marquee.Catalog.Row,
          Marquee.Catalog.Layout,
          Marquee.Accounts.AdminNudgeDismissal,
          Marquee.Content.Video,
          Marquee.Analytics.Snapshot,
          Marquee.Branding.Theme,
          Marquee.Viewers.Viewer,
          Membership
        ] do
      Repo.delete_all(from row in schema, where: row.organization_id == ^org.id)
    end

    Repo.update!(
      Ecto.Changeset.change(org,
        demo_purged_at: now,
        name: "Expired admin demo",
        features: %{},
        accent_color_base: nil,
        accent_color_hover: nil,
        accent_color_active: nil,
        accent_color_subtle: nil,
        display_font: nil,
        preset_name: nil,
        admin_accent_color: nil
      )
    )

    Repo.update!(Ecto.Changeset.change(session, purged_at: now))
    Events.broadcast(%Scope{organization: org}, {:admin_demo_purged, session})
  end

  defp capability(purpose, value),
    do:
      :crypto.mac(
        :hmac,
        :sha256,
        MarqueeWeb.Endpoint.config(:secret_key_base),
        purpose <> <<0>> <> value
      )

  defp hash(value), do: :crypto.hash(:sha256, value)
  defp short_hash(value), do: value |> hash() |> Base.encode16(case: :lower) |> binary_part(0, 16)
  defp config, do: Application.get_env(:marquee, :admin_demo, [])

  defp valid_host?(host),
    do: byte_size(host) <= 253 and Regex.match?(~r/^[a-z0-9]+(?:[.-][a-z0-9]+)*$/, host)
end
