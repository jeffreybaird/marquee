# Mux Integration

Load this file when working on video upload, playback, content management, or
Mux webhook processing.

---

## Client Architecture

### Single entry point: `StreamVane.Content.MuxClient`

All Mux API calls go through this module. No other module in the codebase may
call the Mux SDK directly.

```elixir
defmodule StreamVane.Content.MuxClient do
  @behaviour StreamVane.Content.MuxClientBehaviour

  @impl true
  def create_asset(params) do
    # Mux SDK call
  end

  @impl true
  def create_upload_url(params) do
    # Mux SDK call
  end

  @impl true
  def delete_asset(mux_asset_id) do
    # Mux SDK call
  end

  @impl true
  def get_asset(mux_asset_id) do
    # Mux SDK call
  end
end
```

### Behaviour for testability

The behaviour defines the contract. Tests swap in a mock via Mox.

```elixir
defmodule StreamVane.Content.MuxClientBehaviour do
  @callback create_asset(map()) :: {:ok, map()} | {:error, term()}
  @callback create_upload_url(map()) :: {:ok, String.t()} | {:error, term()}
  @callback delete_asset(String.t()) :: :ok | {:error, term()}
  @callback get_asset(String.t()) :: {:ok, map()} | {:error, term()}
end
```

### Accessing the client

Always resolve the client module from config so tests can inject the mock:

```elixir
defp mux_client do
  Application.get_env(:stream_vane, :mux_client, StreamVane.Content.MuxClient)
end
```

---

## Video Schema Conventions

### Stored Mux identifiers

The `Video` schema stores these Mux-specific fields:

| Field              | Type     | Purpose                                      |
|--------------------|----------|----------------------------------------------|
| `mux_asset_id`     | `string` | The Mux asset ID (e.g. `"aB1cD2eF3g"`)      |
| `mux_playback_id`  | `string` | The public playback ID for streaming          |
| `mux_upload_id`    | `string` | The direct upload ID (nullable, temporary)    |
| `mux_status`       | `string` | Asset status: `waiting`, `preparing`, `ready`, `errored` |
| `duration`         | `float`  | Duration in seconds, set when asset is ready  |
| `max_resolution`   | `string` | e.g. `"1080p"`, set from Mux asset metadata  |

### Never reconstruct Mux URLs from raw strings

Always use the stored `mux_playback_id` with the Mux Player component. Never
build URLs by string concatenation.

```elixir
# ✅ CORRECT — pass playback ID to the player component
<.mux_player playback_id={@video.mux_playback_id} />

# ❌ WRONG — constructing the URL manually
<video src={"https://stream.mux.com/#{@video.mux_playback_id}.m3u8"} />
```

---

## Upload Flow

The video upload flow uses Mux direct uploads:

1. Operator clicks "Upload Video" in the dashboard
2. Backend calls `MuxClient.create_upload_url/1` → returns a signed upload URL
3. Frontend uploads the file directly to Mux (never through our server)
4. Mux sends a `video.upload.asset_ready` webhook when processing is complete
5. The `MuxWebhookProcessor` Oban worker updates the video's status and metadata

### Important: video bytes never pass through StreamVane

The upload goes directly from the browser to Mux. Our server only brokers the
upload URL. This keeps our bandwidth costs zero for video transfer.

---

## Webhook Processing

### Inbound endpoint: `/webhooks/mux`

```elixir
# In router.ex
scope "/webhooks" do
  pipe_through :webhook  # no CSRF, no session, raw body parsing
  post "/mux", WebhookController, :mux
end
```

### Signature verification

Every inbound Mux webhook must be verified using the webhook signing secret
before processing. Reject unverified payloads with a `400` response.

### Async processing via Oban

The controller verifies the signature and immediately enqueues an Oban job.
It does not process the webhook synchronously.

```elixir
def mux(conn, params) do
  with :ok <- verify_mux_signature(conn) do
    %{payload: params}
    |> StreamVane.Workers.MuxWebhookProcessor.new()
    |> Oban.insert()

    send_resp(conn, 200, "ok")
  else
    {:error, :invalid_signature} -> send_resp(conn, 400, "invalid signature")
  end
end
```

### Key webhook events to handle

| Mux Event                        | Action                                         |
|----------------------------------|-------------------------------------------------|
| `video.upload.asset_ready`       | Link upload to asset, set status to `preparing` |
| `video.asset.ready`              | Set status to `ready`, store duration/resolution |
| `video.asset.errored`            | Set status to `errored`, log error details      |
| `video.asset.deleted`            | Soft-delete or clean up the video record        |
| `video.asset.live_stream_completed` | Convert live recording to VOD asset          |

### Idempotency

The worker must be idempotent. Mux may deliver the same webhook more than once.
Use the Mux event ID or asset ID + event type as an Oban unique key.

---

## Environment Variables

| Variable           | Required | Purpose                    |
|--------------------|----------|----------------------------|
| `MUX_TOKEN_ID`     | Yes      | Mux API access token ID    |
| `MUX_TOKEN_SECRET` | Yes      | Mux API access token secret |
| `MUX_WEBHOOK_SECRET` | Yes    | Webhook signature verification |

These live in Fly secrets and GitHub Actions secrets. Never in source code.

---

## Testing Mux Features

Use `Mox` to mock the `MuxClientBehaviour`. Never make real Mux API calls in tests.

```elixir
import Mox

setup :verify_on_exit!

test "create_video calls Mux and persists the video" do
  org = insert(:organization)

  expect(MockMuxClient, :create_upload_url, fn _params ->
    {:ok, "https://storage.googleapis.com/mux-uploads/fake-url"}
  end)

  assert {:ok, url} = Content.create_upload_url(org, %{title: "My Video"})
  assert url =~ "mux-uploads"
end
```

For webhook processing tests, build the payload manually and pass it directly
to the Oban worker's `perform/1` function.
