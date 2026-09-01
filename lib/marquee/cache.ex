defmodule Marquee.Cache do
  @moduledoc """
  Simple ETS-based cache with TTL support.

  Stores key-value pairs with optional TTL. Expired entries are lazily cleaned
  on read. Designed to be swappable to Redis later via a behaviour.
  """

  use GenServer

  @table __MODULE__

  ## Client API

  @doc """
  Starts the cache GenServer and creates the ETS table.

  Exempt from doctest — starts a process.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Fetches a value from cache, computing it via `fun` on miss.

  Options:
  - `:ttl` — time to live in milliseconds (default: 60_000)

  Exempt from doctest — uses ETS.
  """
  def fetch(key, opts \\ [], fun) do
    ttl = Keyword.get(opts, :ttl, 60_000)

    case get(key) do
      {:ok, value} ->
        value

      :miss ->
        value = fun.()
        put(key, value, ttl: ttl)
        value
    end
  end

  @doc """
  Gets a value from the cache. Returns `{:ok, value}` or `:miss`.

  Exempt from doctest — uses ETS.
  """
  def get(key) do
    case :ets.lookup(@table, key) do
      [{^key, value, expires_at}] ->
        if System.monotonic_time(:millisecond) < expires_at do
          {:ok, value}
        else
          delete(key)
          :miss
        end

      [] ->
        :miss
    end
  rescue
    ArgumentError -> :miss
  end

  @doc """
  Puts a value into the cache with a TTL.

  Exempt from doctest — uses ETS.
  """
  def put(key, value, opts \\ []) do
    ttl = Keyword.get(opts, :ttl, 60_000)
    expires_at = System.monotonic_time(:millisecond) + ttl
    :ets.insert(@table, {key, value, expires_at})
    :ok
  rescue
    ArgumentError -> :ok
  end

  @doc """
  Deletes a key from the cache.

  Exempt from doctest — uses ETS.
  """
  def delete(key) do
    :ets.delete(@table, key)
    :ok
  rescue
    ArgumentError -> :ok
  end

  @doc """
  Deletes all keys matching the given prefix.

  Exempt from doctest — uses ETS.
  """
  def delete_by_prefix(prefix) do
    match_spec = [{{:"$1", :_, :_}, [{:is_binary, :"$1"}], [:"$1"]}]

    @table
    |> :ets.select(match_spec)
    |> Enum.filter(&String.starts_with?(&1, prefix))
    |> Enum.each(&delete/1)

    :ok
  rescue
    ArgumentError -> :ok
  end

  ## Server callbacks

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
    {:ok, %{}}
  end
end
