defmodule Bobine.Branding.Theme do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "themes" do
    field :brand_primary, :string
    field :brand_secondary, :string
    field :background, :string
    field :surface, :string
    field :text_primary, :string
    field :text_secondary, :string
    field :accent, :string
    field :font_heading, :string
    field :font_body, :string
    field :border_radius, :string
    field :card_border_radius, :string
    field :logo_url, :string
    field :favicon_url, :string

    belongs_to :organization, Bobine.Accounts.Organization

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(theme, attrs) do
    theme
    |> cast(attrs, [
      :brand_primary,
      :brand_secondary,
      :background,
      :surface,
      :text_primary,
      :text_secondary,
      :accent,
      :font_heading,
      :font_body,
      :border_radius,
      :card_border_radius,
      :logo_url,
      :favicon_url,
      :organization_id
    ])
    |> validate_required([:organization_id])
  end
end
