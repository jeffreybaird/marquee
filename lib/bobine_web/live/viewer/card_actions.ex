defmodule BobineWeb.Viewer.CardActions do
  @moduledoc """
  Shared event handlers and engagement state for video card actions.

  Use this module in any viewer LiveView that renders `content_card`
  components. It injects:

  - `handle_event/3` clauses for `card_toggle_favorite`,
    `card_add_to_watchlist`, and `card_add_to_queue`
  - An `on_mount` callback that loads engagement state into assigns
  - Optimistic UI updates — assigns are updated immediately, DB
    writes happen in the same request but the UI doesn't wait for
    a page reload to reflect the new state

  ## Usage

      defmodule BobineWeb.Viewer.BrowseLive do
        use BobineWeb, :live_view
        use BobineWeb.Viewer.CardActions

        # ...
      end

  Requires the following assigns on the socket:
  - `:organization` — the current org struct
  - `:current_viewer` — the authenticated viewer (or nil)
  """

  alias Bobine.Content
  alias Bobine.Engagement

  defmacro __using__(_opts) do
    quote do
      alias BobineWeb.Viewer.CardActions

      on_mount {CardActions, :load_engagement_state}

      @impl true
      def handle_event("card_add_to_watchlist", %{"video-id" => video_id}, socket) do
        CardActions.handle_add_to_watchlist(video_id, socket)
      end

      @impl true
      def handle_event("card_toggle_favorite", %{"video-id" => video_id}, socket) do
        CardActions.handle_toggle_favorite(video_id, socket)
      end

      @impl true
      def handle_event("card_add_to_queue", %{"video-id" => video_id}, socket) do
        CardActions.handle_add_to_queue(video_id, socket)
      end
    end
  end

  @doc """
  Loads the viewer's engagement state (favorited, watchlisted, queued
  video IDs) into socket assigns. Runs as an `on_mount` callback.

  Exempt from doctest — hits the database.
  """
  def on_mount(:load_engagement_state, _params, _session, socket) do
    org = socket.assigns[:organization]
    viewer = socket.assigns[:current_viewer]

    if org && viewer do
      {:cont,
       socket
       |> Phoenix.Component.assign(
         :favorited_ids,
         Engagement.favorited_video_ids(org, viewer)
       )
       |> Phoenix.Component.assign(
         :watchlisted_ids,
         Engagement.watchlisted_video_ids(org, viewer)
       )
       |> Phoenix.Component.assign(:queued_ids, Engagement.queued_video_ids(org, viewer))}
    else
      {:cont,
       socket
       |> Phoenix.Component.assign(:favorited_ids, MapSet.new())
       |> Phoenix.Component.assign(:watchlisted_ids, MapSet.new())
       |> Phoenix.Component.assign(:queued_ids, MapSet.new())}
    end
  end

  @doc """
  Handles adding a video to the viewer's watchlist.
  Optimistically updates the UI, then persists.

  Exempt from doctest — hits the database.
  """
  def handle_add_to_watchlist(_video_id, %{assigns: %{current_viewer: nil}} = socket) do
    {:noreply, Phoenix.LiveView.push_navigate(socket, to: "/login")}
  end

  def handle_add_to_watchlist(video_id, socket) do
    watchlisted = socket.assigns.watchlisted_ids

    if video_id in watchlisted do
      {:noreply, socket}
    else
      socket =
        Phoenix.Component.assign(socket, :watchlisted_ids, MapSet.put(watchlisted, video_id))

      persist_add_to_watchlist(video_id, socket, watchlisted)
    end
  end

  @doc """
  Handles toggling a video's favorite status.
  Optimistically updates the UI, then persists.

  Exempt from doctest — hits the database.
  """
  def handle_toggle_favorite(_video_id, %{assigns: %{current_viewer: nil}} = socket) do
    {:noreply, Phoenix.LiveView.push_navigate(socket, to: "/login")}
  end

  def handle_toggle_favorite(video_id, socket) do
    org = socket.assigns.organization
    viewer = socket.assigns.current_viewer
    favorited = socket.assigns.favorited_ids

    new_favorited =
      if video_id in favorited do
        MapSet.delete(favorited, video_id)
      else
        MapSet.put(favorited, video_id)
      end

    socket = Phoenix.Component.assign(socket, :favorited_ids, new_favorited)

    with {:ok, video} <- Content.get_video(org, video_id),
         {:ok, _action} <- Engagement.toggle_favorite(org, viewer, video) do
      {:noreply, socket}
    else
      {:error, :not_found} ->
        {:noreply,
         socket
         |> Phoenix.Component.assign(:favorited_ids, favorited)
         |> Phoenix.LiveView.put_flash(:error, "Video not found")}
    end
  end

  @doc """
  Handles adding a video to the viewer's queue.
  Optimistically updates the UI, then persists.

  Exempt from doctest — hits the database.
  """
  def handle_add_to_queue(_video_id, %{assigns: %{current_viewer: nil}} = socket) do
    {:noreply, Phoenix.LiveView.push_navigate(socket, to: "/login")}
  end

  def handle_add_to_queue(video_id, socket) do
    queued = socket.assigns.queued_ids

    if video_id in queued do
      {:noreply, socket}
    else
      socket = Phoenix.Component.assign(socket, :queued_ids, MapSet.put(queued, video_id))

      persist_add_to_queue(video_id, socket, queued)
    end
  end

  # -- Private helpers to flatten nesting --

  defp persist_add_to_watchlist(video_id, socket, original_watchlisted) do
    org = socket.assigns.organization
    viewer = socket.assigns.current_viewer

    with {:ok, video} <- Content.get_video(org, video_id),
         {:ok, _item} <- Engagement.add_to_watchlist(org, viewer, video) do
      {:noreply, socket}
    else
      {:error, :already_in_watchlist} ->
        {:noreply, socket}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> Phoenix.Component.assign(:watchlisted_ids, original_watchlisted)
         |> Phoenix.LiveView.put_flash(:error, "Video not found")}

      {:error, _reason, _detail} ->
        {:noreply,
         socket
         |> Phoenix.Component.assign(
           :watchlisted_ids,
           MapSet.delete(original_watchlisted, video_id)
         )
         |> Phoenix.LiveView.put_flash(:error, "Could not add to watchlist")}
    end
  end

  defp persist_add_to_queue(video_id, socket, original_queued) do
    org = socket.assigns.organization
    viewer = socket.assigns.current_viewer

    with {:ok, video} <- Content.get_video(org, video_id),
         {:ok, _item} <- Engagement.add_to_queue(org, viewer, video, "browse") do
      {:noreply, socket}
    else
      {:error, :already_in_queue} ->
        {:noreply, socket}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> Phoenix.Component.assign(:queued_ids, original_queued)
         |> Phoenix.LiveView.put_flash(:error, "Video not found")}
    end
  end
end
