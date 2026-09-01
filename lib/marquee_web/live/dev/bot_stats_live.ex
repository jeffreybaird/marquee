defmodule MarqueeWeb.Dev.BotStatsLive do
  @moduledoc """
  Development-only dashboard showing MarqueeBot simulation metrics.

  Reads the JSONL stats file written by MarqueeBot and displays
  p50/p75/p90 latency percentiles per action, grouped by org.
  Auto-refreshes every 5 seconds. Route gated behind `:dev_routes`.
  """

  use MarqueeWeb, :live_view

  @refresh_interval_ms 5_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Process.send_after(self(), :refresh, @refresh_interval_ms)

    {:ok,
     socket
     |> assign(:page_title, "Bot Stats")
     |> assign(:open_panels, MapSet.new())
     |> assign_stats(), layout: false}
  end

  @impl true
  def handle_event("toggle_panel", %{"panel" => panel}, socket) do
    open_panels = socket.assigns.open_panels

    open_panels =
      if MapSet.member?(open_panels, panel),
        do: MapSet.delete(open_panels, panel),
        else: MapSet.put(open_panels, panel)

    {:noreply, assign(socket, :open_panels, open_panels)}
  end

  @impl true
  def handle_info(:refresh, socket) do
    Process.send_after(self(), :refresh, @refresh_interval_ms)
    {:noreply, assign_stats(socket)}
  end

  defp assign_stats(socket) do
    metrics = read_metrics()
    agents = read_agents()

    by_org =
      metrics
      |> Enum.group_by(& &1["org_slug"])
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(fn {org, org_metrics} ->
        actions =
          org_metrics
          |> Enum.group_by(&base_action/1)
          |> Enum.sort_by(&elem(&1, 0))
          |> Enum.map(fn {action, action_metrics} ->
            durations = Enum.map(action_metrics, & &1["duration_ms"])
            ok_count = Enum.count(action_metrics, &(&1["result"] == "ok"))
            error_count = Enum.count(action_metrics, &(&1["result"] == "error"))

            %{
              name: action,
              total: length(action_metrics),
              ok: ok_count,
              errors: error_count,
              p50: percentile(durations, 50),
              p75: percentile(durations, 75),
              p90: percentile(durations, 90)
            }
          end)

        org_agents = Enum.filter(agents, &(&1["org_slug"] == org))

        error_breakdown = build_error_breakdown(org_metrics)

        %{org: org, actions: actions, agents: org_agents, error_breakdown: error_breakdown}
      end)

    agents_by_profile =
      agents
      |> Enum.group_by(& &1["profile"])
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(fn {profile, group} -> %{profile: profile, count: length(group)} end)

    socket
    |> assign(:by_org, by_org)
    |> assign(:total_metrics, length(metrics))
    |> assign(:total_agents, length(agents))
    |> assign(:agents_by_profile, agents_by_profile)
    |> assign(:last_updated, DateTime.utc_now())
  end

  defp read_metrics do
    path = Application.get_env(:marquee, :bot_stats_file, "../marquee_bot/stats.jsonl")

    case File.read(path) do
      {:ok, contents} ->
        contents
        |> String.split("\n", trim: true)
        |> Enum.flat_map(&parse_metric_line/1)

      {:error, _} ->
        []
    end
  end

  defp parse_metric_line(line) do
    case Jason.decode(line) do
      {:ok, %{"result" => "skipped"}} -> []
      {:ok, map} -> [map]
      {:error, _} -> []
    end
  end

  defp read_agents do
    path = Application.get_env(:marquee, :bot_agents_file, "../marquee_bot/agents.json")

    case File.read(path) do
      {:ok, contents} ->
        case Jason.decode(contents) do
          {:ok, agents} when is_list(agents) -> agents
          _ -> []
        end

      {:error, _} ->
        []
    end
  end

  defp build_error_breakdown(org_metrics) do
    org_metrics
    |> Enum.filter(&(&1["result"] == "error"))
    |> Enum.group_by(fn m ->
      reason = m["error_reason"] || "unknown"
      action = base_action(m)
      {action, reason}
    end)
    |> Enum.map(fn {{action, reason}, entries} ->
      %{action: action, reason: reason, count: length(entries)}
    end)
    |> Enum.sort_by(& &1.count, :desc)
  end

  defp base_action(%{"action" => action}) do
    case String.split(action, ":", parts: 2) do
      [base, _event] -> base
      [base] -> base
    end
  end

  defp percentile([], _p), do: 0

  defp percentile(values, p) do
    sorted = Enum.sort(values)
    k = max(0, ceil(length(sorted) * p / 100) - 1)
    Enum.at(sorted, k)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main class="min-h-screen bg-bg text-text-primary font-ui">
      <header class="border-b border-border-subtle">
        <div class="mx-auto max-w-7xl px-6 py-10">
          <p class="font-mono text-xs uppercase tracking-wide text-text-muted">
            Dev · MarqueeBot metrics
          </p>
          <h1 class="mt-2 font-display text-4xl leading-tight tracking-tighter text-text-primary">
            Bot Stats
          </h1>
          <p class="mt-3 max-w-2xl font-body text-base leading-relaxed text-text-secondary">
            Latency percentiles from the MarqueeBot viewer simulation.
            Auto-refreshes every 5 seconds.
          </p>

          <div class="mt-4 flex items-center gap-6 font-mono text-xs text-text-muted">
            <span>Total metrics: {@total_metrics}</span>
            <span>Active agents: {@total_agents}</span>
            <span>
              Updated: {Calendar.strftime(@last_updated, "%H:%M:%S UTC")}
            </span>
          </div>

          <div :if={@agents_by_profile != []} class="mt-3 flex gap-3">
            <span
              :for={bp <- @agents_by_profile}
              class="rounded-full bg-surface px-3 py-1 font-mono text-xs text-text-secondary"
            >
              {bp.profile}: {bp.count}
            </span>
          </div>
        </div>
      </header>

      <div class="mx-auto max-w-7xl space-y-12 px-6 py-12">
        <div
          :if={@by_org == []}
          class="rounded-md border border-dashed border-border-subtle p-8 text-center text-text-muted"
        >
          <p class="text-lg">No metrics yet</p>
          <p class="mt-2 text-sm">
            Start MarqueeBot with
            <code class="rounded bg-surface px-1.5 py-0.5">mix marquee_bot.run</code>
            to generate data.
          </p>
        </div>

        <section :for={org_data <- @by_org} id={"org-#{org_data.org}"} class="scroll-mt-6">
          <h2 class="mb-4 font-display text-2xl leading-tight tracking-tight text-text-primary border-b border-border-subtle pb-3">
            {org_data.org}
          </h2>

          <div class="overflow-x-auto">
            <table class="w-full text-sm">
              <thead>
                <tr class="border-b border-border-subtle text-left text-text-muted font-mono text-xs uppercase tracking-wide">
                  <th class="py-3 pr-4">Action</th>
                  <th class="py-3 px-4 text-right">Total</th>
                  <th class="py-3 px-4 text-right">OK</th>
                  <th class="py-3 px-4 text-right">Errors</th>
                  <th class="py-3 px-4 text-right">p50</th>
                  <th class="py-3 px-4 text-right">p75</th>
                  <th class="py-3 px-4 text-right">p90</th>
                </tr>
              </thead>
              <tbody>
                <tr
                  :for={action <- org_data.actions}
                  class="border-b border-border-subtle/50 hover:bg-surface/40"
                >
                  <td class="py-3 pr-4 font-mono">{action.name}</td>
                  <td class="py-3 px-4 text-right tabular-nums">{action.total}</td>
                  <td class="py-3 px-4 text-right tabular-nums text-green-500">{action.ok}</td>
                  <td class={[
                    "py-3 px-4 text-right tabular-nums",
                    if(action.errors > 0, do: "text-red-400", else: "text-text-muted")
                  ]}>
                    {action.errors}
                  </td>
                  <td class="py-3 px-4 text-right tabular-nums">{action.p50}ms</td>
                  <td class="py-3 px-4 text-right tabular-nums">{action.p75}ms</td>
                  <td class={[
                    "py-3 px-4 text-right tabular-nums font-semibold",
                    latency_color(action.p90)
                  ]}>
                    {action.p90}ms
                  </td>
                </tr>
              </tbody>
            </table>
          </div>

          <div :if={org_data.error_breakdown != []} class="mt-6">
            <h3 class="mb-2 font-mono text-xs uppercase tracking-wide text-text-muted">
              Error Breakdown
            </h3>
            <div class="overflow-x-auto">
              <table class="w-full text-sm">
                <thead>
                  <tr class="border-b border-border-subtle text-left text-text-muted font-mono text-xs uppercase tracking-wide">
                    <th class="py-2 pr-4">Action</th>
                    <th class="py-2 px-4">Error Reason</th>
                    <th class="py-2 px-4 text-right">Count</th>
                  </tr>
                </thead>
                <tbody>
                  <tr
                    :for={err <- org_data.error_breakdown}
                    class="border-b border-border-subtle/50 hover:bg-surface/40"
                  >
                    <td class="py-2 pr-4 font-mono text-xs">{err.action}</td>
                    <td class="py-2 px-4 font-mono text-xs text-red-400">{err.reason}</td>
                    <td class="py-2 px-4 text-right tabular-nums">{err.count}</td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>

          <div :if={org_data.agents != []} id={"agents-#{org_data.org}"} class="mt-4">
            <button
              type="button"
              phx-click="toggle_panel"
              phx-value-panel={org_data.org}
              class="cursor-pointer font-mono text-xs text-text-muted hover:text-text-secondary"
            >
              {length(org_data.agents)} active agents
              <span :if={MapSet.member?(@open_panels, org_data.org)}>▾</span>
              <span :if={!MapSet.member?(@open_panels, org_data.org)}>▸</span>
            </button>
            <div :if={MapSet.member?(@open_panels, org_data.org)} class="mt-2 overflow-x-auto">
              <table class="w-full text-sm">
                <thead>
                  <tr class="border-b border-border-subtle text-left text-text-muted font-mono text-xs uppercase tracking-wide">
                    <th class="py-2 pr-4">Email</th>
                    <th class="py-2 px-4">Profile</th>
                    <th class="py-2 px-4">Subscription</th>
                    <th class="py-2 px-4">Last Action</th>
                    <th class="py-2 px-4 text-right">OK</th>
                    <th class="py-2 px-4 text-right">Errors</th>
                    <th class="py-2 px-4 text-right">Streak</th>
                  </tr>
                </thead>
                <tbody>
                  <tr
                    :for={agent <- org_data.agents}
                    class="border-b border-border-subtle/50 hover:bg-surface/40"
                  >
                    <td class="py-2 pr-4 font-mono text-xs">{agent["email"]}</td>
                    <td class="py-2 px-4 font-mono text-xs">{agent["profile"]}</td>
                    <td class="py-2 px-4 font-mono text-xs">{agent["subscription_status"]}</td>
                    <td class="py-2 px-4 font-mono text-xs">{agent["last_action"]}</td>
                    <td class="py-2 px-4 text-right tabular-nums text-green-500">
                      {agent["actions_completed"]}
                    </td>
                    <td class={[
                      "py-2 px-4 text-right tabular-nums",
                      if(agent["actions_failed"] > 0, do: "text-red-400", else: "text-text-muted")
                    ]}>
                      {agent["actions_failed"]}
                    </td>
                    <td class={[
                      "py-2 px-4 text-right tabular-nums",
                      if(agent["error_streak"] > 0, do: "text-red-400", else: "text-text-muted")
                    ]}>
                      {agent["error_streak"]}
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>
        </section>
      </div>
    </main>
    """
  end

  defp latency_color(ms) when ms < 200, do: "text-green-500"
  defp latency_color(ms) when ms < 500, do: "text-yellow-500"
  defp latency_color(_ms), do: "text-red-400"
end
