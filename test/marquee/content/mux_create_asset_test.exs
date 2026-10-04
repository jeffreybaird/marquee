defmodule Marquee.Content.MuxCreateAssetTest do
  use ExUnit.Case, async: false
  alias Marquee.Content.MuxClient

  setup do
    previous =
      for {app, key} <- [
            {:tesla, :adapter},
            {:marquee, :mux_token_id},
            {:marquee, :mux_token_secret}
          ],
          do: {app, key, Application.fetch_env(app, key)}

    Application.put_env(:tesla, :adapter, Tesla.Mock)
    Application.put_env(:marquee, :mux_token_id, "fixture-id")
    Application.put_env(:marquee, :mux_token_secret, "fixture-secret")
    :ok = :otel_simple_processor.set_exporter(:otel_exporter_pid, self())

    on_exit(fn ->
      :otel_simple_processor.set_exporter(:none)

      for {app, key, prior} <- previous do
        case prior do
          {:ok, value} -> Application.put_env(app, key, value)
          :error -> Application.delete_env(app, key)
        end
      end
    end)

    :ok
  end

  test "SDK asset creation carries the supplied idempotency key and exports a Mux span" do
    params = %{
      input: [%{url: "https://example.com/reviewed-footage.mp4"}],
      playback_policy: ["public"]
    }

    Tesla.Mock.mock(fn env ->
      assert env.method == :post
      assert env.url == "https://api.mux.com/video/v1/assets"

      assert Enum.any?(env.headers, fn {name, value} ->
               String.downcase(name) == "idempotency-key" and value == "workshop-reviewed-asset-1"
             end)

      assert Jason.decode!(env.body) == %{
               "input" => [%{"url" => "https://example.com/reviewed-footage.mp4"}],
               "playback_policy" => ["public"]
             }

      %Tesla.Env{status: 201, body: %{"data" => %{"id" => "asset-1", "status" => "preparing"}}}
    end)

    assert {:ok, %{"id" => "asset-1"}} =
             MuxClient.create_asset(params, "workshop-reviewed-asset-1")

    assert_receive {:span, span} when elem(span, 6) == "marquee.mux.create_asset", 1000
    attributes = span |> elem(10) |> :otel_attributes.map()
    assert attributes["marquee.service"] == "mux"
    assert attributes["marquee.mux.operation"] == "create_asset"
  end

  test "Mux rejection retains the established tagged error contract" do
    Tesla.Mock.mock(fn _ ->
      %Tesla.Env{
        status: 400,
        body: %{"error" => %{"type" => "invalid_parameters", "messages" => ["invalid input"]}}
      }
    end)

    assert {:error, :mux_error, %{type: "invalid_parameters", messages: ["invalid input"]}} =
             MuxClient.create_asset(%{input: []}, "workshop-invalid-input")
  end

  test "missing idempotency keys are rejected before any HTTP request" do
    Tesla.Mock.mock(fn _ -> flunk("invalid idempotency key must not send a request") end)

    for key <- [nil, "", 123] do
      assert {:error, :mux_error, :invalid_idempotency_key} = MuxClient.create_asset(%{}, key)
    end
  end
end
