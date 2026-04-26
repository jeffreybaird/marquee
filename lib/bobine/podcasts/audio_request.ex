defmodule Bobine.Podcasts.AudioRequest do
  @moduledoc """
  Append-only delivery record. Written by the audio proxy and feed handlers.
  Drives the operator-facing analytics for podcasts.

  Recorded request_type values:

    * `"feed"` — a request to the RSS feed XML endpoint
    * `"audio_redirect"` — a request that redirected to a Mux MP3 URL
    * `"audio_proxy"` — a request that the proxy fulfilled (remote audio)
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Bobine.Podcasts.{Episode, FeedToken, Show}
  alias Bobine.Viewers.Viewer

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @request_types ~w(feed audio_redirect audio_proxy)

  schema "podcast_audio_requests" do
    field :request_type, :string
    field :user_agent, :string
    field :occurred_at, :utc_datetime

    belongs_to :organization, Bobine.Accounts.Organization
    belongs_to :show, Show
    belongs_to :episode, Episode
    belongs_to :viewer, Viewer
    belongs_to :feed_token, FeedToken
  end

  @doc false
  def changeset(record, attrs) do
    record
    |> cast(attrs, [
      :organization_id,
      :show_id,
      :episode_id,
      :viewer_id,
      :feed_token_id,
      :request_type,
      :user_agent,
      :occurred_at
    ])
    |> validate_required([:organization_id, :show_id, :episode_id, :request_type, :occurred_at])
    |> validate_inclusion(:request_type, @request_types)
  end

  @doc "Allowed request_type values."
  def request_types, do: @request_types
end
