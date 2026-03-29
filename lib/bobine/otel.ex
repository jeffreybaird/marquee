defmodule Bobine.Otel do
  @moduledoc """
  Helpers for creating OpenTelemetry spans in Bobine business logic.
  All span names follow the convention: bobine.<context>.<operation>
  """

  require OpenTelemetry.Tracer, as: Tracer

  @doc """
  Wraps a function in a named span with standard Bobine attributes.

  Automatically sets an "outcome" attribute based on the return value.

  ## Example

      Bobine.Otel.with_span "bobine.content.create_video", %{org_id: org.id} do
        do_create_video(scope, attrs)
      end
  """
  defmacro with_span(name, attributes \\ Macro.escape(%{}), do: block) do
    quote do
      require OpenTelemetry.Tracer, as: Tracer

      Tracer.with_span unquote(name), %{attributes: unquote(attributes)} do
        result = unquote(block)
        Bobine.Otel.tag_outcome(result)
        result
      end
    end
  end

  @doc """
  Tags the current span with outcome attributes based on the result value.
  Called automatically by `with_span`.
  """
  def tag_outcome({:ok, _}), do: Tracer.set_attribute("outcome", "success")

  def tag_outcome({:error, reason}) do
    Tracer.set_attribute("outcome", "error")
    Tracer.set_attribute("error.reason", inspect(reason))
  end

  def tag_outcome({:error, reason, _detail}) do
    Tracer.set_attribute("outcome", "error")
    Tracer.set_attribute("error.reason", inspect(reason))
  end

  def tag_outcome(_), do: :ok

  @doc """
  Adds standard organization context attributes to the current span.

      iex> Bobine.Otel.set_org_attributes(nil)
      :ok
  """
  def set_org_attributes(%{id: org_id, slug: slug}) do
    Tracer.set_attributes([
      {"bobine.org.id", org_id},
      {"bobine.org.slug", slug}
    ])
  end

  def set_org_attributes(_), do: :ok

  @doc """
  Adds user context attributes to the current span.

      iex> Bobine.Otel.set_user_attributes(nil)
      :ok
  """
  def set_user_attributes(%{id: user_id, email: email}) do
    Tracer.set_attributes([
      {"bobine.user.id", user_id},
      {"bobine.user.email", email}
    ])
  end

  def set_user_attributes(_), do: :ok
end
