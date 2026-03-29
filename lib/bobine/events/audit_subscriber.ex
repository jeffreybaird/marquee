defmodule Bobine.Events.AuditSubscriber do
  @moduledoc """
  GenServer that subscribes to all global events and creates audit log entries.
  """

  use GenServer

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    Bobine.Events.subscribe_global()
    {:ok, %{}}
  end

  @impl true
  def handle_info({:bobine_event, {action, resource}, scope}, state) do
    try do
      Bobine.Audit.log(scope, format_action(action), resource)
    rescue
      _error -> :ok
    end

    {:noreply, state}
  end

  defp format_action(atom) when is_atom(atom) do
    atom |> Atom.to_string() |> String.replace("_", ".")
  end
end
