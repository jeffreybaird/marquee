defmodule BobineWeb.RawBodyReader do
  @moduledoc """
  Custom body reader that caches the raw request body for webhook
  signature verification. Uses the process dictionary since conn.assigns
  set during body reading don't reliably propagate through Plug.Parsers.
  """

  def read_body(conn, opts) do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, body, conn} ->
        Process.put(:raw_body, body)
        {:ok, body, conn}

      {:more, body, conn} ->
        Process.put(:raw_body, body)
        {:more, body, conn}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
