defmodule Marquee.Workers.PodcastTokenReconciler do
  @moduledoc """
  Walks a show's active feed tokens after its access configuration
  changes (or after a viewer's subscription transitions) and revokes any
  token whose owner no longer has access.

  Two job shapes:

    * `%{"show_id" => id, "reason" => reason}` — sweep a single show
    * `%{"viewer_id" => id, "reason" => reason}` — sweep every show
      that viewer holds an active token for
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger

  import Ecto.Query, warn: false

  alias Marquee.Podcasts
  alias Marquee.Podcasts.{FeedToken, Show}
  alias Marquee.Repo
  alias Marquee.Viewers.Viewer

  @impl true
  def perform(%Oban.Job{args: %{"show_id" => show_id} = args}) do
    with :ok <-
           Marquee.AdminDemo.worker_permission(
             Marquee.AdminDemo.external_resource(Show, show_id, args["organization_id"])
           ) do
      case Repo.get(Show, show_id) do
        nil -> :ok
        %Show{} = show -> reconcile_show(show, Map.get(args, "reason", "show_access_changed"))
      end
    end
  end

  def perform(%Oban.Job{args: %{"viewer_id" => viewer_id} = args}) do
    with :ok <-
           Marquee.AdminDemo.worker_permission(
             Marquee.AdminDemo.external_resource(Viewer, viewer_id, args["organization_id"])
           ) do
      case Repo.get(Viewer, viewer_id) do
        nil ->
          :ok

        %Viewer{} = viewer ->
          reason = Map.get(args, "reason", "viewer_subscription_changed")
          reconcile_viewer(viewer, reason)
      end
    end
  end

  @doc "Convenience: enqueue reconciliation for a show."
  def enqueue_for_show(%Show{id: show_id}, reason) when is_binary(reason) do
    %{"show_id" => show_id, "reason" => reason}
    |> __MODULE__.new()
    |> Oban.insert()
  end

  @doc "Convenience: enqueue reconciliation for a viewer."
  def enqueue_for_viewer(%Viewer{id: viewer_id}, reason) when is_binary(reason) do
    %{"viewer_id" => viewer_id, "reason" => reason}
    |> __MODULE__.new()
    |> Oban.insert()
  end

  defp reconcile_show(%Show{} = show, reason) do
    show = Podcasts.with_access_plans(show)

    tokens = active_tokens_for_show(show.id) |> Repo.preload(:viewer)

    Enum.each(tokens, fn token ->
      maybe_revoke(show, token, reason)
    end)

    :ok
  end

  defp reconcile_viewer(%Viewer{} = viewer, reason) do
    tokens =
      from(t in FeedToken,
        where: t.viewer_id == ^viewer.id and t.status == "active"
      )
      |> Repo.all()
      |> Repo.preload(:show)

    Enum.each(tokens, fn token ->
      maybe_revoke(token.show, %{token | viewer: viewer}, reason)
    end)

    :ok
  end

  defp maybe_revoke(%Show{} = show, %FeedToken{viewer: %Viewer{} = viewer} = token, reason) do
    if Podcasts.can_access?(show, viewer) do
      :ok
    else
      Podcasts.revoke_feed_token(token, reason)
    end
  end

  defp active_tokens_for_show(show_id) do
    from(t in FeedToken, where: t.show_id == ^show_id and t.status == "active")
    |> Repo.all()
  end
end
