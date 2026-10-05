defmodule MarqueeWeb.Admin.DemoLibraryLive do
  @moduledoc "Approved travel clips and immutable source attribution for a private admin sandbox."
  use MarqueeWeb, :live_view
  alias Marquee.AdminDemo
  alias Marquee.AdminDemo.Catalog

  def mount(_params, _session, socket) do
    with :ok <- AdminDemo.authorize(socket.assigns.current_scope, :content_edit),
         true <- not is_nil(socket.assigns.current_scope.admin_demo_session_id),
         {:ok, manifest} <- Catalog.load() do
      {:ok, assign(socket, clips: manifest.clips, page_title: "Travel library")}
    else
      _ -> {:ok, redirect(socket, to: "/admin")}
    end
  end

  def handle_event("add_clip", %{"slug" => slug}, socket) do
    case AdminDemo.add_sample_clip(socket.assigns.current_scope, slug) do
      {:ok, _} -> {:noreply, put_flash(socket, :info, "Clip added to your private catalog.")}
      _ -> {:noreply, put_flash(socket, :error, "This clip cannot be added.")}
    end
  end

  def render(assigns) do
    ~H"""
    <MarqueeWeb.Components.AdminLayout.admin_layout
      current_path="/admin/demo/library"
      organization={@organization}
      current_user={@current_user}
      flash={@flash}
    >
      <h1 class="font-display text-3xl">Travel library</h1>
      <p class="my-4">
        Real short travel clips from Pexels. Add an approved clip to your private catalog.
      </p>
      <div class="grid md:grid-cols-3 gap-6">
        <article :for={clip <- @clips} class="bg-admin-surface rounded-xl p-4">
          <img
            src={"https://image.mux.com/#{clip["mux_playback_id"]}/thumbnail.jpg?width=480"}
            alt={clip["title"]}
            class="rounded-lg aspect-video object-cover"
          />
          <h2 class="text-xl my-3">{clip["title"]}</h2>
          <p>{clip["description"]}</p>
          <p class="text-sm my-3">
            <a
              href={clip["source_url"]}
              target="_blank"
              rel="noopener noreferrer"
              class="inline-flex min-h-11 items-center rounded px-2 underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2"
            >
              Pexels source
            </a>
            ·
            <a
              href={clip["creator_url"]}
              target="_blank"
              rel="noopener noreferrer"
              class="inline-flex min-h-11 items-center rounded px-2 underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2"
            >
              {clip["creator_name"]}
            </a>
            ·
            <a
              href={clip["license_url"]}
              class="inline-flex min-h-11 items-center rounded px-2 underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2"
            >
              License
            </a>
          </p>
          <button
            phx-click="add_clip"
            phx-value-slug={clip["slug"]}
            data-test={"sample-clip-#{clip["slug"]}"}
            class="min-h-11 rounded-lg bg-admin-accent text-admin-on-accent px-4 py-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2"
          >
            Add to catalog
          </button>
        </article>
      </div>
    </MarqueeWeb.Components.AdminLayout.admin_layout>
    """
  end
end
