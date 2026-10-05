defmodule Marquee.AdminDemo.ProtectedAsset do
  @moduledoc "Permanent ownership registry protecting shared demo media from customer cleanup."
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "admin_demo_protected_assets" do
    field :mux_asset_id, :string
    field :mux_playback_id, :string
    field :template_version, :string
    timestamps(type: :utc_datetime_usec)
  end
end
