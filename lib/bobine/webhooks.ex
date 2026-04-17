defmodule Bobine.Webhooks do
  @moduledoc """
  The Webhooks context.
  """

  import Ecto.Query, warn: false
  alias Bobine.Accounts.Organization
  alias Bobine.Events
  alias Bobine.Pagination
  alias Bobine.Repo

  alias Bobine.Webhooks.Endpoint

  require Bobine.Otel

  @doc """
  Returns a paginated list of webhook_endpoints for an organization,
  excluding soft-deleted records.

  Exempt from doctest — hits the database.
  """
  def list_webhook_endpoints(%Organization{id: org_id}, opts \\ []) do
    Endpoint
    |> where([e], e.organization_id == ^org_id)
    |> where([e], is_nil(e.deleted_at))
    |> order_by(desc: :inserted_at)
    |> Pagination.paginate(opts)
  end

  @doc """
  Returns the list of webhook_endpoints for an organization including
  soft-deleted records.

  Exempt from doctest — hits the database.
  """
  def list_webhook_endpoints_including_deleted(%Organization{id: org_id}) do
    Endpoint
    |> where([e], e.organization_id == ^org_id)
    |> Repo.all()
  end

  @doc """
  Gets a single endpoint.

  Raises `Ecto.NoResultsError` if the Endpoint does not exist.

  ## Examples

      iex> get_endpoint!(123)
      %Endpoint{}

      iex> get_endpoint!(456)
      ** (Ecto.NoResultsError)

  """
  def get_endpoint!(id), do: Repo.get!(Endpoint, id)

  @doc """
  Creates a endpoint.

  Accepts an optional scope so the broadcast + audit subscriber can
  attribute the action to the acting user/org.

  Exempt from doctest — hits the database.
  """
  def create_endpoint(scope \\ nil, attrs) do
    Bobine.Otel.with_span "bobine.webhooks.create_endpoint", otel_scope_attrs(scope) do
      case %Endpoint{} |> Endpoint.changeset(attrs) |> Repo.insert() do
        {:ok, endpoint} ->
          Events.broadcast(scope, {:endpoint_created, endpoint})
          {:ok, endpoint}

        {:error, changeset} ->
          {:error, :validation, changeset}
      end
    end
  end

  @doc """
  Updates a endpoint.

  Accepts an optional scope so the broadcast + audit subscriber can
  attribute the action to the acting user/org.

  Exempt from doctest — hits the database.
  """
  def update_endpoint(scope \\ nil, %Endpoint{} = endpoint, attrs) do
    Bobine.Otel.with_span "bobine.webhooks.update_endpoint",
                          %{
                            "bobine.org.id" => endpoint.organization_id,
                            "bobine.endpoint.id" => endpoint.id
                          } do
      case endpoint |> Endpoint.changeset(attrs) |> Repo.update() do
        {:ok, endpoint} ->
          Events.broadcast(scope, {:endpoint_updated, endpoint})
          {:ok, endpoint}

        {:error, changeset} ->
          {:error, :validation, changeset}
      end
    end
  end

  @doc """
  Soft-deletes an endpoint by setting `deleted_at`.

  Accepts an optional scope so the broadcast + audit subscriber can
  attribute the action to the acting user/org.

  Exempt from doctest — hits the database.
  """
  def delete_endpoint(scope \\ nil, %Endpoint{} = endpoint) do
    Bobine.Otel.with_span "bobine.webhooks.delete_endpoint",
                          %{
                            "bobine.org.id" => endpoint.organization_id,
                            "bobine.endpoint.id" => endpoint.id
                          } do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      case endpoint |> Ecto.Changeset.change(deleted_at: now) |> Repo.update() do
        {:ok, endpoint} ->
          Events.broadcast(scope, {:endpoint_deleted, endpoint})
          {:ok, endpoint}

        {:error, changeset} ->
          {:error, :validation, changeset}
      end
    end
  end

  @doc """
  Restores a soft-deleted endpoint by clearing `deleted_at`.

  Exempt from doctest — hits the database.
  """
  def restore_endpoint(%Endpoint{} = endpoint) do
    case endpoint |> Ecto.Changeset.change(deleted_at: nil) |> Repo.update() do
      {:ok, endpoint} -> {:ok, endpoint}
      {:error, changeset} -> {:error, :validation, changeset}
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking endpoint changes.

  ## Examples

      iex> change_endpoint(%Bobine.Webhooks.Endpoint{})
      %Ecto.Changeset{data: %Bobine.Webhooks.Endpoint{}}

  """
  def change_endpoint(%Endpoint{} = endpoint, attrs \\ %{}) do
    Endpoint.changeset(endpoint, attrs)
  end

  defp otel_scope_attrs(%{organization: %{id: id}}), do: %{"bobine.org.id" => id}
  defp otel_scope_attrs(_), do: %{}
end
