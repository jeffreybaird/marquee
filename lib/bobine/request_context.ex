defmodule Bobine.RequestContext do
  @moduledoc """
  Per-process request context. Set in a plug, available everywhere
  without passing through function signatures.
  """

  @key :bobine_request_context

  @doc """
  Stores request context in the current process dictionary.

      iex> Bobine.RequestContext.put(%{request_id: "abc-123", ip: "127.0.0.1"})
      iex> Bobine.RequestContext.current()
      %{request_id: "abc-123", ip: "127.0.0.1"}
  """
  def put(attrs) when is_map(attrs) do
    Process.put(@key, attrs)
  end

  @doc """
  Returns the current request context, or nil if none has been set.

      iex> Bobine.RequestContext.current()
      nil
  """
  def current do
    Process.get(@key)
  end

  @doc """
  Fetches a specific key from the current request context.

      iex> Bobine.RequestContext.put(%{ip: "10.0.0.1"})
      iex> Bobine.RequestContext.get(:ip)
      "10.0.0.1"

      iex> Bobine.RequestContext.get(:missing, "default")
      "default"
  """
  def get(key, default \\ nil) do
    case current() do
      nil -> default
      ctx -> Map.get(ctx, key, default)
    end
  end
end
