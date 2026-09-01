defmodule MarqueeWeb.Plugs.RateLimit do
  @moduledoc """
  Token-bucket rate limiter plug. ETS-backed, single-node counters.

  Options:

    * `:bucket`  — required atom identifying the bucket (e.g. `:webhook_mux`).
      Each bucket has its own ETS table and counters.
    * `:limit`   — integer requests allowed per `:period`. Defaults to `100`.
    * `:period`  — window length in milliseconds. Defaults to 60_000 (1 minute).
    * `:key`     — how to derive the counter key from the conn. One of
      `:ip`, `:organization_id`, `:user_id`. Defaults to `:ip`. When the
      chosen assign is missing, the plug falls back to the remote IP.

  On breach, responds with HTTP 429, sets `retry-after` (seconds), and
  halts the pipeline.

  Backed by ETS; limits are per-node. See `.claude/scalability.md` for the
  migration path to a shared Redis counter at scale.
  """

  import Plug.Conn

  @default_limit 100
  @default_period :timer.minutes(1)
  @table :marquee_rate_limit

  @doc """
  Initializes options for the plug. The only required option is `:bucket`.

  ## Examples

      iex> MarqueeWeb.Plugs.RateLimit.init(bucket: :webhook_mux, limit: 500)
      [bucket: :webhook_mux, limit: 500]

      iex> MarqueeWeb.Plugs.RateLimit.init(bucket: :auth, limit: 10, key: :ip)
      [bucket: :auth, limit: 10, key: :ip]
  """
  def init(opts) do
    _bucket = Keyword.fetch!(opts, :bucket)
    opts
  end

  @doc """
  Applies the rate limit to `conn`.

  Exempt from doctest — mutates ETS and the Plug.Conn.
  """
  def call(conn, opts) do
    if Application.get_env(:marquee, :rate_limit_disabled, false) do
      conn
    else
      do_call(conn, opts)
    end
  end

  defp do_call(conn, opts) do
    bucket = Keyword.fetch!(opts, :bucket)
    limit = Keyword.get(opts, :limit, @default_limit)
    period = Keyword.get(opts, :period, @default_period)
    key_kind = Keyword.get(opts, :key, :ip)

    key = build_counter_key(conn, bucket, key_kind)

    case check_rate(key, limit, period) do
      :ok ->
        conn

      :rate_limited ->
        conn
        |> put_resp_header("retry-after", to_string(div(period, 1000)))
        |> send_resp(429, "Rate limit exceeded")
        |> halt()
    end
  end

  # Exposed for tests — lets suites drop state between cases.
  @doc false
  def reset do
    ensure_table()
    :ets.delete_all_objects(@table)
    :ok
  end

  defp build_counter_key(conn, bucket, :ip) do
    {bucket, :ip, ip_string(conn)}
  end

  defp build_counter_key(conn, bucket, :organization_id) do
    case fetch_organization_id(conn) do
      nil -> {bucket, :ip, ip_string(conn)}
      org_id -> {bucket, :organization_id, org_id}
    end
  end

  defp build_counter_key(conn, bucket, :user_id) do
    case fetch_user_id(conn) do
      nil -> {bucket, :ip, ip_string(conn)}
      user_id -> {bucket, :user_id, user_id}
    end
  end

  defp ip_string(%Plug.Conn{remote_ip: ip}), do: ip |> :inet.ntoa() |> to_string()

  defp fetch_organization_id(conn) do
    case conn.assigns[:organization] do
      %{id: id} when not is_nil(id) -> id
      _ -> get_in(conn.assigns, [:current_scope, Access.key(:organization), Access.key(:id)])
    end
  end

  defp fetch_user_id(conn) do
    get_in(conn.assigns, [:current_scope, Access.key(:user), Access.key(:id)])
  end

  defp check_rate(key, limit, period) do
    ensure_table()
    now = System.monotonic_time(:millisecond)
    window_start = now - period

    # Counter layout: {key, count, window_start_ms}
    case :ets.lookup(@table, key) do
      [] ->
        :ets.insert(@table, {key, 1, now})
        :ok

      [{^key, _count, started_at}] when started_at < window_start ->
        # Window expired — reset.
        :ets.insert(@table, {key, 1, now})
        :ok

      [{^key, count, _started_at}] when count < limit ->
        :ets.update_counter(@table, key, {2, 1})
        :ok

      [{^key, _count, _started_at}] ->
        :rate_limited
    end
  end

  defp ensure_table do
    case :ets.whereis(@table) do
      :undefined ->
        :ets.new(@table, [:named_table, :public, :set, write_concurrency: true])

      _tid ->
        @table
    end
  end
end
