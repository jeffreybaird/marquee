defmodule Marquee.Events.AuditSubscriber do
  @moduledoc """
  GenServer that subscribes to all global events and creates audit log entries.
  """

  use GenServer

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    Marquee.Events.subscribe_audit()
    {:ok, %{}}
  end

  @impl true
  def handle_info({:marquee_event, {action, resource}, scope}, state) do
    try do
      Marquee.Audit.log(scope, format_action(action), resource)
    rescue
      _error -> :ok
    end

    {:noreply, state}
  end

  defp format_action(atom) when is_atom(atom) do
    atom |> Atom.to_string() |> String.replace("_", ".")
  end
end
