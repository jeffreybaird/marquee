defmodule Bobine.Storage do
  @moduledoc """
  Image storage context — hands out presigned PUT URLs for direct-to-Spaces
  uploads and builds bucket keys that preserve multi-tenant isolation.

  Usage from a LiveView:

      {:ok, presigned} =
        Bobine.Storage.presign_upload(org, "series_cover",
          content_type: "image/jpeg",
          filename: "pilot.jpg"
        )

      push_event(socket, "spaces_start_upload", presigned)

  Swap implementations via `config :bobine, Bobine.Storage, client: ...`.
  Tests use `Bobine.Storage.MockSpacesClient` (Mox).

  ## Bucket layout

      org/<org_id>/<kind>/<uuid>.<ext>

  The `<kind>` component groups uploads by purpose — `series_cover`,
  `season_cover`, `collection_cover`, `video_thumbnail`, etc. UUIDs
  make keys unguessable and avoid collisions even when two operators
  upload files with the same name.
  """

  require Bobine.Otel

  alias Bobine.Accounts.Organization

  @typedoc "One of the short identifiers that groups uploads by purpose."
  @type kind :: String.t()

  @doc """
  Returns the merged storage config (defaults + runtime overrides).
  Exposed so the real client and helpers can read the current bucket
  and public URL base.
  """
  def config do
    opts = Application.get_env(:bobine, __MODULE__, [])

    %{
      client: Keyword.get(opts, :client, Bobine.Storage.SpacesClient),
      bucket: Keyword.fetch!(opts, :bucket),
      region: Keyword.fetch!(opts, :region),
      host: Keyword.fetch!(opts, :host),
      public_url_base: Keyword.fetch!(opts, :public_url_base)
    }
  end

  @doc """
  Returns the client module used for presigning. Injectable via config
  so tests can swap in a Mox mock without touching callers.
  """
  def client, do: config().client

  @doc """
  Generates a presigned PUT URL for an image upload scoped to an
  organization.

  Options:
    * `:content_type` — e.g. `"image/jpeg"`. Required — the client
      signs this header so the browser must send it on the PUT.
    * `:filename` — original filename (only used to derive an extension
      for the bucket key; never trusted for the key itself).
    * `:expires_in` — seconds, default 900 (15 minutes).

  Returns `{:ok, presigned}` where `presigned` matches the shape in
  `SpacesClientBehaviour.presigned/0`.
  """
  def presign_upload(%Organization{id: org_id}, kind, opts)
      when is_binary(kind) and is_list(opts) do
    Bobine.Otel.with_span "bobine.storage.presign_upload",
                          %{"bobine.org.id" => org_id, "bobine.storage.kind" => kind} do
      content_type = Keyword.get(opts, :content_type, "application/octet-stream")
      filename = Keyword.get(opts, :filename, "upload")

      key = build_key(org_id, kind, filename)

      client().presign_put(
        key: key,
        content_type: content_type,
        expires_in: Keyword.get(opts, :expires_in, 900)
      )
    end
  end

  @doc """
  Builds a deterministic bucket key. Exposed for tests and so callers
  that need to compute a key without presigning can do so.

      iex> key = Bobine.Storage.build_key("abc", "series_cover", "pilot.jpg")
      iex> String.starts_with?(key, "org/abc/series_cover/")
      true
      iex> String.ends_with?(key, ".jpg")
      true
  """
  def build_key(org_id, kind, filename) when is_binary(org_id) do
    uuid = Ecto.UUID.generate()
    ext = filename_extension(filename)
    "org/#{org_id}/#{kind}/#{uuid}#{ext}"
  end

  defp filename_extension(filename) when is_binary(filename) do
    case filename |> Path.extname() |> String.downcase() do
      "" -> ""
      ext -> ext
    end
  end

  defp filename_extension(_), do: ""

  @doc """
  Uploads bytes to the bucket at the given key with the given content type.

  Used for server-side uploads such as CSV exports.
  Returns `:ok` on success or `{:error, reason}` on failure.

  Exempt from doctest — calls external service.
  """
  def put_object(key, body, content_type)
      when is_binary(key) and is_binary(content_type) do
    Bobine.Otel.with_span "bobine.storage.put_object",
                          %{"bobine.storage.key" => key} do
      client().put_object(key, body, content_type)
    end
  end

  @doc """
  Returns object metadata, or `{:error, :not_found}`.

  Exempt from doctest — calls external service.
  """
  def head_object(key) when is_binary(key) do
    Bobine.Otel.with_span "bobine.storage.head_object",
                          %{"bobine.storage.key" => key} do
      client().head_object(key)
    end
  end

  @doc """
  Downloads an object's bytes and content type.

  Exempt from doctest — calls external service.
  """
  def download_object(key) when is_binary(key) do
    Bobine.Otel.with_span "bobine.storage.download_object",
                          %{"bobine.storage.key" => key} do
      client().download_object(key)
    end
  end

  @doc """
  Returns the public URL for a given bucket key.

      iex> url = Bobine.Storage.public_url_for_key("org/abc/exports/audit/file.csv")
      iex> is_binary(url)
      true
  """
  def public_url_for_key(key) when is_binary(key) do
    cfg = config()
    "#{String.trim_trailing(cfg.public_url_base, "/")}/#{key}"
  end

  @doc """
  Returns the list of image content types we accept at the upload
  endpoint. Used both as client-side `accept` and as server-side
  validation so a malicious client can't upload arbitrary binaries.
  """
  def allowed_image_content_types do
    ~w(image/jpeg image/png image/webp image/gif image/avif)
  end

  @doc """
  Returns true if the given content type is an accepted image type.

      iex> Bobine.Storage.allowed_image_content_type?("image/jpeg")
      true

      iex> Bobine.Storage.allowed_image_content_type?("application/pdf")
      false
  """
  def allowed_image_content_type?(content_type) when is_binary(content_type) do
    content_type in allowed_image_content_types()
  end

  def allowed_image_content_type?(_), do: false
end
