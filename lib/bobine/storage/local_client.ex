defmodule Bobine.Storage.LocalClient do
  @moduledoc """
  Development-only storage client. Replaces `Bobine.Storage.SpacesClient`
  so image uploads stay on the local machine instead of hitting
  DigitalOcean Spaces.

  * Presigned PUT URLs point at `/dev/uploads/<key>`, served by
    `BobineWeb.Plugs.DevUploadReceiver` (mounted in the endpoint above
    `Plug.Parsers` so binary bodies aren't pre-read).
  * Public URLs are relative (`/uploads/<key>`) so images work across
    tenant subdomains (e.g. `prism-plus.localhost:4000`).
  * Files land under `priv/static/uploads/` and are served via
    `Plug.Static`.

  Wire up in `config/dev.exs`:

      config :bobine, Bobine.Storage,
        client: Bobine.Storage.LocalClient,
        public_url_base: "/uploads",
        local_upload_dir: Path.expand("../priv/static/uploads", __DIR__)

  Image URLs written to the database while this client is active are
  dev-only — do not copy a dev database to staging or production.
  """

  @behaviour Bobine.Storage.SpacesClientBehaviour

  @default_expires_in 3_600

  @doc """
  Builds a dev presigned PUT response that points at the local upload
  endpoint. Never fails — there is no remote signing to talk to.

  ## Examples

      iex> {:ok, presigned} =
      ...>   Bobine.Storage.LocalClient.presign_put(
      ...>     key: "org/abc/series_cover/x.jpg",
      ...>     content_type: "image/jpeg"
      ...>   )
      iex> presigned.presigned_url
      "/dev/uploads/org/abc/series_cover/x.jpg"
      iex> presigned.public_url
      "/uploads/org/abc/series_cover/x.jpg"
      iex> presigned.key
      "org/abc/series_cover/x.jpg"
      iex> presigned.headers["Content-Type"]
      "image/jpeg"

  """
  @impl true
  def presign_put(opts) do
    key = Keyword.fetch!(opts, :key)
    content_type = Keyword.get(opts, :content_type, "application/octet-stream")
    expires_in = Keyword.get(opts, :expires_in, @default_expires_in)

    {:ok,
     %{
       presigned_url: "/dev/uploads/#{key}",
       public_url: "/uploads/#{key}",
       key: key,
       expires_at: DateTime.add(DateTime.utc_now(), expires_in, :second),
       headers: %{"Content-Type" => content_type}
     }}
  end

  @doc """
  Writes bytes to the local uploads directory, creating any missing
  parent directories. Used for server-side writes (e.g. CSV exports)
  that normally target Spaces.

  Exempt from doctest — touches the filesystem.
  """
  @impl true
  def put_object(key, body, _content_type) when is_binary(key) do
    full_path = Path.join(upload_dir(), key)
    File.mkdir_p!(Path.dirname(full_path))
    File.write!(full_path, body)
    :ok
  end

  @doc """
  Returns the configured directory where uploaded files are stored.
  Defaults to `priv/static/uploads` under the app's priv dir when no
  explicit `:local_upload_dir` is set in config.

  ## Examples

      iex> dir = Bobine.Storage.LocalClient.upload_dir()
      iex> is_binary(dir)
      true

  """
  def upload_dir do
    case Application.get_env(:bobine, Bobine.Storage, [])
         |> Keyword.get(:local_upload_dir) do
      nil -> Path.join(:code.priv_dir(:bobine), "static/uploads")
      dir when is_binary(dir) -> dir
    end
  end

  @doc """
  Returns metadata for a previously written object, or `{:error, :not_found}`
  when no file exists at the key. Content type is recovered from the
  filename extension since the local client does not persist it.

  Exempt from doctest — touches the filesystem.
  """
  @impl true
  def head_object(key) when is_binary(key) do
    full_path = Path.join(upload_dir(), key)

    case File.stat(full_path) do
      {:ok, %File.Stat{size: size}} ->
        {:ok, %{content_type: content_type_from_key(key), size: size}}

      {:error, :enoent} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Reads the bytes back from the local uploads directory.

  Exempt from doctest — touches the filesystem.
  """
  @impl true
  def download_object(key) when is_binary(key) do
    full_path = Path.join(upload_dir(), key)

    case File.read(full_path) do
      {:ok, body} -> {:ok, %{body: body, content_type: content_type_from_key(key)}}
      {:error, :enoent} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp content_type_from_key(key) do
    case key |> Path.extname() |> String.downcase() do
      ".mp3" -> "audio/mpeg"
      ".m4a" -> "audio/x-m4a"
      ".aac" -> "audio/aac"
      ".ogg" -> "audio/ogg"
      ".wav" -> "audio/wav"
      _ -> nil
    end
  end
end
