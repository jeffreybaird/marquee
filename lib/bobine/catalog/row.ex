defmodule Bobine.Catalog.Row do
  use Ecto.Schema
  import Ecto.Changeset

  alias Bobine.Catalog.Presets

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "rows" do
    belongs_to :organization, Bobine.Accounts.Organization
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
        # Preset row types (aligned with Bobine.Catalog.Presets.row_types/0)
        :popularity,
        :tags,
        :preferences,
        :series,
        :creator_showcase,
        :editorial_spotlight,
        # Static text block rendered inline in the catalog. No items; content
        # lives in `filter_config` keys: eyebrow, headline, body, cta_label,
        # cta_href.
        :welcome_text
      ]

    field :source_id, :binary_id
    field :card_variant, :string
    field :filter_config, :map
    field :position, :integer, default: 0
    field :visible, :boolean, default: false
    field :max_items, :integer, default: 20
    field :deleted_at, :utc_datetime

    has_many :row_items, Bobine.Catalog.RowItem
    has_many :hero_slides, Bobine.Catalog.HeroSlide

    timestamps(type: :utc_datetime)
  end

  @doc """
  Maps a `Row.source_type` to the preset row type used for card-variant
  compatibility lookups. Legacy source types collapse onto the closest
  preset row type; new source types pass through unchanged.

      iex> Bobine.Catalog.Row.compat_row_type(:popular)
      :popularity

      iex> Bobine.Catalog.Row.compat_row_type(:editorial_spotlight)
      :editorial_spotlight

      iex> Bobine.Catalog.Row.compat_row_type(:curated)
      :popularity
  """
  def compat_row_type(:popular), do: :popularity
  def compat_row_type(:recent), do: :popularity
  def compat_row_type(:curated), do: :popularity
  def compat_row_type(:collection), do: :editorial_spotlight
  def compat_row_type(:tag), do: :tags
  def compat_row_type(:new_seasons), do: :series
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
