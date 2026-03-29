defmodule Bobine.Billing do
  @moduledoc """
  The Billing context.
  """

  import Ecto.Query, warn: false
  alias Bobine.Repo
  alias Bobine.Pagination
  alias Bobine.Events

  require Bobine.Otel

  alias Bobine.Billing.Plan

  @doc """
  Returns a paginated list of plans, excluding soft-deleted records.

  Exempt from doctest — hits the database.
  """
  def list_plans(opts \\ []) do
    Plan
    |> where([p], is_nil(p.deleted_at))
    |> order_by(desc: :inserted_at)
    |> Pagination.paginate(opts)
  end

  @doc """
  Returns the list of plans including soft-deleted records.

  Exempt from doctest — hits the database.
  """
  def list_plans_including_deleted do
    Repo.all(Plan)
  end

  @doc """
  Gets a single plan.

  Raises `Ecto.NoResultsError` if the Plan does not exist.

  ## Examples

      iex> get_plan!(123)
      %Plan{}

      iex> get_plan!(456)
      ** (Ecto.NoResultsError)

  """
  def get_plan!(id), do: Repo.get!(Plan, id)

  @doc """
  Creates a plan.

  Exempt from doctest — hits the database.
  """
  def create_plan(attrs) do
    with {:ok, plan} <- %Plan{} |> Plan.changeset(attrs) |> Repo.insert() do
      Events.broadcast(nil, {:plan_created, plan})
      {:ok, plan}
    else
      {:error, changeset} -> {:error, :validation, changeset}
    end
  end

  @doc """
  Updates a plan.

  Exempt from doctest — hits the database.
  """
  def update_plan(%Plan{} = plan, attrs) do
    with {:ok, plan} <- plan |> Plan.changeset(attrs) |> Repo.update() do
      Events.broadcast(nil, {:plan_updated, plan})
      {:ok, plan}
    else
      {:error, changeset} -> {:error, :validation, changeset}
    end
  end

  @doc """
  Soft-deletes a plan by setting `deleted_at`.

  Exempt from doctest — hits the database.
  """
  def delete_plan(%Plan{} = plan) do
    plan
    |> Ecto.Changeset.change(deleted_at: DateTime.utc_now() |> DateTime.truncate(:second))
    |> Repo.update()
  end

  @doc """
  Restores a soft-deleted plan by clearing `deleted_at`.

  Exempt from doctest — hits the database.
  """
  def restore_plan(%Plan{} = plan) do
    plan
    |> Ecto.Changeset.change(deleted_at: nil)
    |> Repo.update()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking plan changes.

  ## Examples

      iex> change_plan(%Bobine.Billing.Plan{})
      %Ecto.Changeset{data: %Bobine.Billing.Plan{}}

  """
  def change_plan(%Plan{} = plan, attrs \\ %{}) do
    Plan.changeset(plan, attrs)
  end

  alias Bobine.Billing.Subscription

  @doc """
  Returns a paginated list of subscriptions.

  Exempt from doctest — hits the database.
  """
  def list_subscriptions(opts \\ []) do
    Subscription
    |> order_by(desc: :inserted_at)
    |> Pagination.paginate(opts)
  end

  @doc """
  Gets a single subscription.

  Raises `Ecto.NoResultsError` if the Subscription does not exist.

  ## Examples

      iex> get_subscription!(123)
      %Subscription{}

      iex> get_subscription!(456)
      ** (Ecto.NoResultsError)

  """
  def get_subscription!(id), do: Repo.get!(Subscription, id)

  @doc """
  Creates a subscription.

  Exempt from doctest — hits the database.
  """
  def create_subscription(attrs) do
    Bobine.Otel.with_span "bobine.billing.create_subscription" do
      with {:ok, sub} <- %Subscription{} |> Subscription.changeset(attrs) |> Repo.insert() do
        Events.broadcast(nil, {:subscription_created, sub})
        {:ok, sub}
      else
        {:error, changeset} -> {:error, :validation, changeset}
      end
    end
  end

  @doc """
  Updates a subscription.

  Exempt from doctest — hits the database.
  """
  def update_subscription(%Subscription{} = subscription, attrs) do
    case subscription |> Subscription.changeset(attrs) |> Repo.update() do
      {:ok, sub} -> {:ok, sub}
      {:error, changeset} -> {:error, :validation, changeset}
    end
  end

  @doc """
  Deletes a subscription.

  Exempt from doctest — hits the database.
  """
  def delete_subscription(%Subscription{} = subscription) do
    Repo.delete(subscription)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking subscription changes.

  ## Examples

      iex> change_subscription(%Bobine.Billing.Subscription{})
      %Ecto.Changeset{data: %Bobine.Billing.Subscription{}}

  """
  def change_subscription(%Subscription{} = subscription, attrs \\ %{}) do
    Subscription.changeset(subscription, attrs)
  end
end
