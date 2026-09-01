defmodule Marquee.Catalog.Layout do
  @moduledoc """
  Per-tenant homepage layout metadata. Holds the selected preset name
  and the default card variant used on browse pages.

  Row ordering + per-row card variant live on `Marquee.Catalog.Row` —
  operators edit those on `/admin/catalog`. Layout exists so we can
  remember which preset the tenant is on and drive browse-page defaults
  without inspecting every row.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Marquee.Catalog.Presets

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "layouts" do
    field :preset_name, :string
    field :default_browse_card_variant, :string

    belongs_to :organization, Marquee.Accounts.Organization

    timestamps(type: :utc_datetime)
  end

  @castable ~w(preset_name default_browse_card_variant organization_id)a

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
    |> unique_constraint(:organization_id)
  end
end
