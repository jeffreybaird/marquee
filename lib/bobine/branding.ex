defmodule Bobine.Branding do
  @moduledoc """
  The Branding context.
  """

  import Ecto.Query, warn: false
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

  defp invalidate_theme_cache(org_id) do
    Cache.delete("theme:#{org_id}")
  end
end
