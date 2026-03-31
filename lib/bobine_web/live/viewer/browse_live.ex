defmodule BobineWeb.Viewer.BrowseLive do
  use BobineWeb, :live_view

  alias Bobine.Content

  @impl true
  def mount(_params, _session, socket) do
    org = socket.assigns[:organization]

    if org do
      %{results: videos} = Content.list_videos(org, per_page: 50)

      {:ok,
       socket
       |> assign(:page_title, "Browse")
       |> assign(:videos, videos)}
    else
      {:ok,
       socket
       |> assign(:page_title, "Browse")
       |> assign(:videos, [])}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="max-w-5xl mx-auto">
        <.header>Browse</.header>

        <div :if={@videos == []} class="py-12 text-center text-base-content/60">
          <p class="text-lg">No videos available yet.</p>
        </div>

        <div :if={@videos != []} class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4 mt-6">
          <.link
            :for={video <- @videos}
            navigate={~p"/watch/#{video.id}"}
            class="group block rounded-lg overflow-hidden bg-base-200 hover:ring-2 hover:ring-primary transition"
          >
            <div class="aspect-video bg-base-300">
              <img
                :if={video.mux_playback_id}
                src={"https://image.mux.com/#{video.mux_playback_id}/thumbnail.webp?width=480&height=270"}
                alt={video.title}
                class="w-full h-full object-cover"
              />
            </div>
            <div class="p-3">
              <p class="font-medium text-sm group-hover:text-primary truncate">{video.title}</p>
            </div>
          </.link>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
