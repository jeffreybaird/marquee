defmodule Bobine.Content.MuxClientBehaviour do
  @moduledoc """
  Behaviour contract for the Mux API client.

  All Mux API calls go through a module implementing this behaviour.
  In production, `Bobine.Content.MuxClient` is used. In tests, a
  `Mox`-generated mock is injected via config.
  """

  @callback create_direct_upload(map()) :: {:ok, map()} | {:error, :mux_error, term()}
  @callback get_asset(String.t()) :: {:ok, map()} | {:error, :mux_error, term()}
  @callback delete_asset(String.t()) :: :ok | {:error, :mux_error, term()}
  @callback list_assets(keyword()) :: {:ok, list(map())} | {:error, :mux_error, term()}

  # Live stream callbacks
  @callback create_live_stream(map()) :: {:ok, map()} | {:error, :mux_error, term()}
  @callback get_live_stream(String.t()) :: {:ok, map()} | {:error, :mux_error, term()}
  @callback delete_live_stream(String.t()) :: :ok | {:error, :mux_error, term()}
  @callback disable_live_stream(String.t()) :: :ok | {:error, :mux_error, term()}
  @callback enable_live_stream(String.t()) :: :ok | {:error, :mux_error, term()}
  @callback reset_stream_key(String.t()) :: {:ok, map()} | {:error, :mux_error, term()}
end
