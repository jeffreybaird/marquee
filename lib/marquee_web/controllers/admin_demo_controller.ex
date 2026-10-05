defmodule MarqueeWeb.AdminDemoController do
  @moduledoc "CSRF-protected lifecycle for isolated admin demos."
  use MarqueeWeb, :controller
  alias Marquee.AdminDemo
  alias Marquee.AdminDemo.Catalog
  alias MarqueeWeb.Plugs.RateLimit

  plug :require_demo_host

  def index(conn, _params) do
    conn =
      if get_session(conn, :admin_demo_entry_key),
        do: conn,
        else: put_session(conn, :admin_demo_entry_key, :crypto.strong_rand_bytes(32))

    csrf = Plug.CSRFProtection.get_csrf_token()
    disabled = if AdminDemo.enabled?(), do: "", else: "disabled"

    hero = entry_hero()

    html(conn, """
    <!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Wanderlust TV — Explore the admin demo</title><link rel="stylesheet" href="/assets/css/app.css"></head>
    <body class="bg-slate-950 text-white min-h-screen"><div class="relative h-80 overflow-hidden"><img src="#{hero}" alt="A journey through Bali" class="h-full w-full object-cover opacity-75"><div class="absolute inset-0 bg-gradient-to-t from-slate-950 to-transparent"></div><p class="absolute top-8 left-8 font-serif text-3xl">Wanderlust TV</p></div><main class="mx-auto max-w-4xl px-8 py-12"><p class="text-amber-300 tracking-widest uppercase">Wanderlust TV</p><h1 class="font-serif text-5xl my-6">Your next adventure starts behind the scenes.</h1><p class="text-xl text-slate-300 mb-8">Explore a private travel video platform. Edit its catalog, arrange collections, and make the brand your own. Your sandbox lasts two hours.</p><form method="post" action="/demo/admin" data-test="admin-demo-entry-form"><input type="hidden" name="_csrf_token" value="#{csrf}"><button #{disabled} class="min-h-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 rounded-lg bg-amber-300 px-6 py-3 text-slate-950 font-semibold" data-test="admin-demo-start">Explore the admin demo</button></form><p class="mt-8 text-slate-400">Real short travel clips. Sample analytics. Payments, uploads, email and live broadcasts are disabled.</p><a class="inline-flex min-h-11 items-center underline focus-visible:outline focus-visible:outline-2" href="https://www.pexels.com/">Footage from Pexels</a></main></body></html>
    """)
  end

  def create(conn, _params) do
    conn = limit(conn)

    if conn.halted do
      conn
    else
      key = get_session(conn, :admin_demo_entry_key)

      if is_binary(key),
        do: finish(conn, AdminDemo.start_session(entry_key: key)),
        else: conn |> send_resp(400, "Open the demo entry page first.") |> halt()
    end
  end

  def reset(conn, _params) do
    conn = limit(conn)

    if conn.halted,
      do: conn,
      else: finish(conn, AdminDemo.reset_session(get_session(conn, :admin_demo_token)))
  end

  def exit(conn, _params) do
    token = get_session(conn, :admin_demo_token)
    if is_binary(token), do: AdminDemo.revoke_session(token)

    conn
    |> delete_session(:admin_demo_token)
    |> delete_session(:admin_demo_entry_key)
    |> delete_session(:admin_demo_live_socket_id)
    |> delete_session(:member_preview_org_id)
    |> delete_session(:member_preview_viewer_id)
    |> redirect(external: MarqueeWeb.Endpoint.url() <> "/")
  end

  defp entry_hero do
    case Catalog.load() do
      {:ok, %{clips: clips}} ->
        clip = Enum.find(clips, &String.contains?(&1["slug"], "bali")) || hd(clips)

        "https://image.mux.com/#{URI.encode_www_form(clip["mux_playback_id"])}/thumbnail.jpg?width=1600"

      _ ->
        ""
    end
  end

  defp finish(conn, {:ok, demo}) do
    conn
    |> configure_session(renew: true)
    |> put_session(:admin_demo_token, demo.token)
    |> put_session(:admin_demo_live_socket_id, "admin_demo:#{demo.session.id}")
    |> redirect(to: "/admin")
  end

  defp finish(conn, {:error, :capacity_reached}),
    do:
      conn
      |> put_resp_header("retry-after", "60")
      |> send_resp(503, "The demo is busy. Please try again shortly.")

  defp finish(conn, {:error, _}),
    do: conn |> send_resp(503, "The admin demo is unavailable. Please return to the entry page.")

  defp limit(conn) do
    limited =
      RateLimit.call(%{conn | remote_ip: rate_limit_ip(conn)},
        bucket: :admin_demo,
        limit: 3,
        key: :ip
      )

    %{limited | remote_ip: conn.remote_ip}
  end

  defp rate_limit_ip(conn) do
    trusted = Application.get_env(:marquee, :admin_demo, [])[:trusted_proxy_ip]

    with true <- not is_nil(trusted) and conn.remote_ip == trusted,
         [forwarded] <- get_req_header(conn, "x-forwarded-for"),
         {:ok, address} <- :inet.parse_strict_address(String.to_charlist(forwarded)) do
      address
    else
      _ -> conn.remote_ip
    end
  end

  defp require_demo_host(conn, _opts) do
    if AdminDemo.host?(conn.host),
      do: put_resp_header(conn, "cache-control", "private, no-store"),
      else: conn |> send_resp(404, "Not found") |> halt()
  end
end
