defmodule MarqueeWeb.SpacesRuntimeTest do
  @moduledoc """
  Prod `config/runtime.exs` Spaces handling. Deploys write an unset GitHub
  secret/var as `KEY=` (empty string), which must behave exactly like an
  unset variable instead of overriding compiled defaults with "".
  """
  use ExUnit.Case, async: false

  @spaces ~w(SPACES_ACCESS_KEY_ID SPACES_SECRET_ACCESS_KEY SPACES_BUCKET SPACES_REGION SPACES_HOST SPACES_PUBLIC_URL_BASE)

  @prod_env %{
    "DATABASE_URL" => "ecto://user:pass@localhost/marquee_prod",
    "SECRET_KEY_BASE" => String.duplicate("a", 64),
    "PHX_HOST" => "marquee.example.test",
    "OTEL_EXPORTER_OTLP_ENDPOINT" => "https://otel.example.test",
    "OTEL_HUB_TOKEN" => "hub-token"
  }

  @cleared ~w(ADMIN_DEMO_ENABLED ADMIN_DEMO_HOST ADMIN_DEMO_TRUSTED_PROXY_IP ORG_RESOLUTION
              TENANT_HOST_PATTERN TENANT_DOMAIN_PROVISIONING DATABASE_CA_FILE PHX_SERVER PORT
              MUX_TOKEN_ID STRIPE_SECRET_KEY STRIPE_WEBHOOK_SECRET STRIPE_CONNECT_WEBHOOK_SECRET
              RESEND_API_KEY MAILER_FROM POOL_SIZE ECTO_IPV6 DNS_CLUSTER_QUERY)

  setup do
    keys = @spaces ++ @cleared ++ Map.keys(@prod_env)
    original = Map.new(keys, &{&1, System.get_env(&1)})
    Enum.each(@spaces ++ @cleared, &System.delete_env/1)
    System.put_env(@prod_env)

    on_exit(fn ->
      for {key, value} <- original do
        if value, do: System.put_env(key, value), else: System.delete_env(key)
      end
    end)

    :ok
  end

  test "unset Spaces variables leave credentials and storage defaults untouched" do
    config = read_prod_config()

    refute Keyword.has_key?(config[:ex_aws] || [], :access_key_id)
    refute Keyword.has_key?(config[:ex_aws] || [], :secret_access_key)
    refute Keyword.has_key?(config[:marquee], Marquee.Storage)
  end

  test "empty Spaces variables produce the same config as unset ones" do
    unset = read_prod_config()

    Enum.each(@spaces, &System.put_env(&1, ""))
    empty = read_prod_config()

    refute Keyword.has_key?(empty[:ex_aws] || [], :access_key_id)
    refute Keyword.has_key?(empty[:marquee], Marquee.Storage)
    assert empty == unset
  end

  test "non-empty Spaces values are applied" do
    System.put_env(%{
      "SPACES_ACCESS_KEY_ID" => "AKID",
      "SPACES_SECRET_ACCESS_KEY" => "SECRET",
      "SPACES_BUCKET" => "media",
      "SPACES_REGION" => "sfo3",
      "SPACES_HOST" => "sfo3.digitaloceanspaces.com",
      "SPACES_PUBLIC_URL_BASE" => "https://cdn.example.test"
    })

    config = read_prod_config()

    assert config[:ex_aws][:access_key_id] == "AKID"
    assert config[:ex_aws][:secret_access_key] == "SECRET"

    assert storage(config) == %{
             bucket: "media",
             region: "sfo3",
             host: "sfo3.digitaloceanspaces.com",
             public_url_base: "https://cdn.example.test"
           }
  end

  test "a bucket with empty region, host and public URL base uses the defaults" do
    System.put_env(%{
      "SPACES_BUCKET" => "media",
      "SPACES_REGION" => "",
      "SPACES_HOST" => "",
      "SPACES_PUBLIC_URL_BASE" => ""
    })

    assert storage(read_prod_config()) == %{
             bucket: "media",
             region: "nyc3",
             host: "nyc3.digitaloceanspaces.com",
             public_url_base: "https://media.nyc3.digitaloceanspaces.com"
           }
  end

  test "an empty public URL base is derived from the bucket and configured host" do
    System.put_env(%{
      "SPACES_BUCKET" => "media",
      "SPACES_HOST" => "ams3.digitaloceanspaces.com",
      "SPACES_PUBLIC_URL_BASE" => ""
    })

    assert storage(read_prod_config())[:public_url_base] ==
             "https://media.ams3.digitaloceanspaces.com"
  end

  defp storage(config) do
    config[:marquee][Marquee.Storage]
    |> Keyword.take([:bucket, :region, :host, :public_url_base])
    |> Map.new()
  end

  defp read_prod_config, do: Config.Reader.read!("config/runtime.exs", env: :prod)
end
