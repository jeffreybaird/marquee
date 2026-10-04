defmodule Marquee.Streaming.LiveEventChatBan do
  @moduledoc """
  Schema for banning a viewer from chat in a specific live event.

  A chat ban is event-scoped (not org-wide) and is a hard record — there is
  no soft delete since bans are lifted by deletion. One ban per viewer per event.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "live_event_chat_bans" do
    belongs_to :organization, Marquee.Accounts.Organization
    belongs_to :live_event, Marquee.Streaming.LiveEvent
    belongs_to :viewer, Marquee.Viewers.Viewer
    belongs_to :banned_by_user, Marquee.Accounts.User, foreign_key: :banned_by_user_id

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for banning a viewer from chat.

  ## Examples

      iex> changeset = changeset(%Marquee.Streaming.LiveEventChatBan{}, %{
      ...>   organization_id: "00000000-0000-0000-0000-000000000001",
      ...>   live_event_id: "00000000-0000-0000-0000-000000000002",
      ...>   viewer_id: "00000000-0000-0000-0000-000000000003",
      ...>   banned_by_user_id: "00000000-0000-0000-0000-000000000004"
      ...> })
      iex> changeset.valid?
      true
  """
  def changeset(ban, attrs) do
    ban
    |> cast(attrs, [:organization_id, :live_event_id, :viewer_id, :banned_by_user_id])
    |> validate_required([:organization_id, :live_event_id, :viewer_id, :banned_by_user_id])
    |> unique_constraint([:live_event_id, :viewer_id],
      name: :live_event_chat_bans_live_event_id_viewer_id_index
    )
  end
end
