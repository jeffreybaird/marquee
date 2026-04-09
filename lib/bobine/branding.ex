defmodule Bobine.Branding do
  @moduledoc """
  The Branding context.
  """

  import Ecto.Query, warn: false
  alias Bobine.Accounts.Organization
  alias Bobine.Cache
  alias Bobine.Events
  alias Bobine.Repo

  alias Bobine.Branding.Theme

  @doc """
  Returns the list of themes for a given organization.

  Exempt from doctest — hits the database.
  """
  def list_themes(%Bobine.Accounts.Organization{id: org_id}) do
    Theme
    |> where([t], t.organization_id == ^org_id)
    |> Repo.all()
  end

  @doc """
  Gets a single theme.

  Raises `Ecto.NoResultsError` if the Theme does not exist.

  ## Examples

      iex> get_theme!(123)
      %Theme{}

      iex> get_theme!(456)
      ** (Ecto.NoResultsError)

  """
  def get_theme!(id), do: Repo.get!(Theme, id)

  @doc """
  Gets the theme for a given organization, or nil if none exists.

  Exempt from doctest — hits the database.
  """
  def get_theme_by_org(%Bobine.Accounts.Organization{id: org_id}) do
    Repo.get_by(Theme, organization_id: org_id)
  end

  @doc """
  Creates a theme.

  ## Examples

      iex> create_theme(%{field: value})
      {:ok, %Theme{}}

      iex> create_theme(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_theme(attrs) do
    case %Theme{} |> Theme.changeset(attrs) |> Repo.insert() do
      {:ok, theme} ->
        invalidate_theme_cache(theme.organization_id)
        {:ok, theme}

      {:error, changeset} ->
        {:error, :validation, changeset}
    end
  end

  @doc """
  Updates a theme.

  ## Examples

      iex> update_theme(theme, %{field: new_value})
      {:ok, %Theme{}}

      iex> update_theme(theme, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_theme(%Theme{} = theme, attrs) do
    case theme |> Theme.changeset(attrs) |> Repo.update() do
      {:ok, theme} ->
        invalidate_theme_cache(theme.organization_id)
        Events.broadcast(nil, {:theme_updated, theme})
        {:ok, theme}

      {:error, changeset} ->
        {:error, :validation, changeset}
    end
  end

  @doc """
  Deletes a theme.

  ## Examples

      iex> delete_theme(theme)
      {:ok, %Theme{}}

      iex> delete_theme(theme)
      {:error, %Ecto.Changeset{}}

  """
  def delete_theme(%Theme{} = theme) do
    case Repo.delete(theme) do
      {:ok, deleted_theme} ->
        invalidate_theme_cache(deleted_theme.organization_id)
        {:ok, deleted_theme}

      other ->
        other
    end
  end

  @doc """
  Returns the theme for an organization, or an empty struct with defaults when none exists.

  Exempt from doctest — hits the database.
  """
  def get_theme_or_default(%Bobine.Accounts.Organization{} = org) do
    case get_theme_by_org(org) do
      nil -> %Theme{}
      theme -> theme
    end
  end

  @doc """
  Cached variant of `get_theme_or_default/1` for hot LiveView mount paths.
  """
  def get_theme_or_default_cached(%Bobine.Accounts.Organization{} = org) do
    Cache.fetch("theme:#{org.id}", [ttl: 300_000], fn ->
      get_theme_or_default(org)
    end)
  end

  @doc """
  Returns the CSS custom property string for an organization's theme.

  Exempt from doctest — hits the database.
  """
  def build_theme_css_vars(%Bobine.Accounts.Organization{} = org) do
    org
    |> get_theme_or_default()
    |> Theme.build_css_vars()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking theme changes.

  ## Examples

      iex> change_theme(theme)
      %Ecto.Changeset{data: %Theme{}}

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
      `Bobine.Branding.Theme.default_preset_key/0`). Must be one of
      `Bobine.Branding.Theme.preset_keys/0`.
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

  defp invalidate_theme_cache(org_id) do
    Cache.delete("theme:#{org_id}")
  end
end
