defmodule Bobine.Catalog.HeroSlide do
  @moduledoc """
  Schema for hero carousel slides.

  Each slide belongs to a hero-type catalog row and links to a video.
  Operators can override text fields (headline, subheadline, etc.) — blanks
  fall back to the linked video's defaults at render time.

  Hard limit: 4 slides per hero row, enforced by position check constraint
  (0–3) and the context function `create_hero_slide/3`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "hero_slides" do
    belongs_to :organization, Bobine.Accounts.Organization
    belongs_to :row, Bobine.Catalog.Row
    belongs_to :video, Bobine.Content.Video

    field :position, :integer, default: 0

    # Custom overlay text
    field :headline, :string
    field :subheadline, :string
    field :brand_tag, :string
    field :description, :string
    field :primary_cta_label, :string
    field :secondary_cta_label, :string

    # Optional custom background image
    field :background_image_url, :string

    field :deleted_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(slide, attrs) do
    slide
    |> cast(attrs, [
      :organization_id,
      :row_id,
      :video_id,
      :position,
      :headline,
      :subheadline,
      :brand_tag,
      :description,
      :primary_cta_label,
      :secondary_cta_label,
      :background_image_url
    ])
    |> validate_required([:organization_id, :row_id, :video_id])
    |> validate_number(:position, greater_than_or_equal_to: 0, less_than_or_equal_to: 3)
    |> unique_constraint([:row_id, :video_id])
    |> check_constraint(:position, name: :position_range)
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:row_id)
    |> foreign_key_constraint(:video_id)
  end
end
