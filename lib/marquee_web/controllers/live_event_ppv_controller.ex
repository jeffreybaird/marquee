defmodule MarqueeWeb.Viewer.LiveEventPpvController do
  @moduledoc """
  Handles pay-per-view checkout redirects for live events.

  POST /events/:slug/purchase — initiates a Stripe Checkout session for the
  event and redirects the viewer to the payment page.

  Viewer must be authenticated. Unauthenticated requests are redirected to
  the login page.
  """

  use MarqueeWeb, :controller

  alias Marquee.Billing
  alias Marquee.Streaming
  alias Marquee.Viewers
  alias MarqueeWeb.OrgURL

  @doc """
  POST /events/:slug/purchase

  Initiates Stripe Checkout for a pay-per-view event and redirects to the
  Stripe-hosted payment page. Requires viewer authentication.
  """
  def create(conn, %{"slug" => slug}) do
    org = conn.assigns.organization

    with {:viewer, viewer} when not is_nil(viewer) <- {:viewer, fetch_current_viewer(conn)},
         {:event, {:ok, event}} <- {:event, Streaming.get_live_event_by_slug(org, slug)},
         {:checkout, {:ok, url}} <-
           {:checkout,
            Billing.create_ppv_checkout(event, viewer, org, %{
              success_url:
                OrgURL.org_url(
                  "#{org_base_url(org)}/events/#{slug}/success?session_id={CHECKOUT_SESSION_ID}",
                  org
                ),
              cancel_url: OrgURL.org_url("#{org_base_url(org)}/events/#{slug}", org)
            })} do
      redirect(conn, external: url)
    else
      {:viewer, nil} ->
        conn
        |> put_flash(:error, "You must sign in to purchase this event.")
        |> redirect(to: ~p"/login")

      {:event, {:error, :not_found}} ->
        conn
        |> put_status(:not_found)
        |> put_view(MarqueeWeb.ErrorHTML)
        |> render(:"404")

      {:checkout, {:error, :not_pay_per_view}} ->
        conn
        |> put_status(:not_found)
        |> put_view(MarqueeWeb.ErrorHTML)
        |> render(:"404")

      {:checkout, {:error, :stripe_not_connected}} ->
        conn
        |> put_flash(:error, "Payments are not available for this event at this time.")
        |> redirect(to: ~p"/")

      {:checkout, {:error, :stripe_error, _reason}} ->
        conn
        |> put_flash(:error, "An error occurred while processing your request. Please try again.")
        |> redirect(to: ~p"/")
    end
  end

  defp fetch_current_viewer(conn) do
    case Plug.Conn.get_session(conn, :viewer_token) do
      nil -> nil
      token -> Viewers.get_viewer_by_session_token(token)
    end
  end

  defp org_base_url(org) do
    case org do
      %{custom_domain: domain} when is_binary(domain) and domain != "" ->
        "https://#{domain}"

      %{slug: slug} ->
        endpoint_config = Application.get_env(:marquee, MarqueeWeb.Endpoint, [])
        host = get_in(endpoint_config, [:url, :host]) || "localhost"

        port =
          get_in(endpoint_config, [:http, :port]) || get_in(endpoint_config, [:url, :port]) ||
            4000

        if host =~ "localhost" do
          "http://#{host}:#{port}"
        else
          "https://#{slug}.#{host}"
        end
    end
  end
end
