defmodule BobineWeb.Plugs.TelemetryOrgPlug do
  @moduledoc """
  Plug that adds tenant and user context to the current OpenTelemetry span.

  Must run AFTER `SetOrganization` and `fetch_current_scope_for_user` so that
  `current_scope` is populated in `conn.assigns`.
  """

  @behaviour Plug

  require OpenTelemetry.Tracer, as: Tracer

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    set_org_attributes(conn.assigns)
    set_user_attributes(conn.assigns)
    conn
  end

  defp set_org_attributes(%{current_scope: %{organization: %{id: org_id, slug: slug}}})
       when not is_nil(org_id) do
    safe_set_attributes([{"bobine.org.id", org_id}, {"bobine.org.slug", slug}])
  end

  defp set_org_attributes(%{organization: %{id: org_id, slug: slug}})
       when not is_nil(org_id) do
    safe_set_attributes([{"bobine.org.id", org_id}, {"bobine.org.slug", slug}])
  end

  defp set_org_attributes(_), do: :ok

  defp set_user_attributes(%{current_scope: %{user: %{id: user_id}}})
       when not is_nil(user_id) do
    safe_set_attributes([{"bobine.user.id", user_id}])
  end

  defp set_user_attributes(_), do: :ok

  defp safe_set_attributes(attrs) do
    Tracer.set_attributes(attrs)
  rescue
    UndefinedFunctionError -> :ok
  end
end
