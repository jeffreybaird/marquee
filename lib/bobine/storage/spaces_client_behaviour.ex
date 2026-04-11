defmodule Bobine.Storage.SpacesClientBehaviour do
  @moduledoc """
  Contract for the DigitalOcean Spaces client.

  The real implementation is `Bobine.Storage.SpacesClient`; tests
  inject `Bobine.Storage.MockSpacesClient` (defined via Mox) via
  `config :bobine, Bobine.Storage, client: ...`.

  The client's only job is to produce presigned PUT URLs — it never
  touches file bytes. The browser uploads directly to Spaces using the
  URL we hand it, which keeps Phoenix out of the upload hot path.
  """

  @type presign_opts :: [
          key: String.t(),
          content_type: String.t(),
          expires_in: pos_integer(),
          max_size: pos_integer()
        ]

  @type presigned :: %{
          required(:presigned_url) => String.t(),
          required(:public_url) => String.t(),
          required(:key) => String.t(),
          required(:expires_at) => DateTime.t(),
          optional(:headers) => %{String.t() => String.t()}
        }

  @callback presign_put(presign_opts()) ::
              {:ok, presigned()} | {:error, atom() | binary()}

  @callback put_object(key :: String.t(), body :: iodata(), content_type :: String.t()) ::
              :ok | {:error, atom() | binary()}
end
