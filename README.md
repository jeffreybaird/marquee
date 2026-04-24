# Bobine

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

## Dev tasks

### Streaming a live video

`mix bobine.dev_live_stream` creates a live event, provisions a Mux stream, transitions it to live, and pushes a test video pattern via ffmpeg — all in one command.

**Prerequisites**

- `MUX_TOKEN_ID` and `MUX_TOKEN_SECRET` set in your environment (from [dashboard.mux.com](https://dashboard.mux.com) → Settings → API Access Tokens)
- `ffmpeg` installed (`brew install ffmpeg`)

**Usage**

```bash
# Uses the first org in the DB, picks a random video source
mix bobine.dev_live_stream

# Target a specific org by slug
mix bobine.dev_live_stream --org my-org

# Choose a video source (default: random)
mix bobine.dev_live_stream --source testsrc       # color grid with timestamp
mix bobine.dev_live_stream --source smptebars     # SMPTE color bars
mix bobine.dev_live_stream --source mandelbrot    # animated Mandelbrot fractal
mix bobine.dev_live_stream --source life          # Conway's Game of Life

# Print RTMP credentials without starting ffmpeg
mix bobine.dev_live_stream --org my-org --no-ffmpeg

# Skip Mux entirely — uses a test playback ID so UI and chat work without real video
mix bobine.dev_live_stream --org my-org --fake
```

The task walks the state machine (`draft → scheduled → live`) so PubSub broadcasts fire and any open viewer pages update in real time.

**Stopping**

Ctrl+C stops ffmpeg. The event stays in `live` status — end it via the super admin dashboard or in iex:

```elixir
event = Bobine.Repo.get_by!(Bobine.Streaming.LiveEvent, slug: "dev-stream-...")
scope = %Bobine.Accounts.Scope{organization: %{id: event.organization_id}}
Bobine.Streaming.transition_event(scope, event, "ended")
```

**Webhooks (optional)**

In production, Mux fires `video.live_stream.active` to trigger the live transition. This task does that directly, so ngrok is not required for basic testing. If you want to test the full webhook flow, expose port 4000 with ngrok and register the endpoint in your Mux dashboard under Settings → Webhooks, then set `MUX_WEBHOOK_SECRET`.

---

## Production

**Create an admin user**

```bash
fly ssh console -C 'bin/bobine eval "Bobine.Release.create_admin_with_login(\"user@example.com\", \"https://your-app.fly.dev/\")"'
```
