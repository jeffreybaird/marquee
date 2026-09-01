defmodule MarqueeWeb.Dev.BotAuthController do
  @moduledoc """
  Dev-only endpoint for MarqueeBot to register viewers, grant
  subscriptions, and obtain session cookies in a single request.

  Gated behind `:dev_routes` — never compiled in production.
  """

  use MarqueeWeb, :controller

  alias Marquee.Accounts
  alias Marquee.Viewers

  @doc """
  POST /dev/bot-auth

  Accepts JSON:
    {
      "email": "bot-1@prism-plus.bot",
      "display_name": "Bot 1",
      "org_slug": "prism-plus",
      "subscription_status": "active"
    }

  Finds or creates the viewer, grants the requested subscription
  status, and returns a session cookie.
  """
  def create(conn, params) do
    with {:ok, org} <- Accounts.get_organization_by_slug(params["org_slug"]),
         {:ok, viewer} <- find_or_register(org, params),
         {:ok, viewer} <- ensure_subscription(org, viewer, params["subscription_status"]) do
      token = Viewers.generate_viewer_session_token(viewer)

      conn
      |> put_session(:viewer_token, token)
      |> put_session(:live_socket_id, "viewers_sessions:#{Base.url_encode64(token)}")
      |> json(%{ok: true, viewer_id: viewer.id, email: viewer.email})
    else
      {:error, :not_found} ->
        conn |> put_status(404) |> json(%{error: "org_not_found"})

      {:error, :validation, changeset} ->
        errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)
        conn |> put_status(422) |> json(%{error: "validation", details: errors})
    end
  end

  defp find_or_register(org, params) do
    case Viewers.get_viewer_by_email(org, params["email"]) do
      nil ->
        Viewers.register_viewer(org, %{
          "email" => params["email"],
          "display_name" => params["display_name"] || params["email"]
        })

      viewer ->
        {:ok, viewer}
    end
  end

  defp ensure_subscription(_org, viewer, nil), do: {:ok, viewer}

  defp ensure_subscription(_org, %{subscription_status: status} = viewer, status)
       when status != "trial" do
    {:ok, viewer}
  end

  defp ensure_subscription(org, viewer, "trial") do
    expires = DateTime.add(DateTime.utc_now(), 30, :day)

    Viewers.set_subscription_status_with_trial(
      %{organization: org, user: nil},
      viewer,
      "trial",
      expires
    )
  end

  defp ensure_subscription(org, viewer, desired) do
    Viewers.set_subscription_status(%{organization: org, user: nil}, viewer, desired)
  end
end
