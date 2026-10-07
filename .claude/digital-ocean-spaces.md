# DigitalOcean Spaces image storage

Image uploads (series covers, season covers, collection covers, custom
video thumbnails, …) go directly from the browser to a DigitalOcean
Spaces bucket via presigned PUT URLs. No image bytes touch our
Phoenix server.

This file is for operators setting up the storage layer. Application
code lives in:

- `lib/marquee/storage.ex` — the context
- `lib/marquee/storage/spaces_client_behaviour.ex` — the mockable contract
- `lib/marquee/storage/spaces_client.ex` — the real client (wraps `ex_aws_s3`)
- `lib/marquee_web/live/admin/image_upload_handlers.ex` — the shared LiveView macro
- `lib/marquee_web/components/admin_components.ex` — the `image_upload_field/1` UI
- `assets/js/hooks/spaces_uploader.ts` — the JS hook that PUTs to Spaces

## Environment variables

The app reads the following from the runtime env. In dev they can live
in `.env` (auto-loaded by `config/runtime.exs`). In prod they are GitHub
Actions secrets (`SPACES_ACCESS_KEY_ID`, `SPACES_SECRET_ACCESS_KEY`) and vars
(the rest), written into the deploy `.env` by `deploy.yml` and `rollback.yml`.
An empty value is treated as unset (see `.claude/deployment.md`).

| Variable | Required | Example | Purpose |
| --- | --- | --- | --- |
| `SPACES_ACCESS_KEY_ID` | yes (non-test) | `DO00ABCD1234EFGH5678` | Generated in the DO control panel under **API → Spaces access keys** |
| `SPACES_SECRET_ACCESS_KEY` | yes (non-test) | `abcdefg…` | The matching secret (shown once at creation time) |
| `SPACES_BUCKET` | no | `marquee` | Bucket name. Defaults to `"marquee"` (compiled default in `config.exs`) |
| `SPACES_REGION` | no | `nyc3` | Region slug |
| `SPACES_HOST` | no | `nyc3.digitaloceanspaces.com` | S3 endpoint host |
| `SPACES_PUBLIC_URL_BASE` | no | `https://cdn.marquee.io` | Override if you put a CDN in front of the bucket |

## Bucket CORS policy

The browser uploads directly to `https://<bucket>.<host>/...` via a
`PUT`, so the bucket **must** allow the operator's origins. `SpacesClient`
signs URLs in virtual-hosted style (`virtual_host: true`) precisely so
the preflight request host matches the bucket's CORS surface — path-style
URLs will not get CORS headers back and the browser fires a bare
"Network error during upload." Use the DO control panel
(Spaces → Settings → CORS) or `s3cmd`:

```json
[
  {
    "AllowedOrigins": [
      "https://*.marquee.io",
      "https://marquee.io",
      "http://localhost:4000",
      "http://*.localhost:4000"
    ],
    "AllowedMethods": ["PUT", "GET", "HEAD"],
    "AllowedHeaders": ["*"],
    "ExposeHeaders": ["ETag"],
    "MaxAgeSeconds": 3000
  }
]
```

Replace the origin list with whatever domains your operators use.

**Dev:** the admin dashboard resolves tenants by subdomain, so in dev
you're hitting `http://<org-slug>.localhost:4000`, not bare
`http://localhost:4000`. The CORS allowlist has to include the
subdomain form or every upload will fail with
"Network error during upload." If your bucket provider doesn't accept
`http://*.localhost:4000` (DO Spaces sometimes rejects wildcards on
non-TLD hosts), fall back to listing each org slug explicitly or point
dev uploads at a dev-only bucket whose CORS is `"*"`.

**Debugging a CORS failure:** open DevTools → Network, retry the
upload, find the OPTIONS preflight to
`https://<bucket>.nyc3.digitaloceanspaces.com/...`. Check the request's
`Origin` header against the bucket's `AllowedOrigins`. If the response
is missing `Access-Control-Allow-Origin`, the bucket rejected the
preflight — update the policy above.

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
they'll need to re-pick; we can raise this in `Marquee.Storage` if
needed.

## Testing

Tests never touch real Spaces. `config/test.exs` sets
`client: Marquee.Storage.MockSpacesClient`, a Mox-defined stub. Use
`expect/3` in test setup to control what the client returns — see
`test/marquee/storage_test.exs` and
`test/marquee_web/live/admin/series_live_image_upload_test.exs` for
examples.
