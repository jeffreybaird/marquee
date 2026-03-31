defmodule Bobine.Viewers.ViewerNotifier do
  @moduledoc """
  Email notifications for viewer accounts.
  """

  import Swoosh.Email

  alias Bobine.Mailer

  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from({"Bobine", from_address()})
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  defp from_address do
    Application.get_env(:bobine, :mailer_from, "onboarding@resend.dev")
  end

  @doc """
  Delivers a magic link sign-in email to a viewer.

  Exempt from doctest — sends email.
  """
  def deliver_magic_link(viewer, token, organization) do
    url = viewer_magic_link_url(token)

    deliver(viewer.email, "Sign in to #{organization.name}", """

    ==============================

    Hi #{viewer.display_name || viewer.email},

    You can sign in to #{organization.name} by visiting the URL below:

    #{url}

    This link will expire in 15 minutes.

    If you didn't request this email, please ignore this.

    ==============================
    """)
  end

  @doc """
  Delivers a "you already have an account" email when a viewer
  tries to register with an email that already exists. This prevents
  email enumeration while still being helpful.

  Exempt from doctest — sends email.
  """
  def deliver_already_registered(email, organization) do
    deliver(email, "Account already exists on #{organization.name}", """

    ==============================

    Hi,

    Someone tried to register a new account on #{organization.name}
    using this email address, but you already have an account.

    If this was you, you can sign in instead by requesting a
    magic link at the login page.

    If you didn't request this, please ignore this email.

    ==============================
    """)
  end

  defp viewer_magic_link_url(token) do
    base_url = Application.get_env(:bobine, BobineWeb.Endpoint)[:url][:host] || "localhost"
    port = Application.get_env(:bobine, BobineWeb.Endpoint)[:url][:port] || 4000
    scheme = Application.get_env(:bobine, BobineWeb.Endpoint)[:url][:scheme] || "http"
    "#{scheme}://#{base_url}:#{port}/magic-link/#{token}"
  end
end
