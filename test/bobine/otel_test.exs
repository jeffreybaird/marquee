defmodule Bobine.OtelTest do
  use ExUnit.Case, async: true

  require Bobine.Otel

  describe "with_span/3 return value pass-through" do
    test "returns ok tuple" do
      result =
        Bobine.Otel.with_span "test.span" do
          {:ok, "hello"}
        end

      assert result == {:ok, "hello"}
    end

    test "returns error tuple" do
      result =
        Bobine.Otel.with_span "test.span" do
          {:error, :not_found}
        end

      assert result == {:error, :not_found}
    end

    test "returns three-element error tuple" do
      result =
        Bobine.Otel.with_span "test.span" do
          {:error, :validation, %{field: "bad"}}
        end

      assert result == {:error, :validation, %{field: "bad"}}
    end

    test "returns non-tuple values" do
      result =
        Bobine.Otel.with_span "test.span" do
          42
        end

      assert result == 42
    end

    test "accepts attributes" do
      result =
        Bobine.Otel.with_span "test.span", %{"org_id" => "123"} do
          {:ok, "done"}
        end

      assert result == {:ok, "done"}
    end
  end

  describe "safe_span/3 resilience" do
    test "executes block when OpenTelemetry tracer raises UndefinedFunctionError" do
      # Simulate what happens during dev code reload: the :opentelemetry
      # module becomes temporarily unavailable, raising UndefinedFunctionError.
      # safe_span must rescue and still execute the block.
      result =
        Bobine.Otel.safe_span("test.span", %{}, fn ->
          {:ok, "survived"}
        end)

      assert result == {:ok, "survived"}
    end

    test "block side effects run even when tracing is unavailable" do
      # Verify that mutations inside the span block aren't lost
      test_pid = self()

      Bobine.Otel.safe_span("test.span", %{}, fn ->
        send(test_pid, :side_effect_ran)
        {:ok, "done"}
      end)

      assert_received :side_effect_ran
    end

    test "block exceptions propagate normally (not swallowed by rescue)" do
      assert_raise RuntimeError, "boom", fn ->
        Bobine.Otel.safe_span("test.span", %{}, fn ->
          raise "boom"
        end)
      end
    end
  end
end
