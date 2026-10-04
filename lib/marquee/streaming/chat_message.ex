defmodule Marquee.Streaming.ChatMessage do
  @moduledoc """
  Schema for live event chat messages.

  Chat messages are posted by viewers during a live event. They support
  soft delete (for moderation) and track who deleted a message. Content
  is limited to 500 characters, enforced at the changeset level.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @max_content_length 500

  schema "chat_messages" do
    field :content, :string
    field :deleted_at, :utc_datetime

    belongs_to :organization, Marquee.Accounts.Organization
    belongs_to :live_event, Marquee.Streaming.LiveEvent
    belongs_to :viewer, Marquee.Viewers.Viewer
    belongs_to :deleted_by_user, Marquee.Accounts.User, foreign_key: :deleted_by_user_id

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for posting a chat message.

  ## Examples

      iex> changeset = changeset(%Marquee.Streaming.ChatMessage{}, %{
      ...>   content: "Hello world!",
      ...>   organization_id: "00000000-0000-0000-0000-000000000001",
      ...>   live_event_id: "00000000-0000-0000-0000-000000000002",
      ...>   viewer_id: "00000000-0000-0000-0000-000000000003"
      ...> })
      iex> changeset.valid?
      true
  """
  def changeset(message, attrs) do
    message
    |> cast(attrs, [:content, :organization_id, :live_event_id, :viewer_id])
    |> validate_required([:content, :organization_id, :live_event_id, :viewer_id])
    |> validate_length(:content, min: 1, max: @max_content_length)
  end

  @doc """
  Changeset for soft-deleting a chat message (moderation).

  ## Examples

      iex> changeset = delete_changeset(%Marquee.Streaming.ChatMessage{}, %{
      ...>   deleted_at: ~U[2026-05-01 19:00:00Z],
      ...>   deleted_by_user_id: "00000000-0000-0000-0000-000000000004"
      ...> })
      iex> changeset.valid?
      true
  """
  def delete_changeset(message, attrs) do
    message
    |> cast(attrs, [:deleted_at, :deleted_by_user_id])
    |> validate_required([:deleted_at])
  end
end
