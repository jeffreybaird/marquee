defmodule Bobine.Catalog.Layout do
  @moduledoc """
  Per-tenant homepage layout configuration. Stores the selected preset,
  ordered row list (each row carries a row type + card variant + position),
  and the default card variant used on browse pages.

  Distinct from `Bobine.Catalog.Row`, which holds the data-bound row
  records (title, source type, source id). Layout is the operator-facing
  shape of the homepage; Row is the realized content source.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Bobine.Catalog.Presets

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "layouts" do
    field :preset_name, :string
    field :default_browse_card_variant, :string
    field :rows, {:array, :map}, default: []

    belongs_to :organization, Bobine.Accounts.Organization

    timestamps(type: :utc_datetime)
  end

  @castable ~w(preset_name default_browse_card_variant rows organization_id)a

  @doc false
  def changeset(layout, attrs) do
    layout
    |> cast(attrs, @castable)
    |> validate_required([:preset_name, :default_browse_card_variant, :organization_id])
    |> validate_inclusion(:preset_name, Presets.names())
    |> validate_inclusion(
      :default_browse_card_variant,
      Enum.map(Presets.card_variants(), &Atom.to_string/1)
    )
    |> normalize_rows()
    |> validate_row_count()
    |> validate_continue_watching_present()
    |> validate_row_compatibility()
    |> unique_constraint(:organization_id)
  end

  # Ensure row entries stored as string-keyed maps with canonical shape
  # before validation runs.
  defp normalize_rows(changeset) do
    case get_change(changeset, :rows) || get_field(changeset, :rows) do
      nil ->
        changeset

      rows when is_list(rows) ->
        normalized = rows |> Enum.with_index() |> Enum.map(&normalize_row/1)
        put_change(changeset, :rows, normalized)

      _ ->
        add_error(changeset, :rows, "must be a list")
    end
  end

  defp normalize_row({row, idx}) when is_map(row) do
    %{
      "row_type" => row |> fetch(:row_type) |> to_string(),
      "card_variant" => row |> fetch(:card_variant) |> to_string(),
      "position" => row |> fetch(:position) |> as_integer(idx),
      "visible" => fetch(row, :visible, true)
    }
  end

  defp fetch(map, key, default \\ nil) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end

  defp as_integer(nil, default), do: default
  defp as_integer(n, _) when is_integer(n), do: n

  defp as_integer(s, default) when is_binary(s) do
    case Integer.parse(s) do
      {n, _} -> n
      :error -> default
    end
  end

  defp as_integer(_, default), do: default

  defp validate_row_count(changeset) do
    rows = get_field(changeset, :rows) || []

    if length(rows) < 2 do
      add_error(changeset, :rows, "must contain at least 2 rows")
    else
      changeset
    end
  end

  defp validate_continue_watching_present(changeset) do
    rows = get_field(changeset, :rows) || []

    if Enum.any?(rows, &(&1["row_type"] == "continue_watching")) do
      changeset
    else
      add_error(
        changeset,
        :rows,
        "continue_watching row cannot be removed — only hidden"
      )
    end
  end

  defp validate_row_compatibility(changeset) do
    rows = get_field(changeset, :rows) || []

    Enum.reduce(rows, changeset, fn row, acc ->
      row_type = safe_atom(row["row_type"], Presets.row_types())
      variant = safe_atom(row["card_variant"], Presets.card_variants())

      cond do
        is_nil(row_type) ->
          add_error(acc, :rows, "unknown row type: #{inspect(row["row_type"])}")

        is_nil(variant) ->
          add_error(acc, :rows, "unknown card variant: #{inspect(row["card_variant"])}")

        not Presets.compatible?(variant, row_type) ->
          add_error(
            acc,
            :rows,
            "#{variant} is not a compatible card variant for row #{row_type}"
          )

        true ->
          acc
      end
    end)
  end

  defp safe_atom(value, allowed) when is_binary(value) do
    Enum.find(allowed, &(Atom.to_string(&1) == value))
  end

  defp safe_atom(_, _), do: nil
end
