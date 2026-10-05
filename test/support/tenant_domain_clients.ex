defmodule Marquee.TenantDomains.ScriptedClients do
  @moduledoc false
  use Agent

  def start_link(_opts),
    do: Agent.start_link(fn -> %{dns: [], probe: [], calls: []} end, name: __MODULE__)

  def script(kind, responses) do
    Agent.update(__MODULE__, &Map.put(&1, kind, responses))
  end

  def calls, do: Agent.get(__MODULE__, &Enum.reverse(&1.calls))

  def dispatch(kind, args) do
    response =
      Agent.get_and_update(__MODULE__, fn state ->
        case Map.fetch!(state, kind) do
          [response | rest] ->
            {response, state |> Map.put(kind, rest) |> Map.update!(:calls, &[{kind, args} | &1])}

          [] ->
            raise "Unexpected #{kind} call: #{inspect(args)}"
        end
      end)

    if is_function(response, 1), do: response.(args), else: response
  end
end

defmodule Marquee.TenantDomains.ScriptedDNSClient do
  @moduledoc false
  alias Marquee.TenantDomains.ScriptedClients

  def ensure_record(hostname, target, key) do
    ScriptedClients.dispatch(:dns, [hostname, target, key])
  end
end

defmodule Marquee.TenantDomains.ScriptedProbe do
  @moduledoc false
  alias Marquee.TenantDomains.ScriptedClients

  def check(hostname, target, identity) do
    ScriptedClients.dispatch(:probe, [hostname, target, identity])
  end
end

defmodule Marquee.TenantDomains.ScriptedResolver do
  @moduledoc false
  alias Marquee.TenantDomains.ScriptedClients

  def resolve(hostname), do: ScriptedClients.dispatch(:resolve, [hostname])
end
