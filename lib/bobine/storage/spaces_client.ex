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

  require Logger

  @default_expires_in 900

  @impl true
  def presign_put(opts) do
    cfg = Bobine.Storage.config()
    key = Keyword.fetch!(opts, :key)
    content_type = Keyword.get(opts, :content_type, "application/octet-stream")
    expires_in = Keyword.get(opts, :expires_in, @default_expires_in)

    with {:ok, aws_config} <- build_aws_config(cfg) do
      signed_headers = [
        {"Content-Type", content_type},
        {"x-amz-acl", "public-read"}
      ]

      case ExAws.S3.presigned_url(aws_config, :put, cfg.bucket, key,
             expires_in: expires_in,
             headers: signed_headers,
             virtual_host: true
           ) do
        {:ok, presigned_url} ->
          {:ok,
           %{
             presigned_url: presigned_url,
             public_url: public_url(cfg, key),
             key: key,
             expires_at: DateTime.add(DateTime.utc_now(), expires_in, :second),
             headers: %{
               "Content-Type" => content_type,
               "x-amz-acl" => "public-read"
             }
           }}

        {:error, reason} ->
          {:error, reason}
      end
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

  @impl true
  def head_object(key) when is_binary(key) do
    cfg = Bobine.Storage.config()

    case ExAws.S3.head_object(cfg.bucket, key)
         |> ExAws.request(region: cfg.region, host: cfg.host, scheme: "https://") do
      {:ok, %{headers: headers}} ->
        {:ok,
         %{
           content_type: header(headers, "content-type"),
           size: header(headers, "content-length") |> parse_int()
         }}

      {:error, {:http_error, 404, _}} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def download_object(key) when is_binary(key) do
    cfg = Bobine.Storage.config()

    case ExAws.S3.get_object(cfg.bucket, key)
         |> ExAws.request(region: cfg.region, host: cfg.host, scheme: "https://") do
      {:ok, %{body: body, headers: headers}} ->
        {:ok, %{body: body, content_type: header(headers, "content-type")}}

      {:error, {:http_error, 404, _}} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp header(headers, name) when is_list(headers) do
    target = String.downcase(name)

    Enum.find_value(headers, fn {k, v} ->
      if String.downcase(to_string(k)) == target, do: v
    end)
  end

  defp header(_, _), do: nil

  defp parse_int(nil), do: nil

  defp parse_int(v) when is_binary(v) do
    case Integer.parse(v) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp parse_int(v) when is_integer(v), do: v
  defp parse_int(_), do: nil

  defp build_aws_config(cfg) do
    # Resolve Spaces credentials explicitly so a misconfigured env produces a
    # clear error up front, instead of the ex_aws default chain silently
    # falling through to EC2 instance metadata and timing out with a cryptic
    # "Instance Meta Error" on localhost. Runtime config in `runtime.exs`
    # writes these keys from `SPACES_ACCESS_KEY_ID` / `SPACES_SECRET_ACCESS_KEY`.
    case {
      Application.get_env(:ex_aws, :access_key_id),
      Application.get_env(:ex_aws, :secret_access_key)
    } do
      {key, secret} when is_binary(key) and key != "" and is_binary(secret) and secret != "" ->
        {:ok,
         ExAws.Config.new(:s3,
           region: cfg.region,
           host: cfg.host,
           scheme: "https://",
           access_key_id: key,
           secret_access_key: secret
         )}

      _ ->
        Logger.error(
          "Spaces credentials not configured. Set SPACES_ACCESS_KEY_ID and " <>
            "SPACES_SECRET_ACCESS_KEY in the environment (.env in dev, Fly " <>
            "secrets in prod) and restart the server so runtime.exs re-reads them."
        )

        {:error, :spaces_credentials_not_configured}
    end
  end

  defp public_url(%{public_url_base: base}, key) when is_binary(base) do
    "#{String.trim_trailing(base, "/")}/#{key}"
  end
end
