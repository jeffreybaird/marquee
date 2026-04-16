defmodule Bobine.Accounts.Organization do
  use Ecto.Schema
  import Ecto.Changeset

  @approved_display_fonts [
    "Cormorant Garamond",
    "Playfair Display",
    "DM Serif Display",
    "Libre Baskerville",
    "Bodoni Moda"
  ]

  @approved_body_fonts [
    "Lora",
    "Merriweather",
    "Source Serif 4",
    "Spectral",
    "EB Garamond"
  ]

  @approved_presets ~w(catalog_cinema learning_platform creator_channel)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "organizations" do
    field :name, :string
    field :slug, :string
    field :custom_domain, :string
    field :stripe_account_id, :string
    field :stripe_connect_account_id, :string
    field :stripe_connect_onboarding_complete, :boolean, default: false
    field :stripe_customer_id, :string
    field :template, :string, default: "default"
    field :deleted_at, :utc_datetime
    field :features, :map, default: %{}

    field :accent_color_base, :string
    field :accent_color_hover, :string
    field :accent_color_active, :string
    field :accent_color_subtle, :string
    field :display_font, :string
    field :preset_name, :string
    field :admin_accent_color, :string

    has_many :themes, Bobine.Branding.Theme
    has_many :memberships, Bobine.Accounts.Membership

    timestamps(type: :utc_datetime)
  end

  @doc """
  Returns the list of display fonts an operator may select.

      iex> Bobine.Accounts.Organization.approved_display_fonts() |> Enum.member?("Playfair Display")
      true
  """
  def approved_display_fonts, do: @approved_display_fonts

  @doc """
  Returns the list of body fonts an operator may select.

      iex> Bobine.Accounts.Organization.approved_body_fonts() |> Enum.member?("Lora")
      true
  """
  def approved_body_fonts, do: @approved_body_fonts

  @doc false
  def changeset(organization, attrs) do
    organization
    |> cast(attrs, [
      :name,
      :slug,
      :custom_domain,
      :stripe_account_id,
      :stripe_connect_account_id,
      :stripe_connect_onboarding_complete,
      :stripe_customer_id,
      :template,
      :features
    ])
    |> validate_required([:name, :slug])
    |> unique_constraint(:slug)
    |> unique_constraint(:custom_domain)
  end

  @doc """
  Changeset for per-tenant branding fields. Validates display font against
  the approved Google Fonts allowlist.
  """
  def branding_changeset(organization, attrs) do
    organization
    |> cast(attrs, [
      :accent_color_base,
      :accent_color_hover,
      :accent_color_active,
      :accent_color_subtle,
      :display_font,
      :preset_name,
      :admin_accent_color
    ])
    |> validate_inclusion(:display_font, @approved_display_fonts,
      message: "must be one of the approved Google Fonts"
    )
    |> validate_inclusion(:preset_name, @approved_presets)
    |> validate_accent_color(:accent_color_base)
    |> validate_accent_color(:accent_color_hover)
    |> validate_accent_color(:accent_color_active)
    |> validate_accent_color(:accent_color_subtle)
    |> validate_accent_color(:admin_accent_color)
  end

  # Accept either an oklch() value (preferred) or a hex color (legacy —
  # values backfilled from the old Theme.brand_primary column during
  # the Wave B branding unification). Both render fine in CSS.
  defp validate_accent_color(changeset, field) do
    validate_format(changeset, field, ~r/^(oklch\(|#)/,
      message: "must be an oklch() or hex color"
    )
  end
end
