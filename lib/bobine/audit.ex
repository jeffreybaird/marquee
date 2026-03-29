defmodule Bobine.Audit do
  @moduledoc "Append-only audit log for all mutating operations."

  alias Bobine.Audit.Log
  alias Bobine.Repo

  @doc """
  Logs an auditable action.

  scope can be a %Scope{} or nil (for system-level actions).
  action is a string like "video.created".
  resource is the struct that was acted on.
  changes is a map of what changed (can be empty for creates/deletes).
  """
  def log(scope, action, resource, changes \\ %{}) do
    attrs = %{
      organization_id: org_id_from_scope(scope),
      user_id: user_id_from_scope(scope),
      action: action,
      resource_type: resource_type(resource),
      resource_id: resource_id(resource),
      changes: changes,
      metadata: build_metadata(scope)
    }

    %Log{}
    |> Log.changeset(attrs)
    |> Repo.insert()
  end

  defp org_id_from_scope(nil), do: nil
  defp org_id_from_scope(%{organization: nil}), do: nil
  defp org_id_from_scope(%{organization: org}), do: org.id

  defp user_id_from_scope(nil), do: nil
  defp user_id_from_scope(%{user: nil}), do: nil
  defp user_id_from_scope(%{user: user}), do: user.id

  defp resource_type(%{__struct__: module}), do: module |> Module.split() |> List.last()
  defp resource_type(_), do: "Unknown"

  defp resource_id(%{id: id}), do: id
  defp resource_id(_), do: nil

  defp build_metadata(scope) do
    base =
      case Bobine.RequestContext.current() do
        nil -> %{}
        ctx -> Map.take(ctx, [:request_id, :ip, :user_agent])
      end

    case scope do
      %{impersonated_by: admin_id} when not is_nil(admin_id) ->
        Map.put(base, :impersonated_by, admin_id)

      _ ->
        base
    end
  end
end
