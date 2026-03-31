defmodule BobineWeb.Viewer.HomeLive do
  use BobineWeb, :live_view

  alias Bobine.Content

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    org = socket.assigns[:organization]

    cond do
      # Super admin with no org resolved → send to super admin dashboard
      scope && scope.user && scope.user.is_super_admin && is_nil(org) ->
        {:ok, push_navigate(socket, to: ~p"/super")}

      # Authenticated user with org resolved → show org home
      org ->
        %{results: videos} = Content.list_videos(org, per_page: 20)

        {:ok,
         socket
         |> assign(:page_title, org.name)
         |> assign(:videos, videos)}

      # No org, no super admin → show generic landing
      true ->
        {:ok,
         socket
         |> assign(:page_title, "Welcome")
         |> assign(:videos, [])}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_viewer={@current_viewer} organization={@organization}>
      <div class="max-w-5xl mx-auto">
        <.header>
          {(assigns[:organization] && assigns[:organization].name) || "Welcome to Bobine"}
        </.header>

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
              <p :if={video.duration} class="text-xs text-base-content/60 mt-1">
                {format_duration(video.duration)}
              </p>
            </div>
          </.link>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp format_duration(nil), do: nil

  defp format_duration(seconds) when is_float(seconds) do
    total = round(seconds)
    mins = div(total, 60)
    secs = rem(total, 60)
    "#{mins}:#{String.pad_leading(Integer.to_string(secs), 2, "0")}"
  end
end
