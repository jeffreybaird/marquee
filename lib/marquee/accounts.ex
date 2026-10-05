defmodule Marquee.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  alias Marquee.Branding
  alias Marquee.Branding.Theme
  alias Marquee.PlatformBilling
  alias Marquee.Repo
  alias Marquee.Workers.SeedStarterContentWorker

  alias Marquee.Accounts.{
    AdminNudgeDismissal,
    Membership,
    Organization,
    PageTourCompletion,
    User,
    UserNotifier,
    UserToken
  }

  ## Organization getters

  @doc """
  Gets an organization by its custom domain.

  Returns `{:ok, organization}` if found, `{:error, :not_found}` otherwise.
  Returns `{:error, :not_found}` when `domain` is nil.

  Exempt from doctest — hits the database.
  """
  def get_organization_by_custom_domain(nil), do: {:error, :not_found}

  def get_organization_by_custom_domain(domain) when is_binary(domain) do
    case Repo.get_by(Organization, custom_domain: domain) do
      nil -> {:error, :not_found}
      org -> {:ok, org}
    end
  end

  @doc """
  Gets an organization by its slug.

  Returns `{:ok, organization}` if found, `{:error, :not_found}` otherwise.

  Exempt from doctest — hits the database.
  """
  def get_organization_by_slug(slug) when is_binary(slug) do
    case Repo.get_by(Organization, slug: slug) do
      nil -> {:error, :not_found}
      org -> {:ok, org}
    end
  end

  @doc """
  Gets an organization by its primary key.

  Returns `{:ok, organization}` if found, `{:error, :not_found}` otherwise.
  Returns `{:error, :not_found}` for any non-binary id.

  Exempt from doctest — hits the database.
  """
  def get_organization(id) when is_binary(id) do
    case Repo.get(Organization, id) do
      nil -> {:error, :not_found}
      org -> {:ok, org}
    end
  end

  def get_organization(_), do: {:error, :not_found}

  @doc """
  Returns true once an organization has finished (or skipped) the new-admin
  setup wizard.

  ## Examples

      iex> Marquee.Accounts.onboarding_complete?(%Marquee.Accounts.Organization{onboarding_completed_at: nil})
      false

      iex> Marquee.Accounts.onboarding_complete?(%Marquee.Accounts.Organization{onboarding_completed_at: ~U[2026-09-01 00:00:00Z]})
      true

  """
  def onboarding_complete?(%Organization{onboarding_completed_at: nil}), do: false
  def onboarding_complete?(%Organization{onboarding_completed_at: %DateTime{}}), do: true

  @doc """
  Marks an organization's new-admin onboarding as complete, stamping the
  current time. Idempotent — re-completing simply refreshes the timestamp.

  Exempt from doctest — hits the database.
  """
  def complete_onboarding(%Organization{} = org) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    org
    |> Ecto.Changeset.change(onboarding_completed_at: now)
    |> Repo.update()
    |> case do
      {:ok, org} -> {:ok, org}
      {:error, changeset} -> {:error, :validation, changeset}
    end
  end

  @doc """
  Returns the first organization in the system.

  Intended only for dev-mode fallbacks where the request carries no
  tenant signal. Callers MUST gate this to `Mix.env() == :dev` — the
  production plug pipeline never invokes it.

  Exempt from doctest — hits the database.
  """
  def fetch_any_organization do
    case Organization |> order_by(asc: :inserted_at) |> limit(1) |> Repo.one() do
      nil -> {:error, :not_found}
      org -> {:ok, org}
    end
  end

  @doc """
  Tuple-returning variant of `get_user_primary_organization/1`.

  Returns `{:ok, org}` or `{:error, :not_found}`.

  Exempt from doctest — hits the database.
  """
  def fetch_user_primary_organization(user) do
    case get_user_primary_organization(user) do
      nil -> {:error, :not_found}
      org -> {:ok, org}
    end
  end

  @doc """
  Gets an organization by its Stripe Connect account ID.

  Returns `{:ok, organization}` if found, `{:error, :not_found}` otherwise.

  Exempt from doctest — hits the database.
  """
  def get_organization_by_stripe_connect_id(stripe_account_id)
      when is_binary(stripe_account_id) do
    case Repo.get_by(Organization, stripe_connect_account_id: stripe_account_id) do
      nil -> {:error, :not_found}
      org -> {:ok, org}
    end
  end

  @doc """
  Gets an organization by its Stripe Connect account ID. Raises on not found.

  Exempt from doctest — hits the database.
  """
  def get_organization_by_stripe_connect_id!(stripe_account_id)
      when is_binary(stripe_account_id) do
    Repo.get_by!(Organization, stripe_connect_account_id: stripe_account_id)
  end

  @doc """
  Returns the `organization_id` for the given Stripe Connect account id,
  or `nil` when no organization matches.

  Intended for webhook routing before the tenant context is established.

  Exempt from doctest — hits the database.
  """
  def get_organization_id_by_stripe_connect_account_id(stripe_account_id)
      when is_binary(stripe_account_id) do
    Organization
    |> where([o], o.stripe_connect_account_id == ^stripe_account_id)
    |> select([o], o.id)
    |> Repo.one()
  end

  def get_organization_id_by_stripe_connect_account_id(_), do: nil

  @doc """
  Gets the membership for a user in an organization.

  Returns `%Membership{}` if the user is a member, nil otherwise.

  Exempt from doctest — hits the database.
  """
  def get_membership(%Organization{id: org_id}, %User{id: user_id}) do
    Repo.get_by(Membership, organization_id: org_id, user_id: user_id)
  end

  @doc """
  Returns true if the user has a membership in any organization.

  Exempt from doctest — hits the database.
  """
  def has_any_membership?(%User{id: user_id}) do
    Repo.exists?(from m in Membership, where: m.user_id == ^user_id)
  end

  @doc """
  Returns the user's primary (first non-deleted) organization, or `nil` if
  the user has no memberships.

  Used by flows that need an org context for a user before any tenant has
  been resolved from the request — e.g. building a magic-link URL on the
  platform-level operator login page.

  Exempt from doctest — hits the database.
  """
  def get_user_primary_organization(%User{id: user_id}) do
    Repo.one(
      from m in Membership,
        where: m.user_id == ^user_id,
        join: o in assoc(m, :organization),
        where: is_nil(o.deleted_at),
        order_by: [asc: m.inserted_at],
        select: o,
        limit: 1
    )
  end

  ## Admin dashboard nudge dismissals

  @doc """
  Lists the nudge keys this operator has dismissed on the given org's
  dashboard.

  Exempt from doctest — hits the database.
  """
  def list_dismissed_nudge_keys(%User{id: user_id}, %Organization{id: org_id}) do
    AdminNudgeDismissal
    |> where(user_id: ^user_id, organization_id: ^org_id)
    |> select([d], d.nudge_key)
    |> Repo.all()
  end

  @doc """
  Records that this operator dismissed a dashboard nudge. Idempotent —
  re-dismissing the same key refreshes the timestamp.

  Returns `{:ok, dismissal}` or `{:error, :validation, changeset}`.

  Exempt from doctest — hits the database.
  """
  def dismiss_nudge(%User{id: user_id}, %Organization{id: org_id}, nudge_key)
      when is_binary(nudge_key) do
    attrs = %{
      user_id: user_id,
      organization_id: org_id,
      nudge_key: nudge_key,
      dismissed_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }

    %AdminNudgeDismissal{}
    |> AdminNudgeDismissal.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:dismissed_at, :updated_at]},
      conflict_target: [:user_id, :organization_id, :nudge_key]
    )
    |> case do
      {:ok, dismissal} -> {:ok, dismissal}
      {:error, changeset} -> {:error, :validation, changeset}
    end
  end

  ## Guided admin tour

  @doc """
  Returns true once this operator has finished (or dismissed) the guided
  admin tour for the organization the membership belongs to.

  A `nil` membership — e.g. a super admin impersonating an org without a
  seat — is treated as already done, so the tour never auto-starts for them.

      iex> Marquee.Accounts.admin_tour_completed?(
      ...>   %Marquee.Accounts.Membership{admin_tour_completed_at: ~U[2026-09-02 00:00:00Z]}
      ...> )
      true

      iex> Marquee.Accounts.admin_tour_completed?(
      ...>   %Marquee.Accounts.Membership{admin_tour_completed_at: nil}
      ...> )
      false

      iex> Marquee.Accounts.admin_tour_completed?(nil)
      true
  """
  def admin_tour_completed?(nil), do: true
  def admin_tour_completed?(%Membership{admin_tour_completed_at: nil}), do: false
  def admin_tour_completed?(%Membership{admin_tour_completed_at: %DateTime{}}), do: true

  @doc """
  Stamps the current time on the membership to record that the operator
  finished the guided admin tour. Idempotent — re-completing refreshes the
  timestamp. A `nil` membership is a no-op returning `{:ok, nil}`.

  Returns `{:ok, membership}` or `{:error, :validation, changeset}`.

  Exempt from doctest — hits the database.
  """
  def complete_admin_tour(nil), do: {:ok, nil}

  def complete_admin_tour(%Membership{} = membership) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    membership
    |> Membership.tour_changeset(%{admin_tour_completed_at: now})
    |> Repo.update()
    |> case do
      {:ok, membership} -> {:ok, membership}
      {:error, changeset} -> {:error, :validation, changeset}
    end
  end

  ## Per-page tours

  @doc """
  Returns true once this person has seen the first-visit walkthrough for
  `page_key` in the given organization.

  Audience-agnostic: `user` is any `User` (operator or subscriber) and `org`
  the organization the tour is scoped to. A `nil` user or `nil` org is treated
  as already seen, so the tour never auto-starts without a person and a tenant
  to record against.

      iex> Marquee.Accounts.page_tour_completed?(nil, %Marquee.Accounts.Organization{}, "content")
      true

      iex> Marquee.Accounts.page_tour_completed?(%Marquee.Accounts.User{}, nil, "content")
      true

      iex> {:ok, user} = Marquee.Accounts.register_user(%{email: "tour@example.com"})
      iex> org = Marquee.Repo.insert!(%Marquee.Accounts.Organization{name: "Tour example", slug: "tour-example"})
      iex> Marquee.Accounts.page_tour_completed?(user, org, "content")
      false
      iex> {:ok, _completion} = Marquee.Accounts.complete_page_tour(user, org, "content")
      iex> Marquee.Accounts.page_tour_completed?(user, org, "content")
      true
  """
  def page_tour_completed?(nil, _org, _page_key), do: true
  def page_tour_completed?(_user, nil, _page_key), do: true

  def page_tour_completed?(%User{id: user_id}, %Organization{id: org_id}, page_key)
      when is_binary(page_key) do
    PageTourCompletion
    |> where(user_id: ^user_id, organization_id: ^org_id, page_key: ^page_key)
    |> Repo.exists?()
  end

  @doc """
  Records that this person has seen the first-visit walkthrough for `page_key`
  in the given organization. Idempotent — re-recording the same page is a no-op
  that preserves the original "seen" timestamp (`inserted_at`).

  A `nil` user or `nil` org is a no-op returning `{:ok, nil}`.

  Returns `{:ok, completion}` or `{:error, :validation, changeset}`.

  Exempt from doctest — hits the database.
  """
  def complete_page_tour(nil, _org, _page_key), do: {:ok, nil}
  def complete_page_tour(_user, nil, _page_key), do: {:ok, nil}

  def complete_page_tour(%User{id: user_id}, %Organization{id: org_id}, page_key)
      when is_binary(page_key) do
    %PageTourCompletion{}
    |> PageTourCompletion.changeset(%{
      user_id: user_id,
      organization_id: org_id,
      page_key: page_key
    })
    |> Repo.insert(
      on_conflict: :nothing,
      conflict_target: [:user_id, :organization_id, :page_key]
    )
    |> case do
      {:ok, completion} -> {:ok, completion}
      {:error, changeset} -> {:error, :validation, changeset}
    end
  end

  ## Database getters

  @doc """
  Gets a user by email.

  ## Examples

      iex> {:ok, user} = register_user(%{email: "lookup@example.com"})
      iex> get_user_by_email("lookup@example.com").id == user.id
      true

      iex> get_user_by_email("unknown@example.com")
      nil

  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Gets a user by email and password.

  ## Examples

      iex> {:ok, user} = register_user(%{email: "password-lookup@example.com"})
      iex> {:ok, {user, []}} = update_user_password(user, %{password: "correct_password"})
      iex> get_user_by_email_and_password(user.email, "correct_password").id == user.id
      true

      iex> get_user_by_email_and_password("foo@example.com", "invalid_password")
      nil

  """
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    if User.valid_password?(user, password), do: user
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> {:ok, user} = register_user(%{email: "id-lookup@example.com"})
      iex> get_user!(user.id).email
      "id-lookup@example.com"

      iex> try do
      ...>   get_user!("00000000-0000-0000-0000-000000000456")
      ...> rescue
      ...>   Ecto.NoResultsError -> :not_found
      ...> end
      :not_found

  """
  def get_user!(id), do: Repo.get!(User, id)

  ## User registration

  @doc """
  Registers a user.

  ## Examples

      iex> {:ok, user} = register_user(%{email: "registration@example.com"})
      iex> user.email
      "registration@example.com"

      iex> {:error, :validation, changeset} = register_user(%{email: "invalid"})
      iex> Keyword.has_key?(changeset.errors, :email)
      true

  """
  def register_user(attrs) do
    case %User{} |> User.email_changeset(attrs) |> Repo.insert() do
      {:ok, user} -> {:ok, user}
      {:error, changeset} -> {:error, :validation, changeset}
    end
  end

  @doc """
  Creates (or promotes) a super admin and returns a one-time magic-link login
  token, bypassing email delivery.

  Registers the user if the email is new, sets `is_super_admin`, and builds a
  `"login"` token. Returns `{:ok, %{user: user, token: encoded_token}}`; the
  caller turns the token into a `/users/log-in/:token` URL. Used by
  `Marquee.Release.create_super_admin/2` to bootstrap platform access on a
  fresh deploy where no mailer is configured.

  Exempt from doctest — hits the database.
  """
  def create_super_admin_with_login(email) when is_binary(email) do
    with {:ok, user} <- upsert_super_admin(email) do
      {encoded_token, user_token} = UserToken.build_email_token(user, "login")
      Repo.insert!(user_token)
      {:ok, %{user: user, token: encoded_token}}
    end
  end

  defp upsert_super_admin(email) do
    case get_user_by_email(email) do
      nil ->
        with {:ok, user} <- register_user(%{email: email}) do
          promote_to_super_admin(user)
        end

      %User{} = user ->
        promote_to_super_admin(user)
    end
  end

  defp promote_to_super_admin(user) do
    case user |> User.admin_changeset(%{is_super_admin: true}) |> Repo.update() do
      {:ok, user} -> {:ok, user}
      {:error, changeset} -> {:error, :validation, changeset}
    end
  end

  @doc """
  Registers a new user and creates an organization with the user as owner.

  The organization is seeded with the named theme preset (one of
  `Marquee.Branding.Theme.preset_keys/0`) and the user is assigned the `:owner`
  role. When `theme_preset` is omitted, the platform default preset is used. A
  self-service trial subscription is started for the new org (no payment info
  required; see `Marquee.PlatformBilling.start_trial/1`).

  Exempt from doctest — hits the database.
  """
  def register_user_with_organization(user_attrs, org_name, theme_preset \\ nil) do
    slug = slugify(org_name)
    preset_key = resolve_theme_preset(theme_preset)

    Repo.transaction(fn ->
      with {:ok, user} <- %User{} |> User.email_changeset(user_attrs) |> Repo.insert(),
           {:ok, org} <- create_organization_inline(org_name, slug, preset_key),
           {:ok, _membership} <-
             %Membership{}
             |> Membership.changeset(%{user_id: user.id, organization_id: org.id, role: :owner})
             |> Repo.insert(),
           {:ok, _subscription} <- PlatformBilling.start_trial(org) do
        {user, org}
      else
        {:error, :validation, changeset} -> Repo.rollback(changeset)
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
    |> case do
      {:ok, {user, org}} ->
        enqueue_starter_content(org)
        {:ok, user, org}

      {:error, changeset} ->
        {:error, :validation, changeset}
    end
  end

  # Seed sample/starter content asynchronously so it never blocks or rolls back
  # signup. Best-effort: a failure to enqueue must not fail account creation.
  defp enqueue_starter_content(org) do
    %{organization_id: org.id}
    |> SeedStarterContentWorker.new()
    |> Oban.insert()
  end

  defp resolve_theme_preset(nil), do: Theme.default_preset_key()

  defp resolve_theme_preset(key) when is_binary(key) do
    if key in Theme.preset_keys() do
      key
    else
      Theme.default_preset_key()
    end
  end

  # Inline org creation without a nested transaction. Creates the org record
  # and a starter theme from the chosen preset, matching what
  # Admin.create_organization does.
  defp create_organization_inline(name, slug, preset_key) do
    changeset =
      Organization.changeset(%Organization{}, %{name: name, slug: slug, template: "default"})

    case Repo.insert(changeset) do
      {:ok, org} ->
        preset_attrs = Theme.preset_attrs(preset_key)

        {:ok, _theme} =
          preset_attrs
          |> Map.put(:organization_id, org.id)
          |> Branding.create_theme()

        # Self-signup flow: no caller-provided scope yet. Use the freshly
        # minted org so the broadcast attributes to it; routed platform-wide
        # so super admin listeners receive the event.
        scope = %Marquee.Accounts.Scope{organization: org}
        Marquee.Events.broadcast_platform(scope, {:organization_created, org})
        {:ok, org}

      {:error, changeset} ->
        {:error, :validation, changeset}
    end
  end

  defp slugify(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s-]/, "")
    |> String.replace(~r/[\s]+/, "-")
    |> String.trim("-")
  end

  @registration_types %{
    email: :string,
    organization_name: :string,
    theme_preset: :string
  }

  @doc """
  Returns a schemaless changeset for the registration form.

  Validates that email and organization name are present, email has a valid
  format, organization name is between 1 and 100 characters, and the chosen
  `theme_preset` is one of `Marquee.Branding.Theme.preset_keys/0`. The default
  preset is pre-selected so the form renders with a valid value.

  ## Examples

      iex> changeset = Marquee.Accounts.registration_changeset(%{})
      iex> changeset.valid?
      false
      iex> Keyword.keys(Enum.sort(changeset.errors))
      [:email, :organization_name]

      iex> changeset = Marquee.Accounts.registration_changeset(%{"email" => "user@example.com", "organization_name" => "Acme"})
      iex> changeset.valid?
      true
      iex> Ecto.Changeset.get_field(changeset, :theme_preset)
      "midnight"

      iex> changeset = Marquee.Accounts.registration_changeset(%{"email" => "user@example.com", "organization_name" => "Acme", "theme_preset" => "daybreak"})
      iex> Ecto.Changeset.get_field(changeset, :theme_preset)
      "daybreak"

      iex> changeset = Marquee.Accounts.registration_changeset(%{"email" => "user@example.com", "organization_name" => "Acme", "theme_preset" => "neon"})
      iex> changeset.valid?
      false
      iex> {"is invalid", _} = changeset.errors[:theme_preset]

      iex> changeset = Marquee.Accounts.registration_changeset(%{"email" => "bad", "organization_name" => "Acme"})
      iex> changeset.valid?
      false
      iex> {"must have the @ sign and no spaces", _} = changeset.errors[:email]

  """
  def registration_changeset(params) do
    initial_data = %{theme_preset: Theme.default_preset_key()}

    {initial_data, @registration_types}
    |> Ecto.Changeset.cast(params, Map.keys(@registration_types))
    |> Ecto.Changeset.validate_required([:email, :organization_name, :theme_preset])
    |> Ecto.Changeset.validate_format(:email, ~r/^[^\s]+@[^\s]+$/,
      message: "must have the @ sign and no spaces"
    )
    |> Ecto.Changeset.validate_length(:organization_name, min: 1, max: 100)
    |> Ecto.Changeset.validate_inclusion(:theme_preset, Theme.preset_keys())
  end

  @doc """
  Merges errors from a user changeset into the registration changeset.

  This is used after `register_user_with_organization/2` fails with a
  validation error, so that user-schema errors (e.g. "has already been taken")
  appear on the registration form.

  ## Examples

      iex> reg = Marquee.Accounts.registration_changeset(%{"email" => "a@b.com", "organization_name" => "Acme"})
      iex> user_cs = %Ecto.Changeset{errors: [email: {"has already been taken", []}], valid?: false}
      iex> merged = Marquee.Accounts.merge_registration_errors(reg, user_cs)
      iex> {"has already been taken", _} = merged.errors[:email]

  """
  def merge_registration_errors(changeset, user_changeset) do
    Enum.reduce(user_changeset.errors, changeset, fn {field, error}, cs ->
      Ecto.Changeset.add_error(cs, field, elem(error, 0), elem(error, 1))
    end)
  end

  ## Settings

  @doc """
  Checks whether the user is in sudo mode.

  The user is in sudo mode when the last authentication was done no further
  than 20 minutes ago. The limit can be given as second argument in minutes.
  """
  def sudo_mode?(user, minutes \\ -20)

  def sudo_mode?(%User{authenticated_at: ts}, minutes) when is_struct(ts, DateTime) do
    DateTime.after?(ts, DateTime.utc_now() |> DateTime.add(minutes, :minute))
  end

  def sudo_mode?(_user, _minutes), do: false

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user email.

  See `Marquee.Accounts.User.email_changeset/3` for a list of supported options.

  ## Examples

      iex> changeset = change_user_email(%Marquee.Accounts.User{}, %{email: "new@example.com"})
      iex> {changeset.valid?, Ecto.Changeset.get_change(changeset, :email)}
      {true, "new@example.com"}

  """
  def change_user_email(user, attrs \\ %{}, opts \\ []) do
    User.email_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user email using the given token.

  If the token matches, the user email is updated and the token is deleted.
  """
  def update_user_email(user, token) do
    with :ok <- if(Marquee.AdminDemo.normal_user?(user), do: :ok, else: {:error, :demo_forbidden}) do
      authorized_update_user_email(user, token)
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.

  See `Marquee.Accounts.User.password_changeset/3` for a list of supported options.

  ## Examples

      iex> changeset = change_user_password(%Marquee.Accounts.User{}, %{password: "a secure password"}, hash_password: false)
      iex> {changeset.valid?, Ecto.Changeset.get_change(changeset, :password)}
      {true, "a secure password"}

  """
  def change_user_password(user, attrs \\ %{}, opts \\ []) do
    User.password_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user password.

  Returns a tuple with the updated user, as well as a list of expired tokens.

  ## Examples

      iex> {:ok, user} = register_user(%{email: "change-password@example.com"})
      iex> {:ok, {updated, []}} = update_user_password(user, %{password: "a secure password"})
      iex> Marquee.Accounts.User.valid_password?(updated, "a secure password")
      true

      iex> {:error, :validation, changeset} = update_user_password(%Marquee.Accounts.User{}, %{password: "too short"})
      iex> Keyword.has_key?(changeset.errors, :password)
      true

  """
  def update_user_password(user, attrs) do
    with :ok <- if(Marquee.AdminDemo.normal_user?(user), do: :ok, else: {:error, :demo_forbidden}) do
      case user |> User.password_changeset(attrs) |> update_user_and_delete_all_tokens() do
        {:ok, result} -> {:ok, result}
        {:error, changeset} -> {:error, :validation, changeset}
      end
    end
  end

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    with :ok <- if(Marquee.AdminDemo.normal_user?(user), do: :ok, else: {:error, :demo_forbidden}) do
      {token, user_token} = UserToken.build_session_token(user)
      Repo.insert!(user_token)
      token
    end
  end

  @doc """
  Gets the user with the given signed token.

  If the token is valid `{user, token_inserted_at}` is returned, otherwise `nil` is returned.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)

    case Repo.one(query) do
      {%User{demo_kind: nil}, _} = result -> result
      _ -> nil
    end
  end

  @doc """
  Gets the user with the given magic link token.
  """
  def get_user_by_magic_link_token(token) do
    with {:ok, query} <- UserToken.verify_magic_link_token_query(token),
         {%User{demo_kind: nil} = user, _token} <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Logs the user in by magic link.

  There are three cases to consider:

  1. The user has already confirmed their email. They are logged in
     and the magic link is expired.

  2. The user has not confirmed their email and no password is set.
     In this case, the user gets confirmed, logged in, and all tokens -
     including session ones - are expired. In theory, no other tokens
     exist but we delete all of them for best security practices.

  3. The user has not confirmed their email but a password is set.
     This cannot happen in the default implementation but may be the
     source of security pitfalls. See the "Mixing magic link and password registration" section of
     `mix help phx.gen.auth`.
  """
  def login_user_by_magic_link(token) do
    {:ok, query} = UserToken.verify_magic_link_token_query(token)

    case Repo.one(query) do
      {%User{demo_kind: kind}, _token} when not is_nil(kind) ->
        {:error, :demo_forbidden}

      # Prevent session fixation attacks by disallowing magic links for unconfirmed users with password
      {%User{confirmed_at: nil, hashed_password: hash}, _token} when not is_nil(hash) ->
        raise """
        magic link log in is not allowed for unconfirmed users with a password set!

        This cannot happen with the default implementation, which indicates that you
        might have adapted the code to a different use case. Please make sure to read the
        "Mixing magic link and password registration" section of `mix help phx.gen.auth`.
        """

      {%User{confirmed_at: nil} = user, _token} ->
        user
        |> User.confirm_changeset()
        |> update_user_and_delete_all_tokens()

      {user, token} ->
        Repo.delete!(token)
        {:ok, {user, []}}

      nil ->
        {:error, :not_found}
    end
  end

  @doc ~S"""
  Delivers the update email instructions to the given user.

  ## Examples

      iex> {:ok, user} = register_user(%{email: "email-instructions@example.com"})
      iex> {:ok, email} = deliver_user_update_email_instructions(user, user.email, fn token -> "https://example.com/confirm/" <> token end)
      iex> email.to
      [{"", "email-instructions@example.com"}]

  """
  def deliver_user_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    with :ok <- if(Marquee.AdminDemo.normal_user?(user), do: :ok, else: {:error, :demo_forbidden}) do
      {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")

      Repo.insert!(user_token)
      UserNotifier.deliver_update_email_instructions(user, update_email_url_fun.(encoded_token))
    end
  end

  @doc """
  Delivers the magic link login instructions to the given user.
  """
  def deliver_login_instructions(%User{} = user, magic_link_url_fun)
      when is_function(magic_link_url_fun, 1) do
    with :ok <- if(Marquee.AdminDemo.normal_user?(user), do: :ok, else: {:error, :demo_forbidden}) do
      {encoded_token, user_token} = UserToken.build_email_token(user, "login")
      Repo.insert!(user_token)
      UserNotifier.deliver_login_instructions(user, magic_link_url_fun.(encoded_token))
    end
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(from(UserToken, where: [token: ^token, context: "session"]))
    :ok
  end

  ## RBAC helpers

  @role_hierarchy [:viewer_support, :editor, :admin, :owner]

  @doc """
  Returns true if the membership's role meets or exceeds the minimum role.

      iex> Marquee.Accounts.role_at_least?(%Marquee.Accounts.Membership{role: :admin}, :editor)
      true

      iex> Marquee.Accounts.role_at_least?(%Marquee.Accounts.Membership{role: :editor}, :admin)
      false

      iex> Marquee.Accounts.role_at_least?(%Marquee.Accounts.Membership{role: :owner}, :owner)
      true

      iex> Marquee.Accounts.role_at_least?(%Marquee.Accounts.Membership{role: :viewer_support}, :editor)
      false

  """
  def role_at_least?(%Membership{role: role}, minimum_role) do
    role_index(role) >= role_index(minimum_role)
  end

  defp role_index(role) do
    Enum.find_index(@role_hierarchy, &(&1 == role)) || -1
  end

  @doc """
  Returns true if the scope has permission to manage content (videos,
  collections, tags, catalog rows).

  Super admins always have access. Otherwise requires a membership with
  role >= :editor.

      iex> Marquee.Accounts.can_manage_content?(%{user: %{is_super_admin: true}, membership: nil})
      true

      iex> Marquee.Accounts.can_manage_content?(%{user: %{is_super_admin: false}, membership: %Marquee.Accounts.Membership{role: :owner}})
      true

      iex> Marquee.Accounts.can_manage_content?(%{user: %{is_super_admin: false}, membership: %Marquee.Accounts.Membership{role: :editor}})
      true

      iex> Marquee.Accounts.can_manage_content?(%{user: %{is_super_admin: false}, membership: %Marquee.Accounts.Membership{role: :viewer_support}})
      false

      iex> Marquee.Accounts.can_manage_content?(%{user: %{is_super_admin: false}, membership: nil})
      false

  """
  def can_manage_content?(%{user: %{is_super_admin: true}}), do: true

  def can_manage_content?(%{membership: %Membership{} = membership}),
    do: role_at_least?(membership, :editor)

  def can_manage_content?(_), do: false

  @doc """
  Returns true if the scope has permission to manage viewers (invite,
  remove, update viewer accounts).

  Super admins always have access. Otherwise requires a membership with
  role in [:viewer_support, :admin, :owner]. Note that :editor does NOT
  have viewer management permission.

      iex> Marquee.Accounts.can_manage_viewers?(%{user: %{is_super_admin: true}, membership: nil})
      true

      iex> Marquee.Accounts.can_manage_viewers?(%{user: %{is_super_admin: false}, membership: %Marquee.Accounts.Membership{role: :owner}})
      true

      iex> Marquee.Accounts.can_manage_viewers?(%{user: %{is_super_admin: false}, membership: %Marquee.Accounts.Membership{role: :admin}})
      true

      iex> Marquee.Accounts.can_manage_viewers?(%{user: %{is_super_admin: false}, membership: %Marquee.Accounts.Membership{role: :viewer_support}})
      true

      iex> Marquee.Accounts.can_manage_viewers?(%{user: %{is_super_admin: false}, membership: %Marquee.Accounts.Membership{role: :editor}})
      false

      iex> Marquee.Accounts.can_manage_viewers?(%{user: %{is_super_admin: false}, membership: nil})
      false

  """
  def can_manage_viewers?(%{user: %{is_super_admin: true}}), do: true

  def can_manage_viewers?(%{membership: %Membership{role: role}})
      when role in [:viewer_support, :admin, :owner],
      do: true

  def can_manage_viewers?(_), do: false

  @doc """
  Returns true if the scope has permission to view the viewers list.

  Super admins always have access. Otherwise requires a membership with
  role >= :viewer_support.

      iex> Marquee.Accounts.can_view_viewers?(%{user: %{is_super_admin: true}, membership: nil})
      true

      iex> Marquee.Accounts.can_view_viewers?(%{user: %{is_super_admin: false}, membership: %Marquee.Accounts.Membership{role: :viewer_support}})
      true

      iex> Marquee.Accounts.can_view_viewers?(%{user: %{is_super_admin: false}, membership: %Marquee.Accounts.Membership{role: :editor}})
      true

      iex> Marquee.Accounts.can_view_viewers?(%{user: %{is_super_admin: false}, membership: nil})
      false

  """
  def can_view_viewers?(%{user: %{is_super_admin: true}}), do: true

  def can_view_viewers?(%{membership: %Membership{} = membership}),
    do: role_at_least?(membership, :viewer_support)

  def can_view_viewers?(_), do: false

  ## Token helper

  defp update_user_and_delete_all_tokens(changeset) do
    Repo.transact(fn ->
      with {:ok, user} <- Repo.update(changeset) do
        tokens_to_expire = Repo.all_by(UserToken, user_id: user.id)

        Repo.delete_all(from(t in UserToken, where: t.id in ^Enum.map(tokens_to_expire, & &1.id)))

        {:ok, {user, tokens_to_expire}}
      end
    end)
  end

  @doc """
  Updates per-tenant branding fields on an organization (accent color
  variants, display font, preset name). Returns tagged tuples.

  Exempt from doctest — hits the database.
  """
  def update_organization_branding(org, attrs), do: update_organization_branding(nil, org, attrs)

  @doc "Scoped sandbox-safe mutation. Requires database access."
  def update_organization_branding(scope, %Organization{} = org, attrs) do
    with :ok <- Marquee.AdminDemo.authorize(scope, :branding_edit, org) do
      case org |> Organization.branding_changeset(attrs) |> Repo.update() do
        {:ok, updated} ->
          Marquee.Events.broadcast(
            %Marquee.Accounts.Scope{organization: updated},
            {:organization_branding_updated, updated}
          )

          {:ok, updated}

        {:error, changeset} ->
          {:error, :validation, changeset}
      end
    end
  end

  defp authorized_update_user_email(user, token) do
    context = "change:#{user.email}"

    Repo.transact(fn ->
      with {:ok, query} <- UserToken.verify_change_email_token_query(token, context),
           %UserToken{sent_to: email} <- Repo.one(query),
           {:ok, user} <- Repo.update(User.email_changeset(user, %{email: email})),
           {_count, _result} <-
             Repo.delete_all(from(UserToken, where: [user_id: ^user.id, context: ^context])) do
        {:ok, user}
      else
        _ -> {:error, :transaction_aborted}
      end
    end)
  end
end
