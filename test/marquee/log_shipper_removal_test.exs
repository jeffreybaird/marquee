defmodule Marquee.LogShipperRemovalTest do
  @moduledoc """
  Logs ship through the OTLP hub (`Marquee.Otel.Export`); the Grafana Loki
  shipper is gone and must not be compiled into the application.
  """
  use ExUnit.Case, async: true

  test "the Grafana Loki log shipper module no longer exists" do
    refute Code.ensure_loaded?(Marquee.LogShipper)
  end
end
