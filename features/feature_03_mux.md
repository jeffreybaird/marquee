# Task: Feature 03 — Mux Video Upload and Playback

This feature turns Marquee from an admin shell into a functioning video platform.
Operators upload videos, Mux encodes them, viewers watch them. This is the core
value proposition.

Follow all rules in CLAUDE.md — especially the Architecture Principles. Load
`.claude/mux-integration.md`, `.claude/architecture-decisions.md`,
`.claude/observability.md`, `.claude/scalability.md`, and `.claude/testing.md`.

This task has 7 parts. Do them in order. Run `mix test` after each part.

---

## Part 1: Mux Client Behaviour and Implementation

### Create the behaviour

`lib/marquee/content/mux_client_behaviour.ex`:

```elixir
defmodule Marquee.Content.MuxClientBehaviour do
  @callback create_direct_upload(map()) :: {:ok, map()} | {:error, :mux_error, term()}
  @callback get_asset(String.t()) :: {:ok, map()} | {:error, :mux_error, term()}
  @callback delete_asset(String.t()) :: :ok | {:error, :mux_error, term()}
  @callback list_assets(keyword()) :: {:ok, list(map())} | {:error, :mux_error, term()}
end
```

### Create the real client

`lib/marquee/content/mux_client.ex`:

Implements `MuxClientBehaviour`. Uses the Mux Elixir SDK (`Mux` hex package).
Reads credentials from application config:

```elixir
defp config do
  %{
    token_id: Application.fetch_env!(:marquee, :mux_token_id),
    token_secret: Application.fetch_env!(:marquee, :mux_token_secret)
  }
end
```

**Every function must:**
- Be wrapped in a `Marquee.Telemetry.with_span` with name `marquee.mux.<operation>`
- Include an idempotency key via `Marquee.Idempotency`
- Set span attributes for `marquee.service: "mux"` and the operation name
- Return `{:error, :mux_error, details}` on failure (never raise)
- Log at `info` on success and `error` on failure with structured metadata

### `create_direct_upload/1`

Creates a Mux direct upload URL. Params include:
- `cors_origin` — the org's domain (for CORS on the upload)
- `new_asset_settings` — playback policy, encoding tier, etc.

Returns `{:ok, %{upload_id: id, upload_url: url}}`.

The upload URL is what the browser sends the video file directly to. Video
bytes never pass through Marquee's servers.

### `get_asset/1`

Fetches asset details by Mux asset ID. Returns duration, resolution, status,
playback IDs, and other metadata.

### `delete_asset/1`

Deletes a Mux asset. Used when an operator deletes a video.

### Configure the client in application config

```elixir
# config/config.exs
config :marquee, :mux_client, Marquee.Content.MuxClient

# config/test.exs
config :marquee, :mux_client, Marquee.Content.MockMuxClient
```

### Create the mock

`test/support/mocks.ex` — add:

```elixir
Mox.defmock(Marquee.Content.MockMuxClient,
  for: Marquee.Content.MuxClientBehaviour)
```

### Accessing the client

All content context functions resolve the client from config:

```elixir
defp mux_client do
  Application.get_env(:marquee, :mux_client, Marquee.Content.MuxClient)
end
```

---

## Part 2: Video Upload Flow

### Content context: `create_upload_url/2`

```elixir
def create_upload_url(scope, attrs) do
  Telemetry.with_span "marquee.content.create_upload_url",
    %{"marquee.org.id" => scope.organization.id} do

    with {:ok, upload} <- mux_client().create_direct_upload(%{
           cors_origin: build_cors_origin(scope.organization),
           new_asset_settings: %{
             playback_policy: ["public"],
             video_quality: "plus"
           }
         }),
         {:ok, video} <- create_video_record(scope, attrs, upload) do
      Events.broadcast(scope, {:video_upload_initiated, video})
      {:ok, %{video: video, upload_url: upload.upload_url}}
    end
  end
end
```

### `create_video_record/3` (private)

Creates the `Video` record in the database with:
- `organization_id` from scope
- `title`, `description` from attrs
- `mux_upload_id` from the Mux upload response
- `mux_status: "waiting"` — the video hasn't been uploaded yet
- `slug` auto-generated from title

The video record exists before the upload completes. This lets the operator
see "Uploading..." status in the content list immediately.

### Video status state machine

```
waiting → preparing → ready
waiting → errored
preparing → errored
```

- `waiting` — upload URL created, file not yet sent to Mux
- `preparing` — file received by Mux, encoding in progress
- `ready` — encoding complete, playback available
- `errored` — something failed at any stage

Only Mux webhooks transition status. The operator dashboard polls or receives
live updates via PubSub.

---

## Part 3: Mux Webhook Processing

### Webhook controller

Update `lib/marquee_web/controllers/webhook_controller.ex` to handle Mux
webhooks. The controller must:

1. Read the raw request body for signature verification
2. Verify the webhook signature using the Mux webhook secret
3. Return 200 immediately
4. Enqueue an Oban job for async processing

```elixir
def mux(conn, _params) do
  with {:ok, raw_body} <- read_raw_body(conn),
       {:ok, payload} <- verify_mux_signature(raw_body, conn),
       {:ok, _job} <- enqueue_mux_webhook(payload) do
    send_resp(conn, 200, "ok")
  else
    {:error, :invalid_signature} ->
      send_resp(conn, 400, "invalid signature")
    {:error, reason} ->
      Logger.error("Mux webhook error", reason: inspect(reason))
      send_resp(conn, 500, "error")
  end
end
```

**Important:** The webhook pipeline must parse the raw body. Add a custom
body reader plug or configure the existing JSON parser to store the raw body
for signature verification.

### Enqueue with trace context

```elixir
defp enqueue_mux_webhook(payload) do
  trace_ctx = :otel_propagator_text_map.inject(:otel_ctx.get_current(), [])

  %{payload: payload, trace_context: Map.new(trace_ctx)}
  |> Marquee.Workers.MuxWebhookProcessor.new()
  |> Oban.insert()
end
```

### Mux webhook processor worker

`lib/marquee/workers/mux_webhook_processor.ex`:

```elixir
defmodule Marquee.Workers.MuxWebhookProcessor do
  use Oban.Worker,
    queue: :mux,
    unique: [period: 60, fields: [:args], keys: [:payload]]

  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  @impl true
  def perform(%Oban.Job{args: %{"payload" => payload} = args}) do
    # Restore trace context
    if ctx = args["trace_context"] do
      :otel_propagator_text_map.extract(ctx)
    end

    Logger.metadata(event_type: payload["type"])

    Tracer.with_span "marquee.worker.mux_webhook_processor" do
      handle_event(payload["type"], payload["data"])
    end
  end

  defp handle_event("video.upload.asset_ready", data) do
    # Upload complete — link the upload to the asset
    # Find video by mux_upload_id, update with mux_asset_id, set status to "preparing"
  end

  defp handle_event("video.asset.ready", data) do
    # Encoding complete
    # Find video by mux_asset_id
    # Update status to "ready"
    # Store duration, max_resolution, mux_playback_id
    # Broadcast event for live UI update
  end

  defp handle_event("video.asset.errored", data) do
    # Encoding failed
    # Find video by mux_asset_id
    # Update status to "errored"
    # Log error details
  end

  defp handle_event(type, _data) do
    Logger.debug("Unhandled Mux webhook event", type: type)
    :ok
  end
end
```

### Content context webhook handling functions

Add to the Content context:

- `link_upload_to_asset(mux_upload_id, mux_asset_id)` — called by
  `video.upload.asset_ready` handler
- `mark_video_ready(mux_asset_id, metadata)` — sets status to ready,
  stores duration/resolution/playback_id, broadcasts event
- `mark_video_errored(mux_asset_id, error_details)` — sets status to errored

Each of these must:
- Wrap in a `Telemetry.with_span`
- Broadcast an event (`{:video_ready, video}`, `{:video_errored, video}`)
- Return tagged tuples

### Register the webhook route

Ensure `router.ex` has:

```elixir
scope "/webhooks", MarqueeWeb do
  pipe_through :api
  post "/mux", WebhookController, :mux
end
```

The `:api` pipeline must NOT include CSRF protection or session handling.

---

## Part 4: Content Management LiveView (Admin)

Build out `lib/marquee_web/live/admin/content_live.ex` from its placeholder
into a functional content management page.

### Index view (`/admin/content`)

Displays a paginated list of videos for the current organization:
- Thumbnail (from Mux — `https://image.mux.com/{playback_id}/thumbnail.webp`)
- Title
- Status badge (waiting, preparing, ready, errored)
- Duration (formatted as mm:ss)
- Upload date
- Actions: Edit, Delete

Include:
- "Upload Video" button
- Search input (filter by title, `phx-change` for live filtering)
- Sort options (newest, oldest, alphabetical)

Status badges should update in real-time when Mux webhooks arrive. Subscribe
to the org's event topic in `mount/3`:

```elixir
if connected?(socket) do
  Marquee.Events.subscribe(socket.assigns.organization.id)
end
```

Handle the event:

```elixir
def handle_info({:marquee_event, {:video_ready, video}, _scope}, socket) do
  # Update the video in the list
  {:noreply, update_video_in_list(socket, video)}
end
```

### Upload modal

When "Upload Video" is clicked, show a modal with:
- Title input (required)
- Description textarea (optional)
- File input

On form submit:
1. Call `Content.create_upload_url(scope, %{title: title, description: desc})`
2. Receive `{:ok, %{video: video, upload_url: url}}`
3. Push the upload URL to a TypeScript hook that handles the file upload
4. The video appears in the list immediately with status "waiting"

The file upload is handled client-side by the `MuxUploader` hook (see Part 6).
The backend never sees the file bytes.

### Delete action

Soft-deletes the video via `Content.delete_video(scope, video)`. Also triggers
`MuxClient.delete_asset(video.mux_asset_id)` as a background job to clean up
the Mux asset.

Add a confirmation dialog before delete.

### `data-test` attributes

- `data-test="upload-btn"` — upload button
- `data-test="video-search"` — search input
- `data-test={"video-row-#{video.id}"}` — each video row
- `data-test={"video-status-#{video.id}"}` — status badge
- `data-test={"delete-video-#{video.id}"}` — delete button
- `data-test="upload-modal"` — upload modal
- `data-test="upload-form"` — upload form
- `data-test="empty-state"` — shown when no videos exist

---

## Part 5: Video Player Page (Viewer)

Build out `lib/marquee_web/live/viewer/watch_live.ex` from its placeholder.

### Architecture: Static shell with LiveView island

The watch page should be a controller-rendered page (not a full LiveView)
with a LiveView component for the interactive player area. This follows the
islands architecture principle for viewer-facing pages.

If you prefer to start with a full LiveView for simplicity, that's acceptable
for now, but add a `# TODO: Convert to static page with LiveView island`
comment at the top of the module.

### Page content

- Video title and description
- Mux Player web component (see Part 6 for the TypeScript hook)
- "Add to Watchlist" button (placeholder for Feature 06)
- "Favorite" button (placeholder for Feature 06)
- Related videos row (placeholder — can just show other org videos for now)

### Video loading

Load the video by slug or ID from the URL:

```elixir
def mount(%{"id" => id}, _session, socket) do
  org = socket.assigns.organization
  case Content.get_video(org, id) do
    {:ok, video} when video.mux_status == "ready" ->
      {:ok, assign(socket, video: video, page_title: video.title)}
    {:ok, _video} ->
      {:ok, push_navigate(socket, to: ~p"/")}  # Video not ready
    {:error, :not_found} ->
      {:ok, push_navigate(socket, to: ~p"/")}  # Video doesn't exist
  end
end
```

### Playback progress tracking

When the `MuxPlayer` TypeScript hook reports playback position, write it to
the progress buffer (not directly to Postgres):

```elixir
def handle_event("playback_progress", %{"position" => pos}, socket) do
  Engagement.update_progress(
    socket.assigns.current_scope,
    socket.assigns.video.id,
    pos
  )
  {:noreply, socket}
end
```

The `Engagement.update_progress/3` function writes to `Marquee.Buffers.ProgressBuffer`,
not to `Repo`. See `.claude/scalability.md` for the buffer pattern.

For now, a simple ETS-backed buffer with a GenServer flush every 30 seconds
is sufficient.

### Resume playback

On mount, check if there's saved progress for this user + video:

```elixir
progress = Engagement.get_progress(scope, video.id)
resume_position = if progress, do: progress.position, else: 0.0
{:ok, assign(socket, video: video, resume_position: resume_position)}
```

Pass `resume_position` to the Mux Player hook via a data attribute.

---

## Part 6: TypeScript Hooks

### `MuxUploader` hook

`assets/js/hooks/mux_uploader.ts`

Handles the direct upload to Mux from the browser. Uses the
`@mux/mux-uploader` web component or raw `fetch` with a PUT to the upload URL.

```typescript
/**
 * MuxUploader hook
 *
 * Handles direct video upload from browser to Mux.
 * Video bytes never touch Marquee's servers.
 *
 * Events received from server:
 *   - "start_upload" { upload_url: string, video_id: string }
 *
 * Events sent to server:
 *   - "upload_progress" { video_id: string, percent: number }
 *   - "upload_complete" { video_id: string }
 *   - "upload_error"    { video_id: string, error: string }
 */
const MuxUploader = {
  mounted() {
    this.handleEvent("start_upload", ({ upload_url, video_id }) => {
      const fileInput = this.el.querySelector("input[type='file']") as HTMLInputElement
      const file = fileInput?.files?.[0]
      if (!file) return

      this.uploadToMux(upload_url, file, video_id)
    })
  },

  async uploadToMux(url: string, file: File, videoId: string) {
    try {
      const xhr = new XMLHttpRequest()

      xhr.upload.addEventListener("progress", (e) => {
        if (e.lengthComputable) {
          const percent = Math.round((e.loaded / e.total) * 100)
          this.pushEvent("upload_progress", { video_id: videoId, percent })
        }
      })

      xhr.addEventListener("load", () => {
        if (xhr.status >= 200 && xhr.status < 300) {
          this.pushEvent("upload_complete", { video_id: videoId })
        } else {
          this.pushEvent("upload_error", {
            video_id: videoId,
            error: `Upload failed with status ${xhr.status}`
          })
        }
      })

      xhr.addEventListener("error", () => {
        this.pushEvent("upload_error", {
          video_id: videoId,
          error: "Network error during upload"
        })
      })

      xhr.open("PUT", url)
      xhr.send(file)
    } catch (error) {
      this.pushEvent("upload_error", {
        video_id: videoId,
        error: String(error)
      })
    }
  },

  destroyed() {
    // Cancel any in-progress upload if the component unmounts
  }
}

export default MuxUploader
```

### `MuxPlayer` hook

`assets/js/hooks/mux_player.ts`

Mounts the Mux Player web component and bridges playback events to the
LiveView server.

```typescript
/**
 * MuxPlayer hook
 *
 * Mounts the Mux Player web component and reports playback events.
 *
 * DOM attributes read:
 *   - data-playback-id: Mux playback ID
 *   - data-video-id: Marquee video ID
 *   - data-resume-position: Seconds to seek to on load
 *   - data-accent-color: Brand primary color for the player
 *
 * Events sent to server:
 *   - "playback_started"  { video_id }
 *   - "playback_progress" { video_id, position }
 *   - "playback_paused"   { video_id, position }
 *   - "playback_ended"    { video_id }
 *
 * Events received from server:
 *   - "seek_to" { position }
 */
const MuxPlayer = {
  mounted() {
    const player = this.el.querySelector("mux-player") as any
    if (!player) return

    this.player = player
    this.videoId = this.el.dataset.videoId

    // Resume playback if position is set
    const resumePos = parseFloat(this.el.dataset.resumePosition || "0")
    if (resumePos > 0) {
      player.addEventListener("loadedmetadata", () => {
        player.currentTime = resumePos
      }, { once: true })
    }

    // Report playback started
    player.addEventListener("play", () => {
      this.pushEvent("playback_started", { video_id: this.videoId })
    })

    // Report progress every 10 seconds
    this.progressInterval = setInterval(() => {
      if (!player.paused && player.currentTime > 0) {
        this.pushEvent("playback_progress", {
          video_id: this.videoId,
          position: player.currentTime
        })
      }
    }, 10000)

    // Report pause
    player.addEventListener("pause", () => {
      this.pushEvent("playback_paused", {
        video_id: this.videoId,
        position: player.currentTime
      })
    })

    // Report ended
    player.addEventListener("ended", () => {
      this.pushEvent("playback_ended", { video_id: this.videoId })
    })

    // Handle server-initiated seek
    this.handleEvent("seek_to", ({ position }) => {
      player.currentTime = position
    })
  },

  destroyed() {
    if (this.progressInterval) {
      clearInterval(this.progressInterval)
    }
  }
}

export default MuxPlayer
```

### Register hooks

Update `assets/js/hooks/index.ts`:

```typescript
import MuxUploader from "./mux_uploader"
import MuxPlayer from "./mux_player"

export const hooks = {
  MuxUploader,
  MuxPlayer,
}
```

### Load Mux Player script

Add to the root layout `<head>`:

```html
<script src="https://cdn.jsdelivr.net/npm/@mux/mux-player"></script>
```

---

## Part 7: Tests

### MuxClient tests (with Mox)

`test/marquee/content/mux_client_test.exs`

These test the Content context functions, not the Mux client itself (which
is mocked).

```elixir
test "create_upload_url returns video and upload URL" do
  org = insert(:organization)
  scope = build_scope(org, :admin)

  expect(MockMuxClient, :create_direct_upload, fn _params ->
    {:ok, %{id: "upload_123", url: "https://storage.googleapis.com/fake-url"}}
  end)

  assert {:ok, %{video: video, upload_url: url}} =
    Content.create_upload_url(scope, %{title: "My Video"})

  assert video.mux_status == "waiting"
  assert video.organization_id == org.id
  assert url =~ "googleapis.com"
end
```

### Webhook processor tests

`test/marquee/workers/mux_webhook_processor_test.exs`

Test each webhook event type:

```elixir
test "video.asset.ready updates video status and stores metadata" do
  org = insert(:organization)
  video = insert(:video, organization: org,
    mux_asset_id: "asset_123", mux_status: "preparing")

  expect(MockMuxClient, :get_asset, fn "asset_123" ->
    {:ok, %{
      duration: 125.5,
      max_stored_resolution: "1080p",
      playback_ids: [%{id: "playback_abc", policy: "public"}]
    }}
  end)

  payload = %{
    "type" => "video.asset.ready",
    "data" => %{"id" => "asset_123"}
  }

  assert :ok = perform_job(MuxWebhookProcessor, %{"payload" => payload})

  updated = Content.get_video!(org, video.id)
  assert updated.mux_status == "ready"
  assert updated.duration == 125.5
  assert updated.mux_playback_id == "playback_abc"
end

test "video.asset.errored marks video as errored" do
  # ...
end

test "processing is idempotent — same webhook twice produces same result" do
  # ...
end

test "unknown event type is handled gracefully" do
  # ...
end
```

### Content LiveView tests

`test/marquee_web/live/admin/content_live_test.exs`

- Page renders video list for the organization
- Empty state shown when no videos exist
- Videos from other organizations are not visible
- Upload button is visible for editor+ roles
- viewer_support role cannot see upload button
- Delete button triggers soft delete
- Video status updates live when event is broadcast
- Search filters video list by title
- Pagination works (if enough videos)

### Watch LiveView tests

`test/marquee_web/live/viewer/watch_live_test.exs`

- Page renders video title and player element
- Non-existent video redirects to home
- Video with status != "ready" redirects to home
- Player element has correct `data-playback-id`
- Player element has correct `data-resume-position` when progress exists
- Player element has `data-resume-position="0"` when no progress
- Video from another org returns not found

### Webhook controller tests

`test/marquee_web/controllers/webhook_controller_test.exs`

- Valid Mux webhook is accepted and job is enqueued
- Invalid signature returns 400
- Missing payload returns error

### Progress buffer tests

- `update_progress/3` writes to the buffer
- Buffer flushes write batched records to Postgres
- Multiple updates for the same user+video keep only the latest

---

## Environment Variables Needed

Add these to your dev `.env` file and Fly secrets:

- `MUX_TOKEN_ID` — from your Mux dashboard
- `MUX_TOKEN_SECRET` — from your Mux dashboard
- `MUX_WEBHOOK_SECRET` — from Mux webhook settings

For local dev testing of webhooks, use a tool like `ngrok` to expose your
local server to Mux's webhook delivery, or use the Mux CLI to forward events.

---

## Definition of Done

- [ ] `MuxClientBehaviour` and `MuxClient` implementation with all 4 operations
- [ ] Mock registered in `test/support/mocks.ex`
- [ ] `Content.create_upload_url/2` creates video record + Mux upload
- [ ] Video status state machine: waiting → preparing → ready / errored
- [ ] Webhook controller verifies signature and enqueues Oban job
- [ ] `MuxWebhookProcessor` handles asset_ready, errored, and upload_asset_ready
- [ ] Webhook processing propagates trace context from HTTP request
- [ ] Content admin page lists videos with real-time status updates
- [ ] Upload modal creates video and pushes upload URL to TypeScript hook
- [ ] `MuxUploader` TypeScript hook uploads file directly to Mux
- [ ] `MuxPlayer` TypeScript hook mounts player and reports events
- [ ] Watch page loads video with Mux Player
- [ ] Playback progress written to buffer, not directly to Postgres
- [ ] Resume playback from saved position
- [ ] Soft delete on videos triggers Mux asset cleanup job
- [ ] All context functions wrapped in OTel spans
- [ ] All external calls include idempotency keys
- [ ] Events broadcast for video_upload_initiated, video_ready, video_errored, video_deleted
- [ ] Structured logging with org_id on all operations
- [ ] All tests pass including tenant isolation and RBAC
- [ ] `data-test` attributes on all interactive elements
- [ ] `mix format`, `mix credo --strict`, `mix dialyzer` pass
- [ ] `npx tsc --noEmit` passes