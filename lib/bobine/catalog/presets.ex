defmodule Bobine.Catalog.Presets do
  @moduledoc """
  Named preset definitions for the three tenant archetypes described in
  `.claude/brand-system.md`: Catalog Cinema, Learning Platform, Creator
  Channel. Each preset supplies accent color variants, a display font,
  and an ordered homepage row configuration.

  Also owns the card/row compatibility matrix used to guard operator
  configuration at the data layer.
  """

  @type row_type ::
          :hero
          | :popularity
          | :tags
          | :preferences
          | :series
          | :continue_watching
          | :creator_showcase
          | :editorial_spotlight

  @type card_variant ::
          :poster_portrait
          | :landscape_episode
          | :creator_identity
          | :collection_editorial
          | :progress_course
          | :minimal_list_item

  @row_types ~w(hero popularity tags preferences series continue_watching creator_showcase editorial_spotlight)a

  @card_variants ~w(poster_portrait landscape_episode creator_identity collection_editorial progress_course minimal_list_item)a

  # Compatibility matrix — all card variants allowed in all row types.
  @compatibility Map.new(@card_variants, fn variant -> {variant, @row_types} end)

  @presets %{
    "catalog_cinema" => %{
      name: "catalog_cinema",
      display_name: "Catalog Cinema",
      description: "Films and TV. Poster-first browsing, ambient discovery.",
      accent_color_base: "oklch(0.72 0.14 68)",
      accent_color_hover: "oklch(0.78 0.14 68)",
      accent_color_active: "oklch(0.66 0.14 68)",
      accent_color_subtle: "oklch(0.28 0.06 68)",
      display_font: "Cormorant Garamond",
      default_browse_card_variant: :poster_portrait,
      rows: [
        %{row_type: :hero, card_variant: :collection_editorial, position: 0},
        %{row_type: :continue_watching, card_variant: :landscape_episode, position: 1},
        %{row_type: :popularity, card_variant: :poster_portrait, position: 2},
        %{row_type: :editorial_spotlight, card_variant: :collection_editorial, position: 3},
        %{row_type: :tags, card_variant: :poster_portrait, position: 4},
        %{row_type: :preferences, card_variant: :poster_portrait, position: 5}
      ]
    },
    "learning_platform" => %{
      name: "learning_platform",
      display_name: "Learning Platform",
      description: "Structured courses. Completion progress is the primary signal.",
      accent_color_base: "oklch(0.62 0.18 250)",
      accent_color_hover: "oklch(0.68 0.18 250)",
      accent_color_active: "oklch(0.56 0.18 250)",
      accent_color_subtle: "oklch(0.26 0.08 250)",
      display_font: "DM Serif Display",
      default_browse_card_variant: :progress_course,
      rows: [
        %{row_type: :hero, card_variant: :collection_editorial, position: 0},
        %{row_type: :continue_watching, card_variant: :progress_course, position: 1},
        %{row_type: :series, card_variant: :progress_course, position: 2},
        %{row_type: :popularity, card_variant: :poster_portrait, position: 3},
        %{row_type: :tags, card_variant: :landscape_episode, position: 4}
      ]
    },
    "creator_channel" => %{
      name: "creator_channel",
      display_name: "Creator Channel",
      description: "Individual creator content. Creator identity is the primary unit.",
      accent_color_base: "oklch(0.68 0.20 320)",
      accent_color_hover: "oklch(0.74 0.20 320)",
      accent_color_active: "oklch(0.62 0.20 320)",
      accent_color_subtle: "oklch(0.28 0.08 320)",
      display_font: "Playfair Display",
      default_browse_card_variant: :landscape_episode,
      rows: [
        %{row_type: :hero, card_variant: :collection_editorial, position: 0},
        %{row_type: :creator_showcase, card_variant: :creator_identity, position: 1},
        %{row_type: :continue_watching, card_variant: :landscape_episode, position: 2},
        %{row_type: :series, card_variant: :landscape_episode, position: 3},
        %{row_type: :popularity, card_variant: :poster_portrait, position: 4}
      ]
    }
  }

  @doc """
  Returns all known preset names.

      iex> Bobine.Catalog.Presets.names()
      ["catalog_cinema", "creator_channel", "learning_platform"]
  """
  def names, do: @presets |> Map.keys() |> Enum.sort()

  @doc """
  Lists all preset definitions.
  """
  def list, do: @presets |> Map.values() |> Enum.sort_by(& &1.name)

  @doc """
  Fetches a preset definition by name.

      iex> {:ok, p} = Bobine.Catalog.Presets.get("catalog_cinema")
      iex> p.display_name
      "Catalog Cinema"

      iex> Bobine.Catalog.Presets.get("unknown")
      {:error, :not_found}
  """
  def get(name) when is_binary(name) do
    case Map.fetch(@presets, name) do
      {:ok, preset} -> {:ok, preset}
      :error -> {:error, :not_found}
    end
  end

  def get(_), do: {:error, :not_found}

  @doc """
  Returns true when the given card variant may be placed in the given
  row type per the compatibility matrix.

      iex> Bobine.Catalog.Presets.compatible?(:poster_portrait, :hero)
      true

      iex> Bobine.Catalog.Presets.compatible?(:progress_course, :hero)
      true
  """
  def compatible?(card_variant, row_type)
      when card_variant in @card_variants and row_type in @row_types do
    row_type in Map.fetch!(@compatibility, card_variant)
  end

  def compatible?(_card_variant, _row_type), do: false

  @doc """
  Returns the list of card variants that can occupy the given row type.

      iex> :collection_editorial in Bobine.Catalog.Presets.variants_for_row(:hero)
      true
  """
  def variants_for_row(row_type) when row_type in @row_types do
    @card_variants
    |> Enum.filter(&compatible?(&1, row_type))
  end

  def variants_for_row(_), do: []

  @doc "All known row types."
  def row_types, do: @row_types

  @doc "All known card variants."
  def card_variants, do: @card_variants
end
