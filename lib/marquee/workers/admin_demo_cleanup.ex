defmodule Marquee.Workers.AdminDemoCleanup do
  @moduledoc "Expires a bounded batch of private admin sandboxes without external media effects."
  use Oban.Worker, queue: :admin_demo, max_attempts: 3, unique: [period: 60]
  require Marquee.Otel

  @impl true
  def perform(%Oban.Job{}) do
    Marquee.Otel.with_span "marquee.admin_demo.cleanup" do
      case Marquee.AdminDemo.cleanup_expired(per_page: 100) do
        {:ok, _counts} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end
end
