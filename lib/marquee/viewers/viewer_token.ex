defmodule Marquee.Viewers.ViewerToken do
  @moduledoc """
  Token system for viewer authentication. Completely separate from
  the operator UserToken — uses different salts so tokens can never
  cross-validate.
  """

  use Ecto.Schema
  import Ecto.Query

  alias Marquee.Viewers.ViewerToken

  @hash_algorithm :sha256
  @rand_size 32

  @magic_link_validity_in_minutes 15
  @session_validity_in_days 14

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "viewer_tokens" do
    field :token, :binary
    field :context, :string
    field :sent_to, :string

    belongs_to :viewer, Marquee.Viewers.Viewer

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc """
  Builds a session token for a viewer.

  Session tokens are stored as-is (not hashed) because they live in
  a signed session cookie.

  Exempt from doctest — returns random binary.
  """
  def build_session_token(viewer) do
    token = :crypto.strong_rand_bytes(@rand_size)
    {token, %ViewerToken{token: token, context: "session", viewer_id: viewer.id}}
  end

  @doc """
  Returns a query that verifies a session token and returns the viewer.

  The token is valid if it matches the stored value and has not expired.

  Exempt from doctest — hits the database.
  """
  def verify_session_token_query(token) do
    query =
      from t in by_token_and_context_query(token, "session"),
        join: v in assoc(t, :viewer),
        join: org in assoc(v, :organization),
        where: is_nil(org.demo_kind) and is_nil(org.deleted_at),
        where: t.inserted_at > ago(@session_validity_in_days, "day"),
        where: is_nil(v.deleted_at),
        select: v

    {:ok, query}
  end

  @doc """
  Builds a magic link token for a viewer.

  The raw token is sent via email; only the hash is stored in the DB.

  Exempt from doctest — returns random binary.
  """
  def build_magic_link_token(viewer) do
    build_hashed_token(viewer, "magic_link", viewer.email)
  end

  @doc """
  Verifies a magic link token and returns the viewer_id if valid.

  Exempt from doctest — hits the database.
  """
  def verify_magic_link_token_query(token) do
    case Base.url_decode64(token, padding: false) do
      {:ok, decoded_token} ->
        hashed_token = :crypto.hash(@hash_algorithm, decoded_token)

        query =
          from t in by_token_and_context_query(hashed_token, "magic_link"),
            join: v in assoc(t, :viewer),
            join: org in assoc(v, :organization),
            where: is_nil(org.demo_kind) and is_nil(org.deleted_at),
            where: t.inserted_at > ago(^@magic_link_validity_in_minutes, "minute"),
            where: t.sent_to == v.email,
            where: is_nil(v.deleted_at),
            select: v

        {:ok, query}

      :error ->
        :error
    end
  end

  defp build_hashed_token(viewer, context, sent_to) do
    token = :crypto.strong_rand_bytes(@rand_size)
    hashed_token = :crypto.hash(@hash_algorithm, token)

    {Base.url_encode64(token, padding: false),
     %ViewerToken{
       token: hashed_token,
       context: context,
       sent_to: sent_to,
       viewer_id: viewer.id
     }}
  end

  defp by_token_and_context_query(token, context) do
    from ViewerToken, where: [token: ^token, context: ^context]
  end
end
