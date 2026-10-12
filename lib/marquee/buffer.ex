defmodule Marquee.Buffer do
  @moduledoc """
  Behaviour for write buffers that keep high-frequency writes off the
  Postgres hot path. Callers `push/1` entries and never learn whether the
  write was buffered or direct; the buffer persists them on `flush/0`
  (periodically, on demand, and when it stops).
  """

  @doc "Accepts one entry for a later flush."
  @callback push(entry :: term()) :: :ok

  @doc "Persists every pending entry before returning."
  @callback flush() :: :ok
end
