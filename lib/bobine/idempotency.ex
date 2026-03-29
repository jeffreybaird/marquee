defmodule Bobine.Idempotency do
  @moduledoc """
  Deterministic idempotency key generation for external API calls.
  """

  @doc """
  Generates a deterministic idempotency key for external API calls.

  The key includes the current date to allow retries on different days.

      iex> key = Bobine.Idempotency.key("create_upload", "org_123", "video_456")
      iex> String.starts_with?(key, "create_upload:org_123:video_456:")
      true
  """
  def key(operation, org_id, resource_id) do
    "#{operation}:#{org_id}:#{resource_id}:#{Date.utc_today()}"
  end
end
