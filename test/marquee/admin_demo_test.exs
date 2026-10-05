defmodule Marquee.AdminDemoTest do
  use Marquee.DataCase, async: false

  import Swoosh.TestAssertions

  alias Marquee.{AdminDemo, Repo}

  alias Marquee.Accounts.{Membership, Organization, User, UserToken}
  alias Marquee.Catalog.Layout
  alias Marquee.Content.{Collection, Series, Tag, Video}

  @moduletag :tmp_dir
  @host "demo-marquee.example.test"

  setup %{tmp_dir: dir} do
    path = Path.join(dir, "travel-fixture.json")
    manifest = Marquee.AdminDemoFixtures.catalog_manifest()
    File.write!(path, Jason.encode!(manifest))
    original = Application.fetch_env(:marquee, :admin_demo)
    Application.put_env(:marquee, :admin_demo, enabled: true, host: @host, catalog_path: path)

    on_exit(fn ->
      case original do
        {:ok, value} -> Application.put_env(:marquee, :admin_demo, value)
        :error -> Application.delete_env(:marquee, :admin_demo)
      end
    end)

    %{catalog_path: path, manifest: manifest}
  end

  test "disabled or unconfigured demo fails without allocating users or tenants" do
    assert {:error, :demo_unavailable} = AdminDemo.start_session()
    assert Repo.aggregate(Organization, :count) == 0
    assert Repo.aggregate(User, :count) == 0
    config = Application.fetch_env!(:marquee, :admin_demo)
    Application.put_env(:marquee, :admin_demo, Keyword.put(config, :enabled, false))
    assert {:error, :disabled} = AdminDemo.start_session()
    assert Repo.aggregate(Organization, :count) == 0
    assert {:ok, host} = AdminDemo.configure_host(@host)
    assert host.demo_kind == :admin_demo_host
    assert {:error, :disabled} = AdminDemo.start_session()
  end

  test "release host configuration is exact and idempotent without a disposable visitor" do
    assert {:error, _} = AdminDemo.configure_host("foreign.example.test")
    assert {:ok, org} = AdminDemo.configure_host(@host)
    assert org.demo_kind == :admin_demo_host
    assert {:ok, repeated} = AdminDemo.configure_host(@host)
    assert repeated.id == org.id
    assert Repo.aggregate(Organization, :count) == 1
    assert Repo.aggregate(UserToken, :count) == 0
  end

  test "entry creates a two-hour private admin with separate disabled synthetic owner and hashed capability" do
    configure_host()
    now = DateTime.utc_now()
    assert {:ok, demo} = start_session()
    assert demo.organization.demo_kind == :admin_sandbox
    assert demo.organization.onboarding_completed_at != nil
    assert demo.user.demo_kind == :admin_demo_visitor
    assert demo.user.demo_revoked_at == nil
    assert demo.user.hashed_password == nil
    refute demo.user.is_super_admin
    assert is_binary(demo.token) and byte_size(demo.token) >= 32
    assert demo.session.token_hash != demo.token
    assert demo.session.organization_id == demo.organization.id
    assert demo.session.user_id == demo.user.id
    assert DateTime.diff(demo.session.expires_at, now) in 7_195..7_205
    assert demo.organization.demo_expires_at == demo.session.expires_at
    assert demo.session.template_version != nil
    assert demo.session.generation != nil

    memberships =
      Repo.all(from(m in Membership, where: m.organization_id == ^demo.organization.id))

    assert Enum.count(memberships, &(&1.role == :owner)) == 1
    visitor = Enum.find(memberships, &(&1.user_id == demo.user.id))
    assert visitor.role == :admin
    owner = Repo.get!(User, demo.session.owner_user_id)
    assert owner.id != demo.user.id
    assert owner.demo_kind == :admin_demo_owner
    assert owner.demo_revoked_at != nil
    assert owner.hashed_password == nil
    assert Repo.aggregate(UserToken, :count) == 0
    refute_email_sent()
  end

  test "template seeds only approved initial clips plus editable catalog branding and sample analytics",
       %{manifest: manifest} do
    configure_host()
    {:ok, demo} = start_session()
    org_id = demo.organization.id
    videos = Repo.all(from(v in Video, where: v.organization_id == ^org_id))
    initial = Enum.filter(manifest.clips, & &1.initial)

    assert Enum.sort(Enum.map(videos, & &1.mux_playback_id)) ==
             Enum.sort(Enum.map(initial, & &1.mux_playback_id))

    assert Enum.all?(videos, &is_nil(&1.mux_asset_id))
    assert Enum.all?(videos, &(&1.mux_status == "ready"))
    assert Repo.exists?(from(c in Collection, where: c.organization_id == ^org_id))
    assert Repo.exists?(from(s in Series, where: s.organization_id == ^org_id))
    assert Repo.exists?(from(r in Marquee.Catalog.Row, where: r.organization_id == ^org_id))
    assert Repo.exists?(from(t in Marquee.Branding.Theme, where: t.organization_id == ^org_id))

    assert Repo.exists?(
             from(a in Marquee.Analytics.Snapshot, where: a.organization_id == ^org_id)
           )
  end

  test "two entries have distinct tenants users and capabilities; repeated lookup reuses only its own scope" do
    configure_host()
    {:ok, first} = start_session()
    {:ok, second} = start_session()
    assert first.organization.id != second.organization.id
    assert first.user.id != second.user.id
    assert first.token != second.token

    for demo <- [first, second] do
      assert {:ok, %{session: session, scope: scope}} = AdminDemo.get_session(demo.token)
      assert session.id == demo.session.id
      assert scope.user.id == demo.user.id
      assert scope.organization.id == demo.organization.id
      assert scope.membership.role == :admin
      assert scope.admin_demo_session_id == demo.session.id
    end

    assert Repo.aggregate(Organization, :count) == 3
    assert Repo.aggregate(UserToken, :count) == 0
  end

  test "tampered tokens and expired sessions cannot resolve an authenticated demo scope" do
    configure_host()
    {:ok, demo} = start_session()
    assert {:error, :not_found} = AdminDemo.get_session(demo.token <> "tampered")

    Repo.update!(
      Ecto.Changeset.change(demo.session, expires_at: DateTime.add(DateTime.utc_now(), -60))
    )

    assert {:error, :expired} = AdminDemo.get_session(demo.token)
  end

  test "entry keys are idempotent and active capacity rejects only new allocations" do
    configure_host()
    config = Application.fetch_env!(:marquee, :admin_demo)
    Application.put_env(:marquee, :admin_demo, Keyword.put(config, :max_active_sessions, 1))
    key = :crypto.strong_rand_bytes(32)
    assert {:ok, first} = start_session(entry_key: key)
    assert {:ok, repeated} = start_session(entry_key: key)
    assert repeated.token == first.token
    assert repeated.session.id == first.session.id
    assert repeated.organization.id == first.organization.id
    assert {:error, :capacity_reached} = start_session(entry_key: :crypto.strong_rand_bytes(32))
    assert Repo.aggregate(Organization, :count) == 2
    assert :ok = AdminDemo.revoke_session(first.token)
    assert {:error, :revoked} = start_session(entry_key: key)
    assert {:ok, _} = start_session(entry_key: :crypto.strong_rand_bytes(32))
  end

  test "reset retries return one active replacement even at capacity and never resurrect it after exit" do
    configure_host()
    config = Application.fetch_env!(:marquee, :admin_demo)
    Application.put_env(:marquee, :admin_demo, Keyword.put(config, :max_active_sessions, 1))
    {:ok, old} = start_session()

    assert {:ok, fresh} =
             Oban.Testing.with_testing_mode(:manual, fn -> AdminDemo.reset_session(old.token) end)

    assert {:ok, repeated} = AdminDemo.reset_session(old.token)
    assert repeated.token == fresh.token
    assert repeated.organization.id == fresh.organization.id
    assert repeated.session.id == fresh.session.id
    assert Repo.aggregate(Organization, :count) == 3
    assert :ok = AdminDemo.revoke_session(fresh.token)
    assert {:error, :revoked} = AdminDemo.reset_session(old.token)
    assert Repo.aggregate(Organization, :count) == 3
  end

  test "exit revokes immediately and idempotently without touching another visitor" do
    configure_host()
    {:ok, first} = start_session()
    {:ok, second} = start_session()
    assert :ok = AdminDemo.revoke_session(first.token)
    assert :ok = AdminDemo.revoke_session(first.token)
    assert {:error, :revoked} = AdminDemo.get_session(first.token)
    assert Repo.get!(User, first.user.id).demo_revoked_at != nil
    assert {:ok, %{scope: scope}} = AdminDemo.get_session(second.token)
    assert scope.organization.id == second.organization.id
  end

  test "reset creates a clean new sandbox and revokes old authority while preserving other visitors" do
    configure_host()
    {:ok, old} = start_session()
    {:ok, other} = start_session()

    Repo.update_all(from(v in Video, where: v.organization_id == ^old.organization.id),
      set: [title: "Visitor edits"]
    )

    assert {:ok, fresh} =
             Oban.Testing.with_testing_mode(:manual, fn -> AdminDemo.reset_session(old.token) end)

    assert fresh.organization.id != old.organization.id
    assert fresh.user.id != old.user.id
    assert fresh.session.generation != old.session.generation
    assert {:error, :revoked} = AdminDemo.get_session(old.token)
    assert {:ok, _} = AdminDemo.get_session(fresh.token)
    assert {:ok, _} = AdminDemo.get_session(other.token)

    refute Repo.exists?(
             from(v in Video,
               where: v.organization_id == ^fresh.organization.id and v.title == "Visitor edits"
             )
           )

    assert Repo.aggregate(UserToken, :count) == 0
  end

  test "invalid catalog cannot partially reset or revoke the still-valid sandbox", %{
    catalog_path: path
  } do
    configure_host()
    {:ok, demo} = start_session()
    before = Repo.aggregate(Organization, :count)
    File.write!(path, Jason.encode!(%{version: 1, clips: []}))
    assert {:error, :demo_unavailable} = AdminDemo.reset_session(demo.token)
    assert {:ok, _} = AdminDemo.get_session(demo.token)
    assert Repo.aggregate(Organization, :count) == before
    assert Repo.aggregate(UserToken, :count) == 0
  end

  test "ordinary organization and user changesets cannot grant or clear internal demo markers" do
    attrs = %{
      demo_kind: :admin_sandbox,
      demo_expires_at: DateTime.utc_now(),
      demo_purged_at: DateTime.utc_now()
    }

    changeset =
      Organization.changeset(
        %Organization{},
        Map.merge(attrs, %{name: "Ordinary", slug: "ordinary"})
      )

    refute Map.has_key?(changeset.changes, :demo_kind)
    refute Map.has_key?(changeset.changes, :demo_expires_at)
    refute Map.has_key?(changeset.changes, :demo_purged_at)

    changeset =
      User.admin_changeset(%User{}, %{
        email: "ordinary@example.test",
        demo_kind: :admin_demo_visitor,
        demo_revoked_at: DateTime.utc_now()
      })

    refute Map.has_key?(changeset.changes, :demo_kind)
    refute Map.has_key?(changeset.changes, :demo_revoked_at)
  end

  test "cleanup is bounded and idempotent, purges expired content but keeps tenant tombstones and unrelated data" do
    configure_host()
    {:ok, active} = start_session()
    {:ok, recent} = start_session()
    recent_expiry = DateTime.add(DateTime.utc_now(), -300)
    Repo.update!(Ecto.Changeset.change(recent.session, expires_at: recent_expiry))
    Repo.update!(Ecto.Changeset.change(recent.organization, demo_expires_at: recent_expiry))
    ordinary = insert(:organization)
    real_video = insert(:video, organization: ordinary)
    real_tag = insert(:tag, organization: ordinary)
    real_layout = insert(:layout, organization: ordinary)

    stale =
      for _ <- 1..3 do
        {:ok, demo} = start_session()
        insert(:tag, organization: demo.organization)
        insert(:layout, organization: demo.organization)
        old = DateTime.add(DateTime.utc_now(), -48 * 3_600)
        Repo.update!(Ecto.Changeset.change(demo.session, expires_at: old))
        Repo.update!(Ecto.Changeset.change(demo.organization, demo_expires_at: old))
        demo
      end

    assert {:ok, %{revoked: revoked, purged: purged}} = AdminDemo.cleanup_expired(per_page: 2)
    assert revoked in 1..2
    assert purged in 0..2
    for _ <- 1..3, do: assert({:ok, _} = AdminDemo.cleanup_expired(per_page: 2))

    for demo <- stale do
      assert Repo.get!(Organization, demo.organization.id).demo_purged_at != nil
      refute Repo.exists?(from(v in Video, where: v.organization_id == ^demo.organization.id))
      refute Repo.exists?(from(t in Tag, where: t.organization_id == ^demo.organization.id))
      refute Repo.exists?(from(l in Layout, where: l.organization_id == ^demo.organization.id))
      assert {:error, _} = AdminDemo.get_session(demo.token)
    end

    assert {:ok, _} = AdminDemo.get_session(active.token)
    assert {:error, _} = AdminDemo.get_session(recent.token)
    assert Repo.get!(Organization, recent.organization.id).demo_purged_at == nil
    assert Repo.exists?(from(v in Video, where: v.organization_id == ^recent.organization.id))
    assert Repo.get!(Video, real_video.id).organization_id == ordinary.id
    assert Repo.get!(Tag, real_tag.id).organization_id == ordinary.id
    assert Repo.get!(Layout, real_layout.id).organization_id == ordinary.id
    assert {:ok, %{revoked: 0, purged: 0}} = AdminDemo.cleanup_expired(per_page: 2)
  end

  test "registered shared assets remain protected after expired sandbox and retained session cleanup",
       %{manifest: manifest} do
    configure_host()
    assert {:ok, _} = AdminDemo.register_catalog_assets()
    assert {:ok, _} = AdminDemo.register_catalog_assets()
    key = :crypto.strong_rand_bytes(32)
    {:ok, demo} = start_session(entry_key: key)
    old = DateTime.add(DateTime.utc_now(), -40 * 86_400)
    Repo.update!(Ecto.Changeset.change(demo.session, expires_at: old, revoked_at: old))
    Repo.update!(Ecto.Changeset.change(demo.organization, demo_expires_at: old))
    assert {:ok, _} = AdminDemo.cleanup_expired(per_page: 100)
    assert Repo.get(demo.session.__struct__, demo.session.id) == nil
    assert Repo.get!(Organization, demo.organization.id).demo_kind == :admin_sandbox
    assert {:error, reason} = start_session(entry_key: key)
    assert reason in [:expired, :revoked]
    for clip <- manifest.clips, do: assert(AdminDemo.protected_asset?(clip.mux_asset_id))
    refute AdminDemo.protected_asset?("ordinary-customer-asset")
  end

  defp configure_host do
    assert {:ok, _} = AdminDemo.configure_host(@host)
  end

  defp start_session(opts \\ []),
    do: Oban.Testing.with_testing_mode(:manual, fn -> AdminDemo.start_session(opts) end)
end
