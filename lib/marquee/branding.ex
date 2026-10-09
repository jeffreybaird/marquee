defmodule Marquee.Branding do
  @moduledoc """
  The Branding context.
  """

  import Ecto.Query, warn: false
  alias Marquee.Accounts.Organization
  alias Marquee.Cache
  alias Marquee.Events
  alias Marquee.Repo

  alias Marquee.Branding.Theme

  require Marquee.Otel

  @doc """
  Returns a paginated list of themes for a given organization.

  Exempt from doctest — hits the database.
  """
  def list_themes(%Marquee.Accounts.Organization{id: org_id}, opts \\ []) do
    Theme
    |> where([t], t.organization_id == ^org_id)
    |> Marquee.Pagination.paginate(opts)
  end

  @doc """
  Gets a single theme.

  Raises `Ecto.NoResultsError` if the Theme does not exist.

  ## Examples

      iex> org = Marquee.Repo.insert!(%Marquee.Accounts.Organization{name: "Theme example", slug: "theme-example"})
      iex> {:ok, theme} = create_theme(%{organization_id: org.id})
      iex> get_theme!(theme.id).organization_id == org.id
      true

      iex> try do
      ...>   get_theme!("00000000-0000-0000-0000-000000000456")
      ...> rescue
      ...>   Ecto.NoResultsError -> :not_found
      ...> end
      :not_found

  """
  def get_theme!(id), do: Repo.get!(Theme, id)

  @doc """
  Gets the theme for a given organization, or nil if none exists.

  Exempt from doctest — hits the database.
  """
  def get_theme_by_org(%Marquee.Accounts.Organization{id: org_id}) do
    Repo.get_by(Theme, organization_id: org_id)
  end

  @doc """
  Creates a theme.

  ## Examples

      iex> org = Marquee.Repo.insert!(%Marquee.Accounts.Organization{name: "New theme", slug: "new-theme"})
      iex> {:ok, theme} = create_theme(%{organization_id: org.id, background: "#112233"})
      iex> theme.background
      "#112233"

      iex> {:error, :validation, changeset} = create_theme(%{})
      iex> Keyword.has_key?(changeset.errors, :organization_id)
      true

  """
  def create_theme(scope \\ nil, attrs) do
    with :ok <- Marquee.AdminDemo.authorize_creation(scope, :branding_edit, attrs) do
      create_authorized_theme(scope, attrs)
    end
  end

  defp create_authorized_theme(scope, attrs) do
    Marquee.Otel.with_span "marquee.branding.create_theme", otel_scope_attrs(scope) do
      case %Theme{} |> Theme.changeset(attrs) |> Repo.insert() do
        {:ok, theme} ->
          Events.broadcast(scope, {:theme_created, theme})
          {:ok, theme}

        {:error, changeset} ->
          {:error, :validation, changeset}
      end
    end
  end

  @doc """
  Applies a named starter preset (see `Marquee.Branding.Theme.presets/0`) to
  an organization's theme, creating the theme if the org has none yet.

  Returns `{:error, :invalid_preset}` for an unknown key.

  Exempt from doctest — hits the database.
  """
  def apply_theme_preset(scope \\ nil, %Organization{} = org, key) when is_binary(key) do
    with :ok <- Marquee.AdminDemo.authorize(scope, :branding_edit, org) do
      authorized_apply_theme_preset(scope, org, key)
    end
  end

  @doc """
  Updates a theme.

  Accepts an optional scope so the broadcast + audit subscriber can
  attribute the action to the acting user/org.

  ## Examples

      iex> org = Marquee.Repo.insert!(%Marquee.Accounts.Organization{name: "Theme update", slug: "theme-update"})
      iex> {:ok, theme} = create_theme(%{organization_id: org.id})
      iex> {:ok, updated} = update_theme(theme, %{background: "#334455"})
      iex> updated.background
      "#334455"

      iex> {:error, :validation, changeset} = update_theme(%Marquee.Branding.Theme{}, %{organization_id: nil})
      iex> Keyword.has_key?(changeset.errors, :organization_id)
      true

  """
  def update_theme(scope \\ nil, %Theme{} = theme, attrs) do
    with :ok <- Marquee.AdminDemo.authorize(scope, :branding_edit, theme) do
      Marquee.Otel.with_span "marquee.branding.update_theme",
                             %{
                               "marquee.org.id" => theme.organization_id,
                               "marquee.theme.id" => theme.id
                             } do
        case theme |> Theme.changeset(attrs) |> Repo.update() do
          {:ok, theme} ->
            Events.broadcast(scope, {:theme_updated, theme})
            {:ok, theme}

          {:error, changeset} ->
            {:error, :validation, changeset}
        end
      end
    end
  end

  @doc """
  Deletes a theme.

  ## Examples

      iex> org = Marquee.Repo.insert!(%Marquee.Accounts.Organization{name: "Theme deletion", slug: "theme-deletion"})
      iex> {:ok, theme} = create_theme(%{organization_id: org.id})
      iex> {:ok, deleted} = delete_theme(theme)
      iex> deleted.id == theme.id
      true
      iex> get_theme_by_org(org)
      nil

  """
  def delete_theme(scope \\ nil, %Theme{} = theme) do
    with :ok <- Marquee.AdminDemo.authorize(scope, :branding_edit, theme) do
      Marquee.Otel.with_span "marquee.branding.delete_theme",
                             %{
                               "marquee.org.id" => theme.organization_id,
                               "marquee.theme.id" => theme.id
                             } do
        case Repo.delete(theme) do
          {:ok, deleted_theme} ->
            Events.broadcast(scope, {:theme_deleted, deleted_theme})
            {:ok, deleted_theme}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:error, :validation, changeset}
        end
      end
    end
  end

  @doc """
  Returns the theme for an organization, or an empty struct with defaults when none exists.

  Exempt from doctest — hits the database.
  """
  def get_theme_or_default(%Marquee.Accounts.Organization{} = org) do
    case get_theme_by_org(org) do
      nil -> %Theme{}
      theme -> theme
    end
  end

  @doc """
  Cached variant of `get_theme_or_default/1` for hot LiveView mount paths.
  """
  def get_theme_or_default_cached(%Marquee.Accounts.Organization{} = org) do
    Cache.fetch("theme:#{org.id}", [ttl: 300_000], fn ->
      get_theme_or_default(org)
    end)
  end

  @theme_preview_ttl 3_600_000

  @doc """
  Stores an operator's unsaved appearance draft under an org-scoped cache key.

  The draft is a plain map of the editor's live preview state
  (`%{theme: %Theme{}, accent_color_base: String.t() | nil, display_font: String.t() | nil}`).
  It lives for one hour so an abandoned editor cannot leave a stale draft on
  the viewer site indefinitely.

  Exempt from doctest — uses the cache.
  """
  def put_theme_preview(%Marquee.Accounts.Organization{} = org, preview_id, draft)
      when is_binary(preview_id) and is_map(draft) do
    Cache.put(theme_preview_key(org, preview_id), draft, ttl: @theme_preview_ttl)
  end

  @doc """
  Returns the stored appearance draft for an organization, or `nil`.

  Exempt from doctest — uses the cache.
  """
  def get_theme_preview(_org, nil), do: nil

  def get_theme_preview(%Marquee.Accounts.Organization{} = org, preview_id)
      when is_binary(preview_id) do
    case Cache.get(theme_preview_key(org, preview_id)) do
      {:ok, draft} -> draft
      :miss -> nil
    end
  end

  @doc """
  Removes a stored appearance draft. A no-op when nothing is stored.

  Exempt from doctest — uses the cache.
  """
  def clear_theme_preview(%Marquee.Accounts.Organization{} = org, preview_id)
      when is_binary(preview_id) do
    Cache.delete(theme_preview_key(org, preview_id))
  end

  defp theme_preview_key(%{id: org_id}, preview_id), do: "theme_preview:#{org_id}:#{preview_id}"

  @doc """
  Returns the CSS custom property string for an organization's theme.

  Exempt from doctest — hits the database.
  """
  def build_theme_css_vars(%Marquee.Accounts.Organization{} = org) do
    org
    |> get_theme_or_default()
    |> Theme.build_css_vars()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking theme changes.

  ## Examples

      iex> changeset = change_theme(%Marquee.Branding.Theme{organization_id: "00000000-0000-0000-0000-000000000001"}, %{background: "#112233"})
      iex> {changeset.valid?, Ecto.Changeset.get_change(changeset, :background)}
      {true, "#112233"}

  """
  def change_theme(%Theme{} = theme, attrs \\ %{}) do
    Theme.changeset(theme, attrs)
  end

  @doc """
  Returns the list of non-deleted organizations that do not yet have a theme.

  Exempt from doctest — hits the database.
  """
  def list_orgs_without_theme do
    from(o in Organization,
      left_join: t in Theme,
      on: t.organization_id == o.id,
      where: is_nil(t.id) and is_nil(o.deleted_at),
      order_by: o.inserted_at,
      select: o
    )
    |> Repo.all()
  end

  @doc """
  Creates a starter theme from the given preset for every non-deleted
  organization that does not yet have one.

  ## Options

    * `:preset` - the preset key to apply (defaults to
      `Marquee.Branding.Theme.default_preset_key/0`). Must be one of
      `Marquee.Branding.Theme.preset_keys/0`.
    * `:dry_run` - when `true`, lists matching orgs without writing.
      Defaults to `false`.

  Returns `{:ok, summary}` where `summary` has `:created`, `:dry_run?`,
  `:preset`, `:orgs` (the orgs that were processed) and `:failed`
  (a list of `{org, reason}` tuples). Returns `{:error, :unknown_preset}`
  when an invalid preset key is supplied.

  Exempt from doctest — hits the database.
  """
  def backfill_missing_themes(opts \\ []) do
    preset_key = Keyword.get(opts, :preset, Theme.default_preset_key())
    dry_run? = Keyword.get(opts, :dry_run, false)

    case Theme.preset_attrs(preset_key) do
      nil ->
        {:error, :unknown_preset}

      preset_attrs ->
        orgs = list_orgs_without_theme()

        cond do
          orgs == [] ->
            {:ok, empty_summary(preset_key, dry_run?)}

          dry_run? ->
            {:ok,
             %{
               created: 0,
               dry_run?: true,
               preset: preset_key,
               orgs: orgs,
               failed: []
             }}

          true ->
            apply_preset_to_orgs(orgs, preset_attrs, preset_key)
        end
    end
  end

  defp empty_summary(preset_key, dry_run?) do
    %{created: 0, dry_run?: dry_run?, preset: preset_key, orgs: [], failed: []}
  end

  defp apply_preset_to_orgs(orgs, preset_attrs, preset_key) do
    {created, failed} =
      Enum.reduce(orgs, {[], []}, fn org, {ok_acc, err_acc} ->
        attrs = Map.put(preset_attrs, :organization_id, org.id)

        case create_theme(attrs) do
          {:ok, _theme} -> {[org | ok_acc], err_acc}
          {:error, :validation, changeset} -> {ok_acc, [{org, changeset} | err_acc]}
        end
      end)

    {:ok,
     %{
       created: length(created),
       dry_run?: false,
       preset: preset_key,
       orgs: Enum.reverse(created),
       failed: Enum.reverse(failed)
     }}
  end

  defp otel_scope_attrs(%{organization: %{id: id}}), do: %{"marquee.org.id" => id}
  defp otel_scope_attrs(_), do: %{}

  defp authorized_apply_theme_preset(scope, org, key) do
    case Theme.preset_attrs(key) do
      nil ->
        {:error, :invalid_preset}

      attrs ->
        case get_theme_by_org(org) do
          nil -> create_theme(scope, Map.put(attrs, :organization_id, org.id))
          %Theme{} = theme -> update_theme(scope, theme, attrs)
        end
    end
  end
end
