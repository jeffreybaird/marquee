defmodule Marquee.Podcasts.FeedToken do
  @moduledoc """
  Random opaque token bound to one (subscriber, show) pair.

  The token is what the subscriber's podcast app sees in the feed URL and
  every audio URL referenced from that feed. Tokens are unguessable
  (32 random bytes, URL-safe base64) and revocable. They are never
  hard-deleted — revoked tokens linger as an audit trail.

  Tokens may carry an `expires_at` for defense-in-depth (a year is the
  default) but the authoritative access check happens at request time and
  short-circuits regardless of token age.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Marquee.Podcasts.Show
  alias Marquee.Viewers.Viewer

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(active revoked)
  @default_expiry_days 365

  schema "podcast_feed_tokens" do
    field :token, :string
    field :status, :string, default: "active"
    field :expires_at, :utc_datetime
    field :revoked_at, :utc_datetime
    field :revoked_reason, :string
    field :last_used_at, :utc_datetime
    field :request_count, :integer, default: 0

    belongs_to :organization, Marquee.Accounts.Organization
    belongs_to :show, Show
    belongs_to :viewer, Viewer

    timestamps(type: :utc_datetime)
  end

  @doc """
  Generates a fresh token bound to the given show + viewer pair.

      iex> changeset = Marquee.Podcasts.FeedToken.new_changeset(
      ...>   %{organization_id: "org", show_id: "show", viewer_id: "v"})
      iex> changeset.valid?
      true
      iex> byte_size(Ecto.Changeset.get_change(changeset, :token)) > 16
      true
  """
  def new_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:organization_id, :show_id, :viewer_id])
    |> validate_required([:organization_id, :show_id, :viewer_id])
    |> put_change(:token, generate_token())
    |> put_change(:status, "active")
    |> put_change(:expires_at, default_expiry())
    |> unique_constraint([:show_id, :viewer_id],
      name: :podcast_feed_tokens_active_show_viewer_index,
      message: "subscriber already has an active token for this show"
    )
    |> unique_constraint(:token)
  end

  @doc false
  def revoke_changeset(token, reason) when is_binary(reason) do
    token
    |> change(
      status: "revoked",
      revoked_at: DateTime.utc_now() |> DateTime.truncate(:second),
      revoked_reason: reason
    )
  end

  @doc false
  def usage_changeset(token, occurred_at \\ nil) do
    occurred_at = occurred_at || DateTime.utc_now() |> DateTime.truncate(:second)

    token
    |> change(
      last_used_at: occurred_at,
      request_count: (token.request_count || 0) + 1
    )
  end

  @doc """
  Returns true if the token is currently usable (active and not expired).

      iex> alias Marquee.Podcasts.FeedToken
      iex> FeedToken.usable?(%FeedToken{status: "active", expires_at: ~U[2099-01-01 00:00:00Z]})
      true

      iex> alias Marquee.Podcasts.FeedToken
      iex> FeedToken.usable?(%FeedToken{status: "revoked", expires_at: ~U[2099-01-01 00:00:00Z]})
      false

      iex> alias Marquee.Podcasts.FeedToken
      iex> FeedToken.usable?(%FeedToken{status: "active", expires_at: ~U[2000-01-01 00:00:00Z]})
      false

      iex> alias Marquee.Podcasts.FeedToken
      iex> FeedToken.usable?(%FeedToken{status: "active", expires_at: nil})
      true
  """
  def usable?(%__MODULE__{status: "active", expires_at: nil}), do: true

  def usable?(%__MODULE__{status: "active", expires_at: %DateTime{} = expires_at}) do
    DateTime.compare(DateTime.utc_now(), expires_at) == :lt
  end

  def usable?(_), do: false

  @doc "Allowed status values."
  def statuses, do: @statuses

  defp generate_token do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end

  defp default_expiry do
    DateTime.utc_now()
    |> DateTime.add(@default_expiry_days * 86_400, :second)
    |> DateTime.truncate(:second)
  end
end
