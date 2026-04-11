# DigitalOcean Spaces image storage

Image uploads (series covers, season covers, collection covers, custom
video thumbnails, …) go directly from the browser to a DigitalOcean
Spaces bucket via presigned PUT URLs. No image bytes touch our
Phoenix server.

This file is for operators setting up the storage layer. Application
code lives in:

- `lib/bobine/storage.ex` — the context
- `lib/bobine/storage/spaces_client_behaviour.ex` — the mockable contract
- `lib/bobine/storage/spaces_client.ex` — the real client (wraps `ex_aws_s3`)
- `lib/bobine_web/live/admin/image_upload_handlers.ex` — the shared LiveView macro
- `lib/bobine_web/components/admin_components.ex` — the `image_upload_field/1` UI
- `assets/js/hooks/spaces_uploader.ts` — the JS hook that PUTs to Spaces

## Environment variables

The app reads the following from the runtime env. In dev they can live
in `.env` (auto-loaded by `config/runtime.exs`); in prod set them as
Fly secrets.

| Variable | Required | Example | Purpose |
| --- | --- | --- | --- |
| `SPACES_ACCESS_KEY_ID` | yes (non-test) | `DO00ABCD1234EFGH5678` | Generated in the DO control panel under **API → Spaces access keys** |
| `SPACES_SECRET_ACCESS_KEY` | yes (non-test) | `abcdefg…` | The matching secret (shown once at creation time) |
| `SPACES_BUCKET` | no | `bobine` | Bucket name. Defaults to `"bobine"` (compiled default in `config.exs`) |
| `SPACES_REGION` | no | `nyc3` | Region slug |
| `SPACES_HOST` | no | `nyc3.digitaloceanspaces.com` | S3 endpoint host |
| `SPACES_PUBLIC_URL_BASE` | no | `https://cdn.bobine.io` | Override if you put a CDN in front of the bucket |

## Bucket CORS policy

The browser uploads directly to `https://<bucket>.<host>/...` via a
`PUT`, so the bucket **must** allow the operator's origins. Use the
DO control panel (Spaces → Settings → CORS) or `s3cmd`:

```json
[
  {
    "AllowedOrigins": [
      "https://*.bobine.io",
      "https://bobine.io",
      "http://localhost:4000"
    ],
    "AllowedMethods": ["PUT", "GET", "HEAD"],
    "AllowedHeaders": ["*"],
    "ExposeHeaders": ["ETag"],
    "MaxAgeSeconds": 3000
  }
]
```

Replace the origin list with whatever domains your operators use. In
dev, `http://localhost:4000` is enough.

## Bucket key layout

All uploads live under:

```
org/<organization.id>/<kind>/<uuid>.<ext>
```

Where `<kind>` is one of:

- `series_cover`
- `season_cover`
- `collection_cover`
- `video_thumbnail`

The per-org prefix keeps tenants isolated at the storage level. UUIDs
make keys unguessable and avoid collisions even when two operators
upload files with the same name.

## Presigned URL lifetime

Presigned URLs are valid for **15 minutes** by default. That's the
time window between the operator picking a file and the browser
finishing the PUT. If a user has a very large file on a slow connection
they'll need to re-pick; we can raise this in `Bobine.Storage` if
needed.

## Testing

Tests never touch real Spaces. `config/test.exs` sets
`client: Bobine.Storage.MockSpacesClient`, a Mox-defined stub. Use
`expect/3` in test setup to control what the client returns — see
`test/bobine/storage_test.exs` and
`test/bobine_web/live/admin/series_live_image_upload_test.exs` for
examples.
