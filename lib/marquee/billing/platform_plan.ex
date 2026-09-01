defmodule Marquee.Billing.PlatformPlan do
  @moduledoc """
  A platform-level subscription plan that organizations subscribe to for Marquee access.

  Platform plans are global — they have no `organization_id`. They define the
  usage limits and feature access for each org based on a 3x3 grid of
  usage tier (basic/super/premium) x business tier (individual/small_business/enterprise).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "platform_plans" do
    field :name, :string
    field :slug, :string
    field :stripe_product_id, :string
    field :stripe_price_id, :string

    # Pricing
    field :amount, :integer
    field :currency, :string, default: "usd"
    field :interval, Ecto.Enum, values: [:monthly, :yearly], default: :monthly

    # Tier classification
    field :usage_tier, Ecto.Enum, values: [:basic, :super, :premium]
    field :business_tier, Ecto.Enum, values: [:individual, :small_business, :enterprise]

    # Usage limits (nil = unlimited)
    field :max_videos, :integer
    field :max_monthly_views, :integer
    field :max_storage_gb, :integer
    field :max_team_seats, :integer
    field :max_webhook_endpoints, :integer

    # Feature flags this plan enables
    field :enabled_features, {:array, :string}, default: []

    # Display
    field :description, :string
    field :highlight, :boolean, default: false
    field :position, :integer, default: 0
    field :active, :boolean, default: true

    # Legacy field — kept for backward compatibility during migration
    field :transaction_fee_percent, :float, default: 5.0

    field :deleted_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @required_fields [:name, :slug, :amount, :usage_tier, :business_tier]
  @optional_fields [
    :stripe_product_id,
    :stripe_price_id,
    :currency,
    :interval,
    :max_videos,
    :max_monthly_views,
    :max_storage_gb,
    :max_team_seats,
    :max_webhook_endpoints,
    :enabled_features,
    :description,
    :highlight,
    :position,
    :active,
    :transaction_fee_percent,
    :deleted_at
  ]

  @doc false
  def changeset(platform_plan, attrs) do
    platform_plan
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint(:slug)
    |> unique_constraint([:usage_tier, :business_tier])
    |> validate_number(:amount, greater_than_or_equal_to: 0)
    |> validate_inclusion(:usage_tier, [:basic, :super, :premium])
    |> validate_inclusion(:business_tier, [:individual, :small_business, :enterprise])
  end
end
