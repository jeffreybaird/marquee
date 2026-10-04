# Marquee

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

## Dev tasks

### Streaming a live video

`mix marquee.dev_live_stream` creates a live event, provisions a Mux stream, transitions it to live, and pushes a test video pattern via ffmpeg — all in one command.

**Prerequisites**

- `MUX_TOKEN_ID` and `MUX_TOKEN_SECRET` set in your environment (from [dashboard.mux.com](https://dashboard.mux.com) → Settings → API Access Tokens)
- `ffmpeg` installed (`brew install ffmpeg`)

**Usage**

```bash
# Uses the first org in the DB, picks a random video source
mix marquee.dev_live_stream

# Target a specific org by slug
mix marquee.dev_live_stream --org my-org

# Choose a video source (default: random)
mix marquee.dev_live_stream --source testsrc       # color grid with timestamp
mix marquee.dev_live_stream --source smptebars     # SMPTE color bars
mix marquee.dev_live_stream --source mandelbrot    # animated Mandelbrot fractal
mix marquee.dev_live_stream --source life          # Conway's Game of Life

# Print RTMP credentials without starting ffmpeg
mix marquee.dev_live_stream --org my-org --no-ffmpeg

# Skip Mux entirely — uses a test playback ID so UI and chat work without real video
mix marquee.dev_live_stream --org my-org --fake
```

The task walks the state machine (`draft → scheduled → live`) so PubSub broadcasts fire and any open viewer pages update in real time.

**Stopping**

Ctrl+C stops ffmpeg. The event stays in `live` status — end it via the super admin dashboard or in iex:

```elixir
event = Marquee.Repo.get_by!(Marquee.Streaming.LiveEvent, slug: "dev-stream-...")
scope = %Marquee.Accounts.Scope{organization: %{id: event.organization_id}}
Marquee.Streaming.transition_event(scope, event, "ended")
```

**Webhooks (optional)**

In production, Mux fires `video.live_stream.active` to trigger the live transition. This task does that directly, so ngrok is not required for basic testing. If you want to test the full webhook flow, expose port 4000 with ngrok and register the endpoint in your Mux dashboard under Settings → Webhooks, then set `MUX_WEBHOOK_SECRET`.

---

## Production

### OpenTelemetry → elixir_as_inf

Production releases already export traces to `/v1/traces` and Logger events at
info level and above to `/v1/logs`, using OTLP/HTTP protobuf and bearer auth.
Both signals use `service.name=marquee`. Phoenix requests, Ecto queries, Oban
jobs and the application's custom spans are instrumented. Metrics export is
not enabled: the hub currently returns `501` for `/v1/metrics`.

The production GitHub Actions workflow writes these repository settings into
the runtime `.env`, which Docker Compose passes to both app containers:

| GitHub Actions setting | Value |
| --- | --- |
| Variable `OTEL_EXPORTER_OTLP_ENDPOINT` | `https://elixir-as-inf.diviningdad.com` (base URL, no `/v1/traces` suffix) |
| Secret `OTEL_HUB_TOKEN` | Raw source token issued by the hub, without `Bearer ` |

The endpoint variable was configured on September 11, 2026. To finish activation:

1. Log into [the hub](https://elixir-as-inf.diviningdad.com) using its operator
   password (`ACCESS_PASSWORD` on the hub deployment).
2. Open [New source](https://elixir-as-inf.diviningdad.com/sources/new), create
   `marquee`, and save the token before leaving the page; it is shown only once.
   If the source already exists and you saved its active token, reuse it.
3. In [Marquee's Actions secrets](https://github.com/jeffreybaird/marquee/settings/secrets/actions),
   create repository secret `OTEL_HUB_TOKEN` with the raw token. Alternatively,
   run `gh secret set OTEL_HUB_TOKEN --repo jeffreybaird/marquee` and paste it at
   the hidden prompt. The hub's generic `OTEL_EXPORTER_OTLP_HEADERS` snippet is
   not a substitute: Marquee uses `OTEL_HUB_TOKEN` for both traces and logs.
4. Run the production `deploy` workflow from the Actions UI (or push the intended
   release to `main`). Updating a GitHub secret alone does not update running
   containers. Both OTEL settings are required at production boot, including
   the migration runner.
5. Visit Marquee and perform a normal action. Allow at least five seconds for
   export, then check the hub's `/sources` for Marquee's **Last seen**, `/logs`
   for its logs, and `/perf` for trace rollups. Open a linked trace to inspect
   its spans. Rollups may take another minute to appear.

If activation fails, a `401` from an ingest endpoint means the token is invalid
or revoked; `404` suggests a wrong base URL/path; connection failures suggest
DNS, TLS or outbound HTTPS access. The hub redirects `/` to `/login` when logged
out; it does not expose `/health`. The log exporter drops failed batches rather
than retrying, so successful source authentication alone does not prove every
batch was stored.

Dev and test leave export disabled even if these variables are present. This
setup activates the production workflow; staging is currently disabled and its
workflow would also need to forward the OTEL settings before re-enabling it.

**Create an admin user**

```bash
fly ssh console -C 'bin/marquee eval "Marquee.Release.create_admin_with_login(\"user@example.com\", \"https://your-app.fly.dev/\")"'
```

## License

Marquee original project code is licensed under the GNU Affero General Public
License version 3 only (AGPL-3.0-only). See [LICENSE](LICENSE). Third-party
components retain their own licenses; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

The source links point to https://github.com/jeffreybaird/marquee. Before deploying,
make the corresponding source accessible there without a GitHub account or
repository membership; a private repository does not provide a public source offer.
Deployments must offer users access to the corresponding source for the exact
version running, including modifications and the scripts needed to build and
install it. Publish that version before deployment and retain its source.
