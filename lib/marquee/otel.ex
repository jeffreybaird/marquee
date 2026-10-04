defmodule Marquee.Otel do
  @moduledoc """
  Helpers for creating OpenTelemetry spans in Marquee business logic.
  All span names follow the convention: marquee.<context>.<operation>

  Spans are resilient — if OpenTelemetry is unavailable (e.g. during code
  reload in dev), the wrapped block still executes normally.
  """

  require OpenTelemetry.Tracer, as: Tracer

  @doc """
  Wraps a function in a named span with standard Marquee attributes.

  Automatically sets an "outcome" attribute based on the return value.
  If OpenTelemetry is unavailable, executes the block without tracing.

  ## Example

      Marquee.Otel.with_span "marquee.content.create_video", %{org_id: org.id} do
        do_create_video(scope, attrs)
      end
  """
  defmacro with_span(name, attributes \\ Macro.escape(%{}), do: block) do
    quote do
      Marquee.Otel.safe_span(unquote(name), unquote(attributes), fn ->
        unquote(block)
      end)
    end
  end

  @doc false
  def safe_span(name, attributes, fun) do
    Tracer.with_span name, %{attributes: attributes} do
      result = fun.()
      tag_outcome(result)
      result
    end
  rescue
    UndefinedFunctionError ->
      fun.()
  end

  @doc """
  Tags the current span with outcome attributes based on the result value.
  Called automatically by `with_span`.
  """
  def tag_outcome({:ok, _}), do: safe_set_attribute("outcome", "success")

  def tag_outcome({:error, reason}) do
    safe_set_attribute("outcome", "error")
    safe_set_attribute("error.reason", inspect(reason))
  end

  def tag_outcome({:error, reason, _detail}) do
    safe_set_attribute("outcome", "error")
    safe_set_attribute("error.reason", inspect(reason))
  end

  def tag_outcome(_), do: :ok

  @doc """
  Adds standard organization context attributes to the current span.

      iex> require Marquee.Otel
      iex> Marquee.Otel.with_span "example.attributes" do
      ...>   Marquee.Otel.set_org_attributes(%{id: "org-example", slug: "example"})
      ...> end
      true

      iex> Marquee.Otel.set_org_attributes(nil)
      :ok
  """
  def set_org_attributes(%{id: org_id, slug: slug}) do
    Tracer.set_attributes([
      {"marquee.org.id", org_id},
      {"marquee.org.slug", slug}
    ])
  rescue
    UndefinedFunctionError -> :ok
  end

  def set_org_attributes(_), do: :ok

  @doc """
  Adds user context attributes to the current span.
  Only sets the user ID — no PII (email, name) in span attributes.

      iex> require Marquee.Otel
      iex> Marquee.Otel.with_span "example.attributes" do
      ...>   Marquee.Otel.set_user_attributes(%{id: "user-example"})
      ...> end
      true

      iex> Marquee.Otel.set_user_attributes(nil)
      :ok
  """
  def set_user_attributes(%{id: user_id}) do
    Tracer.set_attributes([
      {"marquee.user.id", user_id}
    ])
  rescue
    UndefinedFunctionError -> :ok
  end

  def set_user_attributes(_), do: :ok

  @doc """
  Injects the current OpenTelemetry trace context into an Oban job args map
  under the `"trace_context"` key so the worker can re-attach to the parent
  trace.

  Safe to call when OpenTelemetry is unavailable — returns the args map
  unchanged.
  """
  def put_trace_context(args) when is_map(args) do
    carrier = :otel_propagator_text_map.inject([])
    Map.put(args, "trace_context", Map.new(carrier))
  rescue
    UndefinedFunctionError -> args
  end

  @doc """
  Restores an OpenTelemetry trace context previously injected into Oban job
  args by `put_trace_context/1`. Safe to call if the key is absent or
  OpenTelemetry is unavailable.
  """
  def extract_trace_context(nil), do: :ok

  def extract_trace_context(ctx) when is_map(ctx) do
    :otel_propagator_text_map.extract(Enum.into(ctx, []))
    :ok
  rescue
    UndefinedFunctionError -> :ok
  end

  def extract_trace_context(_), do: :ok

  defp safe_set_attribute(key, value) do
    Tracer.set_attribute(key, value)
  rescue
    UndefinedFunctionError -> :ok
  end
end
