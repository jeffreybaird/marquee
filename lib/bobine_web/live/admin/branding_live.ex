defmodule BobineWeb.Admin.BrandingLive do
  @moduledoc """
  Legacy /admin/branding route. Appearance + surface colors merged into
  one page at /admin/appearance — this LiveView now redirects any
  bookmarked link there.
  """

  use BobineWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, push_navigate(socket, to: ~p"/admin/appearance")}
  end

  @impl true
  def render(assigns), do: ~H""
end
