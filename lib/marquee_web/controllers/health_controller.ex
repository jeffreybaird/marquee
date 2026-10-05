defmodule MarqueeWeb.HealthController do
  @moduledoc """
  Health check endpoint used by the deploy pipeline to verify the app
  is ready to serve traffic. Checks that critical services are running.
  """

  use MarqueeWeb, :controller

  def check(conn, _params) do
    checks = %{
      pubsub: check_pubsub(),
      repo: check_repo(),
      oban: check_oban()
    }

    all_ok = Enum.all?(checks, fn {_k, v} -> v == :ok end)

    if all_ok do
      conn
      |> put_status(200)
      |> json(%{status: "ok", checks: Map.new(checks, fn {k, v} -> {k, to_string(v)} end)})
    else
      conn
      |> put_status(503)
      |> json(%{status: "unhealthy", checks: Map.new(checks, fn {k, v} -> {k, to_string(v)} end)})
    end
  end

  defp check_pubsub do
    if Process.whereis(Marquee.PubSub), do: :ok, else: :down
  end

  defp check_repo do
    Marquee.Repo.query!("SELECT 1")
    :ok
  rescue
    _ -> :down
  end

  defp check_oban do
    if Process.whereis(Oban.Registry), do: :ok, else: :down
  end
end
