defmodule Bobine.Storage.SpacesClient do
  @moduledoc """
  Real DigitalOcean Spaces client backed by `ex_aws_s3`.

  Generates presigned PUT URLs so the browser can upload directly to
  the bucket. Spaces is S3-compatible, so the same SigV4 code path
  works unchanged — we just point `ex_aws` at the `nyc3.digitaloceanspaces.com`
  endpoint in `config.exs`.

  Requires:
    * `config :ex_aws, access_key_id: ..., secret_access_key: ...` set
      at runtime (see `config/runtime.exs`).
    * A bucket configured to accept `PUT` from browser origins via CORS.
      See `.claude/digital-ocean-spaces.md` for the exact JSON.
  """

  @behaviour Bobine.Storage.SpacesClientBehaviour

  @default_expires_in 900

  @impl true
  def presign_put(opts) do
    cfg = Bobine.Storage.config()
    key = Keyword.fetch!(opts, :key)
    content_type = Keyword.get(opts, :content_type, "application/octet-stream")
    expires_in = Keyword.get(opts, :expires_in, @default_expires_in)

    aws_config = build_aws_config(cfg)

    query_params = [
      {"Content-Type", content_type}
    ]

    case ExAws.S3.presigned_url(aws_config, :put, cfg.bucket, key,
           expires_in: expires_in,
           query_params: query_params
         ) do
      {:ok, presigned_url} ->
        {:ok,
         %{
           presigned_url: presigned_url,
           public_url: public_url(cfg, key),
           key: key,
           expires_at: DateTime.add(DateTime.utc_now(), expires_in, :second),
           headers: %{"Content-Type" => content_type}
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def put_object(key, body, content_type) do
    cfg = Bobine.Storage.config()
    opts = [content_type: content_type]

    case ExAws.S3.put_object(cfg.bucket, key, body, opts)
         |> ExAws.request(region: cfg.region, host: cfg.host, scheme: "https://") do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_aws_config(cfg) do
    ExAws.Config.new(:s3, region: cfg.region, host: cfg.host, scheme: "https://")
  end

  defp public_url(%{public_url_base: base}, key) when is_binary(base) do
    "#{String.trim_trailing(base, "/")}/#{key}"
  end
end
