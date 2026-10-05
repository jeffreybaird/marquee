defmodule Marquee.TenantDomains.DNSimpleClient do
  @moduledoc "Reconciles exact DNSimple record names without overwriting or deleting existing DNS."
  @behaviour Marquee.TenantDomains.DNSClientBehaviour
  require Marquee.Otel
  alias Marquee.Metrics

  @doc "Ensures one exact matching A record after inspecting every result page. Performs external DNSimple requests."
  @impl true
  def ensure_record(hostname, target, key) do
    Marquee.Otel.with_span "marquee.dnsimple.ensure_record" do
      with {:ok, request, name} <- build_request(hostname),
           {:ok, records} <- list_records(request, name, 1, []),
           :absent <- classify_records(records, name, target) do
        create_record(request, name, target, key)
      end
    end
  end

  defp build_request(hostname) do
    cfg = Application.get_env(:marquee, :tenant_domain_provisioning, [])

    with zone when is_binary(zone) <- cfg[:zone],
         account when not is_nil(account) <- cfg[:account_id],
         token when is_binary(token) and token != "" <- cfg[:api_token],
         pattern when is_binary(pattern) <- cfg[:host_pattern],
         slug when is_binary(slug) <- MarqueeWeb.OrgURL.tenant_slug(hostname, pattern),
         true <- String.ends_with?(hostname, "." <> zone) do
      name = String.trim_trailing(hostname, "." <> zone)
      opts = Application.get_env(:marquee, :tenant_dns_req_options, [])

      request =
        Req.new(
          Keyword.merge(opts,
            url:
              "https://api.dnsimple.com/v2/#{URI.encode(to_string(account))}/zones/#{URI.encode(zone)}/records",
            auth: {:bearer, token},
            retry: false,
            redirect: false,
            receive_timeout: 10_000,
            connect_options: [timeout: 5_000]
          )
        )

      {:ok, request, name}
    else
      _ -> {:error, :configuration}
    end
  end

  defp list_records(_request, _name, page, _acc) when page > 1000, do: {:error, :dns_unavailable}

  defp list_records(request, name, page, acc) do
    case perform_request(request, method: :get, params: [name: name, page: page, per_page: 100]) do
      {:ok, %{status: 200, body: %{"data" => data, "pagination" => pagination}}}
      when is_list(data) ->
        continue_listing(request, name, page, acc ++ data, pagination)

      {:ok, %{status: status}} when status in [401, 403] ->
        {:error, :configuration}

      _ ->
        {:error, :dns_unavailable}
    end
  end

  defp continue_listing(request, name, page, records, %{
         "current_page" => page,
         "total_pages" => total
       })
       when is_integer(total) and total >= page do
    if page < total, do: list_records(request, name, page + 1, records), else: {:ok, records}
  end

  defp continue_listing(_request, _name, _page, _records, _pagination),
    do: {:error, :dns_unavailable}

  defp classify_records(records, name, target) do
    relevant =
      Enum.filter(records, &(&1["name"] == name and &1["type"] in ["A", "AAAA", "CNAME"]))

    case relevant do
      [] -> :absent
      [%{"type" => "A", "content" => ^target, "id" => id}] -> {:ok, %{id: id}}
      _ -> {:error, :dns_conflict}
    end
  end

  defp create_record(request, name, target, key) do
    opts = [
      method: :post,
      json: %{name: name, type: "A", content: target, ttl: 300},
      headers: [{"idempotency-key", key}]
    ]

    case perform_request(request, opts) do
      {:ok, %{status: status, body: %{"data" => record}}} when status in [200, 201] ->
        case classify_records([record], name, target) do
          {:ok, _} = found -> found
          _ -> {:error, :dns_conflict}
        end

      _ ->
        reconcile_uncertain_create(request, name, target)
    end
  end

  # DNSimple does not promise idempotency-key semantics. A lost POST response is
  # reconciled by reading; neither Req nor this function blindly repeats POST.
  defp reconcile_uncertain_create(request, name, target) do
    with {:ok, records} <- list_records(request, name, 1, []) do
      case classify_records(records, name, target) do
        :absent -> {:error, :dns_unavailable}
        result -> result
      end
    end
  end

  defp perform_request(request, opts) do
    started = System.monotonic_time(:millisecond)
    result = Req.request(request, opts)

    outcome =
      case result do
        {:ok, %{status: status}} when status in 200..299 -> :ok
        _ -> :error
      end

    Metrics.external_api_call(
      "dnsimple",
      to_string(opts[:method]),
      System.monotonic_time(:millisecond) - started,
      outcome
    )

    result
  end
end
