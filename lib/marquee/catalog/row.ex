defmodule Marquee.Catalog.Row do
  use Ecto.Schema
  import Ecto.Changeset

  alias Marquee.Catalog.Presets

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "rows" do
    belongs_to :organization, Marquee.Accounts.Organization
    field :title, :string

    field :source_type, Ecto.Enum,
      values: [
        # Legacy / concrete source types
        :curated,
        :collection,
        :tag,
        :recent,
        :continue_watching,
        :popular,
        :hero,
        :new_seasons,
        # Preset row types (aligned with Marquee.Catalog.Presets.row_types/0)
        :popularity,
        :tags,
        :preferences,
        :series,
        :creator_showcase,
        :editorial_spotlight,
        # Static text block rendered inline in the catalog. No items; content
        # lives in `filter_config` keys: eyebrow, headline, body, cta_label,
        # cta_href.
        :welcome_text,
        # Upcoming live events — resolved from Streaming context
        :upcoming_live_events
      ]

    field :source_id, :binary_id
    field :card_variant, :string
    field :filter_config, :map
    field :position, :integer, default: 0
    field :visible, :boolean, default: false
    field :max_items, :integer, default: 20
    # Hide the details bar (title + metadata) beneath each card image.
    field :show_details, :boolean, default: true
    # When :show_details is false, render the card's title overlaid on the
    # thumbnail instead. Ignored when :show_details is true.
    field :title_overlay, :boolean, default: false
    field :deleted_at, :utc_datetime

    has_many :row_items, Marquee.Catalog.RowItem
    has_many :hero_slides, Marquee.Catalog.HeroSlide

    timestamps(type: :utc_datetime)
  end

  @doc """
  Maps a `Row.source_type` to the preset row type used for card-variant
  compatibility lookups. Legacy source types collapse onto the closest
  preset row type; new source types pass through unchanged.

      iex> Marquee.Catalog.Row.compat_row_type(:popular)
      :popularity

      iex> Marquee.Catalog.Row.compat_row_type(:editorial_spotlight)
      :editorial_spotlight

      iex> Marquee.Catalog.Row.compat_row_type(:curated)
      :popularity
  """
  def compat_row_type(:popular), do: :popularity
  def compat_row_type(:recent), do: :popularity
  def compat_row_type(:curated), do: :popularity
  def compat_row_type(:collection), do: :editorial_spotlight
  def compat_row_type(:tag), do: :tags
  def compat_row_type(:new_seasons), do: :series
  def compat_row_type(:upcoming_live_events), do: :popularity
  def compat_row_type(other) when is_atom(other), do: other

  @doc false
  def changeset(row, attrs) do
    row
    |> cast(attrs, [
      :title,
      :source_type,
      :source_id,
      :card_variant,
      :filter_config,
      :position,
      :visible,
      :max_items,
      :show_details,
      :title_overlay,
      :organization_id
    ])
    |> validate_required([:title, :source_type, :organization_id])
    |> validate_number(:max_items, greater_than_or_equal_to: 5, less_than_or_equal_to: 50)
    |> validate_source_id()
    |> validate_card_variant()
  end

  defp validate_source_id(changeset) do
    source_type = get_field(changeset, :source_type)

    if source_type in [:collection, :tag] do
      validate_required(changeset, [:source_id])
    else
      changeset
    end
  end

  defp validate_card_variant(changeset) do
    variant = get_field(changeset, :card_variant)
    source_type = get_field(changeset, :source_type)

    cond do
      source_type == :welcome_text ->
        changeset

      is_nil(variant) or variant == "" ->
        changeset

      variant not in card_variant_strings() ->
        add_error(changeset, :card_variant, "is not a recognized card variant")

      is_nil(source_type) ->
        changeset

      not Presets.compatible?(
        String.to_existing_atom(variant),
        compat_row_type(source_type)
      ) ->
        add_error(
          changeset,
          :card_variant,
          "is not compatible with row type #{source_type}"
        )

      true ->
        changeset
    end
  end

  defp card_variant_strings do
    Enum.map(Presets.card_variants(), &Atom.to_string/1)
  end
end
