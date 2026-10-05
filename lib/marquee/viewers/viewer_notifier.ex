defmodule Marquee.Viewers.ViewerNotifier do
  @moduledoc """
  Email notifications for viewer accounts.
  """

  import Swoosh.Email

  alias Marquee.Mailer

  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from({"Marquee", from_address()})
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  defp from_address do
    Application.get_env(:marquee, :mailer_from, "onboarding@resend.dev")
  end

  @doc """
  Delivers a magic link sign-in email to a viewer.

  Exempt from doctest — sends email.
  """
  def deliver_magic_link(viewer, token, organization) do
    with :ok <-
           Marquee.AdminDemo.external_resource(Marquee.Viewers.Viewer, viewer.id, organization.id) do
      url = viewer_magic_link_url(token, organization)

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
  end

  @doc """
  Delivers a "you already have an account" email when a viewer
  tries to register with an email that already exists. This prevents
  email enumeration while still being helpful.

  Exempt from doctest — sends email.
  """
  def deliver_already_registered(email, organization) do
    with :ok <- Marquee.AdminDemo.external_effect(organization) do
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
  end

  defp viewer_magic_link_url(token, organization) do
    endpoint_config = Application.get_env(:marquee, MarqueeWeb.Endpoint)[:url] || []
    base_host = Keyword.get(endpoint_config, :host, "localhost")
    port = Keyword.get(endpoint_config, :port)
    scheme = Keyword.get(endpoint_config, :scheme, "http")
    port_suffix = port_suffix(scheme, port)

    host = magic_link_host(organization, base_host)
    base = "#{scheme}://#{host}#{port_suffix}/magic-link/#{token}"

    MarqueeWeb.OrgURL.org_url(base, organization)
  end

  defp magic_link_host(organization, base_host) do
    cond do
      Application.get_env(:marquee, :tenant_host_pattern) ->
        base_host

      organization.custom_domain not in [nil, ""] ->
        organization.custom_domain

      hostname_resolution?() ->
        "#{organization.slug}.#{base_host}"

      true ->
        base_host
    end
  end

  defp hostname_resolution? do
    Application.get_env(:marquee, :org_resolution, :query_param) == :hostname
  end

  defp port_suffix(_scheme, nil), do: ""
  defp port_suffix("http", 80), do: ""
  defp port_suffix("https", 443), do: ""
  defp port_suffix(_scheme, port), do: ":#{port}"
end
