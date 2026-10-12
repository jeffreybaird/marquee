defmodule MarqueeWeb.Viewer.ShortsLive do
  @moduledoc """
  Viewer Shorts feed: an operator-curated vertical feed of short clips,
  one clip per screen.

  The organization's `shorts_feed_access` decides who can play every clip
  in the feed (each video's own visibility is ignored here). A locked clip
  renders its operator poster or a branded placeholder plus a call to
  action and never exposes its Mux playback id or any Mux image URL.

  Playback events are accepted only for clips this socket rendered as
  playable; member preview and operator impersonation never write.

  Hooks: ShortsFeed (player window, autoplay, keyboard, pagination)
  Events: load_more, playback_*, toggle_favorite, toggle_watchlist
  Route: /shorts (home live_session, so the nav from Home live-navigates)
  """

  use MarqueeWeb, :live_view

  alias Marquee.Content
  alias Marquee.Content.{AccessControl, AspectRatio}
  alias Marquee.Engagement
  alias Marquee.Metrics
  alias Marquee.SubscriberDemo
  alias MarqueeWeb.Components.ViewerLayout

  @per_page 8

  @impl true
  def mount(_params, _session, socket) do
    org = socket.assigns[:organization]

    cond do
      is_nil(org) ->
        {:ok, redirect(socket, to: ~p"/")}

      not org.shorts_feed_enabled ->
        {:ok,
         socket
         |> put_flash(:info, "Shorts aren't available right now.")
         |> redirect(to: ~p"/")}

      true ->
        {:ok, mount_feed(socket, org, socket.assigns[:current_viewer])}
    end
  end

  defp mount_feed(socket, org, viewer) do
    socket
    |> assign(:page_title, "Shorts")
    |> assign(:access, AccessControl.feed_access(org.shorts_feed_access, viewer))
    |> assign(:only_video_ids, demo_video_ids(org, viewer))
    |> assign(:writer, engagement_writer(viewer))
    |> assign_engagement_state(org, viewer)
    |> assign(page: 0, total: 0, has_more: false, clip_index: %{}, playable: %{})
    |> stream_configure(:clips, dom_id: &"short-#{&1.id}")
    |> stream(:clips, [])
    |> load_next_page()
  end

  # A subscriber-demo viewer only sees the organization's demo clips; the
  # others are omitted, not shown locked.
  defp demo_video_ids(org, viewer) do
    ids = (org.features || %{})["subscriber_demo_video_ids"]
    if SubscriberDemo.demo_viewer?(viewer) and is_list(ids), do: ids, else: nil
  end

  # Only a real, signed-in viewer writes engagement. Member preview and
  # operator impersonation are read-only.
  defp engagement_writer(%{__preview__: true}), do: nil
  defp engagement_writer(%{__impersonating__: true}), do: nil
  defp engagement_writer(%{metadata: %{"admin_demo_sample" => true}}), do: nil
  defp engagement_writer(viewer), do: viewer

  defp assign_engagement_state(socket, org, viewer) when not is_nil(viewer) do
    socket
    |> assign(:favorited_ids, MapSet.new(Engagement.favorited_video_ids(org, viewer)))
    |> assign(:watchlisted_ids, MapSet.new(Engagement.watchlisted_video_ids(org, viewer)))
  end

  defp assign_engagement_state(socket, _org, nil) do
    socket
    |> assign(:favorited_ids, MapSet.new())
    |> assign(:watchlisted_ids, MapSet.new())
  end

  defp load_next_page(socket) do
    org = socket.assigns.organization
    next_page = socket.assigns.page + 1
    opts = page_opts(next_page, socket.assigns.only_video_ids)

    case Content.list_short_feed(org, opts) do
      {:ok, %{results: videos, total: total, total_pages: total_pages}} ->
        offset = (next_page - 1) * @per_page
        clips = build_clips(videos, offset, total, socket.assigns.access)

        socket
        |> assign(page: next_page, total: total, has_more: next_page < total_pages)
        |> remember_clips(clips)
        |> stream(:clips, clips)

      {:error, :feed_disabled} ->
        assign(socket, :has_more, false)
    end
  end

  defp page_opts(page, nil), do: [page: page, per_page: @per_page]
  defp page_opts(page, ids), do: [page: page, per_page: @per_page, only_video_ids: ids]

  defp build_clips(videos, offset, total, access) do
    videos
    |> Enum.with_index(offset)
    |> Enum.map(fn {video, index} ->
      %{id: video.id, video: video, index: index, setsize: total, access: access}
    end)
  end

  # Keeps only what event handlers need: each loaded clip's index (to
  # re-render it) and, for playable clips, the duration used to clamp
  # progress. This is the server-side allowlist for playback events.
  defp remember_clips(socket, clips) do
    playable_clips = Enum.filter(clips, &(&1.access == :playable))

    socket
    |> update(:clip_index, &Map.merge(&1, Map.new(clips, fn c -> {c.id, c.index} end)))
    |> update(:playable, fn playable ->
      Map.merge(playable, Map.new(playable_clips, fn c -> {c.id, c.video.duration} end))
    end)
  end

  ## -----------------------------------------------------------------------
  ## Pagination
  ## -----------------------------------------------------------------------

  @impl true
  def handle_event("load_more", _params, socket) do
    if socket.assigns.has_more,
      do: {:noreply, load_next_page(socket)},
      else: {:noreply, socket}
  end

  ## -----------------------------------------------------------------------
  ## Playback events (same names/payloads as mux_player.ts)
  ## -----------------------------------------------------------------------

  def handle_event(event, %{"video_id" => video_id} = params, socket)
      when event in ~w(playback_started playback_progress playback_paused) do
    Metrics.watch_event(socket.assigns.organization.id, event)

    with {:ok, duration} <- playable_duration(socket, video_id),
         %{} = viewer <- socket.assigns.writer,
         position when is_number(position) <- Map.get(params, "position") do
      duration = duration || 0.0

      Engagement.update_progress(
        socket.assigns.organization,
        viewer,
        video_id,
        clamp_position(position, duration),
        duration
      )
    end

    {:noreply, socket}
  end

  def handle_event("playback_ended", %{"video_id" => video_id}, socket) do
    org = socket.assigns.organization
    Metrics.watch_event(org.id, "playback_ended")

    # Buffered: the clip is already verified playable for this socket, so no
    # read is needed; the write lands on the next engagement-buffer flush.
    with {:ok, _duration} <- playable_duration(socket, video_id),
         %{} = viewer <- socket.assigns.writer do
      Engagement.buffer_completion(org, viewer, %{id: video_id})
    end

    {:noreply, socket}
  end

  def handle_event("playback_drop_off", %{"video_id" => video_id} = params, socket) do
    org = socket.assigns.organization
    Metrics.watch_event(org.id, "playback_drop_off")

    with {:ok, _duration} <- playable_duration(socket, video_id),
         %{} = viewer <- socket.assigns.writer do
      Engagement.buffer_drop_off(%{
        viewer_id: viewer.id,
        organization_id: org.id,
        video_id: video_id,
        max_position: Map.get(params, "max_position", 0.0),
        video_duration: Map.get(params, "video_duration")
      })
    end

    {:noreply, socket}
  end

  def handle_event("playback_clip_activated", %{"video_id" => video_id}, socket) do
    with {:ok, _duration} <- playable_duration(socket, video_id),
         false <- read_only_viewer?(socket.assigns[:current_viewer]) do
      Metrics.video_viewed(socket.assigns.organization.id, video_id)
    end

    {:noreply, socket}
  end

  ## -----------------------------------------------------------------------
  ## Favorite and watchlist
  ## -----------------------------------------------------------------------

  def handle_event("toggle_favorite", %{"video-id" => video_id}, socket) do
    with_loaded_clip(socket, video_id, fn socket, video ->
      persist_favorite_toggle(socket, video)
    end)
  end

  def handle_event("toggle_watchlist", %{"video-id" => video_id}, socket) do
    with_loaded_clip(socket, video_id, fn socket, video ->
      persist_watchlist_toggle(socket, video)
    end)
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  defp with_loaded_clip(socket, video_id, fun) do
    cond do
      is_nil(socket.assigns[:current_viewer]) ->
        {:noreply, push_navigate(socket, to: ~p"/login")}

      is_nil(socket.assigns.writer) ->
        {:noreply, put_flash(socket, :info, "This preview is read-only.")}

      not Map.has_key?(socket.assigns.clip_index, video_id) ->
        {:noreply, socket}

      true ->
        case Content.get_video(socket.assigns.organization, video_id) do
          {:ok, video} -> fun.(socket, video) |> rerender_clip(video)
          {:error, :not_found} -> {:noreply, socket}
        end
    end
  end

  defp persist_favorite_toggle(socket, video) do
    case Engagement.toggle_favorite(socket.assigns.organization, socket.assigns.writer, video) do
      {:ok, _id, :added} -> update(socket, :favorited_ids, &MapSet.put(&1, video.id))
      {:ok, _id, :removed} -> update(socket, :favorited_ids, &MapSet.delete(&1, video.id))
      _error -> put_flash(socket, :error, "Could not update favorites.")
    end
  end

  defp persist_watchlist_toggle(socket, video) do
    org = socket.assigns.organization
    viewer = socket.assigns.writer

    if MapSet.member?(socket.assigns.watchlisted_ids, video.id) do
      Engagement.remove_from_watchlist(org, viewer, video)
      update(socket, :watchlisted_ids, &MapSet.delete(&1, video.id))
    else
      case Engagement.add_to_watchlist(org, viewer, video) do
        {:ok, _item} ->
          update(socket, :watchlisted_ids, &MapSet.put(&1, video.id))

        {:error, :already_in_watchlist} ->
          update(socket, :watchlisted_ids, &MapSet.put(&1, video.id))

        _error ->
          put_flash(socket, :error, "Could not update your list.")
      end
    end
  end

  # Streamed items only re-render when re-inserted.
  defp rerender_clip(socket, video) do
    clip = %{
      id: video.id,
      video: video,
      index: Map.fetch!(socket.assigns.clip_index, video.id),
      setsize: socket.assigns.total,
      access:
        if(Map.has_key?(socket.assigns.playable, video.id),
          do: :playable,
          else: socket.assigns.access
        )
    }

    {:noreply, stream_insert(socket, :clips, clip)}
  end

  defp playable_duration(socket, video_id) when is_binary(video_id) do
    Map.fetch(socket.assigns.playable, video_id)
  end

  defp playable_duration(_socket, _video_id), do: :error

  defp read_only_viewer?(%{__preview__: true}), do: true
  defp read_only_viewer?(%{__impersonating__: true}), do: true
  defp read_only_viewer?(_viewer), do: false

  defp clamp_position(position, duration) when duration > 0,
    do: position |> max(0.0) |> min(duration) |> Kernel./(1)

  defp clamp_position(position, _duration), do: max(position, 0.0) / 1

  ## -----------------------------------------------------------------------
  ## Render
  ## -----------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <ViewerLayout.viewer_layout
      organization={@organization}
      current_viewer={@current_viewer}
      impersonating_viewer={@impersonating_viewer}
      current_path="/shorts"
      theme={@theme}
      theme_preview={@theme_preview}
      flash={@flash}
    >
      <section id="shorts-page" data-shorts-page aria-labelledby="shorts-heading">
        <h1 id="shorts-heading" class="sr-only">Shorts</h1>

        <p data-shorts-live aria-live="polite" aria-atomic="true" class="sr-only"></p>
        <%!-- Visually hidden status regions sit before the full-height feed so
             their absolute positioning never extends the page's scroll height. --%>
        <p data-test="shorts-loading" aria-live="polite" class="sr-only"></p>

        <div
          :if={@total == 0}
          data-test="shorts-empty"
          class="mx-auto flex max-w-md flex-col items-center gap-3 px-6 py-24 text-center"
        >
          <.icon name="hero-film" class="size-10 opacity-70" />
          <h2 class="text-xl font-semibold">No Shorts yet</h2>
          <p class="opacity-80">Check back soon for new clips.</p>
        </div>

        <div :if={@total > 0} data-shorts-stage>
          <div
            id="shorts-feed"
            phx-hook="ShortsFeed"
            phx-update="stream"
            role="feed"
            aria-label="Shorts"
            aria-busy="false"
            tabindex="0"
            data-has-more={to_string(@has_more)}
          >
            <.clip
              :for={{dom_id, clip} <- @streams.clips}
              dom_id={dom_id}
              clip={clip}
              signed_in={not is_nil(@current_viewer)}
              favorited={MapSet.member?(@favorited_ids, clip.id)}
              watchlisted={MapSet.member?(@watchlisted_ids, clip.id)}
            />
          </div>

          <%!-- Positioned by the Shorts CSS so the full-height feed never scrolls the page. --%>
          <button type="button" data-shorts-prev aria-label="Previous clip">
            <.icon name="hero-chevron-up" class="size-6" />
          </button>
          <button type="button" data-shorts-next aria-label="Next clip">
            <.icon name="hero-chevron-down" class="size-6" />
          </button>
        </div>

        <button
          type="button"
          data-test="shorts-tap-to-play"
          hidden
          class="fixed left-1/2 top-1/2 z-20 inline-flex min-h-11 -translate-x-1/2 -translate-y-1/2 items-center gap-2 rounded-full bg-white px-6 py-3 font-semibold text-black shadow-lg focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-white"
        >
          <.icon name="hero-play" class="size-5" /> Tap to play
        </button>

        <p
          :if={@total > 0 and not @has_more}
          data-test="shorts-end"
          class="pointer-events-none fixed left-4 top-[calc(var(--shorts-offset-top,64px)+12px)] z-10 rounded-full bg-black/70 px-3 py-1 text-xs text-white"
        >
          You're all caught up.
        </p>
      </section>
    </ViewerLayout.viewer_layout>
    """
  end

  attr :dom_id, :string, required: true
  attr :clip, :map, required: true
  attr :signed_in, :boolean, required: true
  attr :favorited, :boolean, required: true
  attr :watchlisted, :boolean, required: true

  defp clip(assigns) do
    assigns =
      assigns
      |> assign(:video, assigns.clip.video)
      |> assign(:playable?, assigns.clip.access == :playable)
      |> assign(:title_id, "short-title-#{assigns.clip.id}")

    ~H"""
    <article
      id={@dom_id}
      tabindex="-1"
      data-index={@clip.index}
      data-video-id={@video.id}
      data-playback-id={@playable? && @video.mux_playback_id}
      data-orientation={AspectRatio.orientation(@video.aspect_ratio)}
      aria-posinset={@clip.index + 1}
      aria-setsize={@clip.setsize}
      aria-labelledby={@title_id}
    >
      <div data-short-media style={"aspect-ratio: #{AspectRatio.css_ratio(@video.aspect_ratio)}"}>
        <.poster video={@video} playable?={@playable?} />
        <div
          :if={@playable?}
          id={"short-player-#{@video.id}"}
          data-player-slot
          phx-update="ignore"
        >
        </div>
      </div>

      <.locked_notice :if={!@playable?} video={@video} access={@clip.access} />

      <div data-short-overlay class="w-full">
        <h2 id={@title_id} class="text-lg font-semibold">{@video.title}</h2>
        <div class="mt-3 flex flex-wrap gap-2">
          <button
            :if={@playable?}
            type="button"
            data-shorts-toggle-play
            aria-pressed="false"
            aria-label="Play"
          >
            <.icon name="hero-play" class="size-6" />
          </button>
          <button
            :if={@playable?}
            type="button"
            data-shorts-toggle-mute
            aria-pressed="false"
            aria-label="Mute"
          >
            <.icon name="hero-speaker-wave" class="size-6" />
          </button>
          <.engagement_button
            kind="favorite"
            video={@video}
            signed_in={@signed_in}
            pressed={@favorited}
            label="Favorite"
            icon="hero-heart"
          />
          <.engagement_button
            kind="watchlist"
            video={@video}
            signed_in={@signed_in}
            pressed={@watchlisted}
            label="Save to My Stuff"
            icon="hero-bookmark"
          />
        </div>
      </div>

      <div
        :if={@playable?}
        data-test={"short-error-#{@video.id}"}
        role="alert"
        hidden
        class="absolute inset-0 flex flex-col items-center justify-center gap-3 bg-black/80 p-6 text-center text-white"
      >
        <p>This clip could not be played.</p>
        <button type="button" data-shorts-retry>Retry</button>
      </div>
    </article>
    """
  end

  attr :video, :map, required: true
  attr :playable?, :boolean, required: true

  defp poster(assigns) do
    assigns = assign(assigns, :src, poster_src(assigns.video, assigns.playable?))

    ~H"""
    <img :if={@src} data-short-poster src={@src} alt={"Poster for #{@video.title}"} />
    <div
      :if={!@src}
      data-short-poster
      data-short-placeholder
      role="img"
      aria-label={"Poster for #{@video.title}"}
      class="flex size-full items-center justify-center bg-neutral-900 text-white/70"
    >
      <.icon name="hero-film" class="size-12" />
    </div>
    """
  end

  # Playable clips use the Mux poster (never smartcropped, so the frame keeps
  # its own ratio). Locked clips must not reveal the playback id, so they use
  # the operator's portrait thumbnail or a branded placeholder.
  defp poster_src(%{mux_playback_id: playback_id}, true),
    do: "https://image.mux.com/#{playback_id}/thumbnail.webp?width=720"

  defp poster_src(%{portrait_thumbnail_url: url} = video, false)
       when is_binary(url) and url != "" do
    if safe_locked_poster?(url, video.mux_playback_id), do: url, else: nil
  end

  defp poster_src(_video, false), do: nil

  # A Mux URL (any *.mux.com host) or any URL carrying the playback id would
  # reveal or derive the bearer playback id, so a locked clip falls back to
  # the branded placeholder instead.
  defp safe_locked_poster?(url, playback_id) do
    not mux_host?(url) and not contains_playback_id?(url, playback_id)
  end

  defp mux_host?(url) do
    case URI.parse(String.trim(url)) do
      %URI{host: host} when is_binary(host) ->
        host = host |> String.downcase() |> String.trim_trailing(".")
        host == "mux.com" or String.ends_with?(host, ".mux.com")

      # No scheme ("image.mux.com/...") parses without a host.
      _ ->
        Regex.match?(~r{\A(?:[a-z0-9-]+\.)*mux\.com(?:[:/?#]|\z)}i, String.trim(url))
    end
  end

  defp contains_playback_id?(_url, playback_id) when playback_id in [nil, ""], do: false

  defp contains_playback_id?(url, playback_id),
    do: String.contains?(String.downcase(url), String.downcase(playback_id))

  attr :video, :map, required: true
  attr :access, :any, required: true

  defp locked_notice(assigns) do
    assigns = assign(assigns, :cta, locked_cta(assigns.access))

    ~H"""
    <div
      data-test={"short-locked-#{@video.id}"}
      data-short-locked
      class="flex max-w-xs flex-col items-start gap-3 rounded-lg bg-black/70 p-4 text-white"
    >
      <.icon name="hero-lock-closed" class="size-6" />
      <p>{@cta.message}</p>
      <.link
        :if={@cta.href}
        navigate={@cta.href}
        class="inline-flex min-h-11 items-center rounded-full bg-white px-5 font-semibold text-black focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-white"
      >
        {@cta.label}
      </.link>
    </div>
    """
  end

  defp locked_cta({:locked, :login}),
    do: %{message: "Sign in to watch this clip.", label: "Sign in", href: ~p"/login"}

  defp locked_cta({:locked, :subscribe}),
    do: %{message: "Subscribe to watch this clip.", label: "Subscribe", href: ~p"/subscribe"}

  defp locked_cta({:locked, :payment_issue}),
    do: %{
      message: "There's a problem with your payment.",
      label: "Update payment",
      href: ~p"/account/payment-issue"
    }

  defp locked_cta(_suspended),
    do: %{message: "Your account is suspended, so clips can't be played.", label: nil, href: nil}

  attr :kind, :string, required: true
  attr :video, :map, required: true
  attr :signed_in, :boolean, required: true
  attr :pressed, :boolean, required: true
  attr :label, :string, required: true
  attr :icon, :string, required: true

  defp engagement_button(%{signed_in: false} = assigns) do
    ~H"""
    <.link
      navigate={~p"/login"}
      data-test={"short-#{@kind}-#{@video.id}"}
      aria-label={"Sign in to #{String.downcase(@label)}"}
      class={control_class()}
    >
      <.icon name={@icon} class="size-6" />
    </.link>
    """
  end

  defp engagement_button(assigns) do
    ~H"""
    <button
      type="button"
      phx-click={"toggle_#{@kind}"}
      phx-value-video-id={@video.id}
      data-test={"short-#{@kind}-#{@video.id}"}
      aria-pressed={to_string(@pressed)}
      aria-label={@label}
      class={control_class()}
    >
      <.icon name={if @pressed, do: "#{@icon}-solid", else: @icon} class="size-6" />
    </button>
    """
  end

  defp control_class do
    "inline-flex min-h-11 min-w-11 items-center justify-center rounded-full bg-black/60 text-white " <>
      "transition-colors hover:bg-black/80 focus-visible:outline-2 focus-visible:outline-offset-2 " <>
      "focus-visible:outline-white"
  end
end
