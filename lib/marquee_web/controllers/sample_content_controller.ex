defmodule MarqueeWeb.SampleContentController do
  @moduledoc """
  Removes the sample/starter content seeded into a new org at signup.

  A plain controller (not a LiveView event) so the "Clear sample content"
  banner works uniformly from every admin page. Scoped to the current org and
  guarded by the admin pipeline.
  """
  use MarqueeWeb, :controller

  alias Marquee.Onboarding.StarterContent

  # Removing all sample content is content management — gate it to editors and
  # above, so read-only viewer_support members cannot.
  plug MarqueeWeb.Plugs.RequireRole, [minimum_role: :editor] when action in [:delete]

  def delete(conn, _params) do
    {:ok, counts} = StarterContent.clear(conn.assigns.current_scope)

    conn
    |> put_flash(:info, "Removed #{counts.videos} sample videos and their collections.")
    |> redirect(to: ~p"/admin")
  end
end
