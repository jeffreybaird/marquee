defmodule Bobine.OtelTest do
  use ExUnit.Case, async: true

  require Bobine.Otel

  test "with_span returns the wrapped function's result on success" do
    result =
      Bobine.Otel.with_span "test.span" do
        {:ok, "hello"}
      end

    assert result == {:ok, "hello"}
  end

  test "with_span passes through error tuples" do
    result =
      Bobine.Otel.with_span "test.span" do
        {:error, :not_found}
      end

    assert result == {:error, :not_found}
  end

  test "with_span passes through three-element error tuples" do
    result =
      Bobine.Otel.with_span "test.span" do
        {:error, :validation, %{field: "bad"}}
      end

    assert result == {:error, :validation, %{field: "bad"}}
  end

  test "with_span passes through non-tuple values" do
    result =
      Bobine.Otel.with_span "test.span" do
        42
      end

    assert result == 42
  end

  test "with_span accepts attributes" do
    result =
      Bobine.Otel.with_span "test.span", %{"org_id" => "123"} do
        {:ok, "done"}
      end

    assert result == {:ok, "done"}
  end
end
