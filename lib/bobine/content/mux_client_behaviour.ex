defmodule Bobine.Content.MuxClientBehaviour do
  @moduledoc """
  Behaviour contract for the Mux API client.

  All Mux API calls go through a module implementing this behaviour.
  In production, `Bobine.Content.MuxClient` is used. In tests, a
  `Mox`-generated mock is injected via config.
  """

  @callback create_upload(map()) :: {:ok, map()} | {:error, term()}
  @callback get_asset(String.t()) :: {:ok, map()} | {:error, term()}
  @callback delete_asset(String.t()) :: {:ok, map()} | {:error, term()}
  @callback create_playback_id(String.t()) :: {:ok, map()} | {:error, term()}
  @callback delete_playback_id(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  @callback get_asset_input_info(String.t()) :: {:ok, map()} | {:error, term()}
end
