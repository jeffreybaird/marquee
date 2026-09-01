defmodule Marquee.Podcasts.ShowTier do
  @moduledoc """
  Join record between a Show and a Plan. Used when the show's `access_mode`
  is `"specific_tiers"` to enumerate which plans grant access.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Marquee.Billing.Plan
  alias Marquee.Podcasts.Show

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "podcast_show_tiers" do
    belongs_to :organization, Marquee.Accounts.Organization
    belongs_to :show, Show
    belongs_to :plan, Plan

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(tier, attrs) do
    tier
    |> cast(attrs, [:organization_id, :show_id, :plan_id])
    |> validate_required([:organization_id, :show_id, :plan_id])
    |> unique_constraint([:show_id, :plan_id])
    |> foreign_key_constraint(:show_id)
    |> foreign_key_constraint(:plan_id)
  end
end
