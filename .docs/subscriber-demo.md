# Workshop subscriber demo

The subscriber demo uses a separate, passwordless viewer for each browser session.
It requires no email confirmation or payment. Eligibility requires the
`subscriber_demo` organization feature to be exactly `true`; it does not depend on
the organization's name or slug. The included seed enables The Workshop. Operator member preview
remains a separate, read-only feature.

## Provisioning

The seeder loads the reviewed JSON manifest at
`priv/subscriber_demo/workshop_catalog.json` by default, including in a release.
JSON uses the same field names below as string keys. A trusted
`:marquee, :subscriber_demo_manifest_path` configuration can select another file;
an explicit `:marquee, :subscriber_demo_catalog` list takes precedence over files.
The manifest supports three to 24 clips, with unique slugs and metadata that
accurately describes the footage:

The included catalog contains 18 distinct woodworking shorts from Pexels, covering
measuring, cutting, drilling, planing, sanding, and finishing. Three curated
collections each contain 12 clips, with overlapping but different selections so
visitors can explore horizontal scrolling. Each entry credits its creator and links
to its source. Durations come from ready Mux assets; thumbnails use those same
playback IDs.

The hero carousel features three distinct videos from across the catalog. Each
slide links to its featured episode and the series. The former text-only
"Your subscriber demo" row is no longer seeded; reseeding retires that managed
legacy row without restoring an operator's deletion or changing unrelated rows.

```elixir
[
  %{
    slug: "reviewed-clip-slug",
    title: "Accurate clip title",
    description: "A description of what this clip actually shows.",
    mux_playback_id: "verified-public-playback-id",
    mux_asset_id: "verified-asset-id",
    duration: 134.41761,
    source_url: "https://source.example/approved-clip"
  }
  # Include at least three reviewed clips.
]
```

These are illustrative fields, not playable asset identifiers. Verify the actual
Mux stream, duration, and image before using a manifest. The seeder derives
thumbnails from the same playback ID and records the source URL in the description.
It does not upload media or contact Mux, Pexels, Stripe, or an email provider.

For local development, put the reviewed list in a local Elixir script, configure
it with `Application.put_env(:marquee, :subscriber_demo_catalog, manifest)`, then
call `Marquee.DemoSeeder.seed_subscriber_demo()`. Run that script with
`mix run /absolute/path/to/reviewed_seed.exs`.

To use the checked-in JSON directly, run
`mix run -e 'Marquee.DemoSeeder.seed_subscriber_demo() |> IO.inspect()'`.

Approved new footage can be ingested through
`Marquee.Content.MuxClient.create_asset(params, idempotency_key)`. Use a stable key
such as `subscriber-demo:the-workshop:<source-id>:v1` for each source so retries
reuse the same operation. This client calls the installed Mux SDK with the
idempotency header and OpenTelemetry span. Poll with `get_asset/1` until Mux reports
ready, then verify playback, duration, and thumbnail before recording IDs in the
reviewed manifest. Credentials belong in runtime configuration, never the JSON.

For a release, configure the same manifest and invoke
`Marquee.Release.seed_subscriber_demo()` through `bin/marquee eval`. Do not run
Mix in production. The operation returns the organization, series, videos, and
collections. Missing or invalid media returns `{:error, :media_not_configured}`
and rolls back provisioning. Repeating the seed updates the same catalog entries.

The platform homepage links to the first explicitly enabled demo organization,
ordered by creation time and ID. A fresh browser visiting that organization's
homepage starts its own private demo session and receives the catalog and demo
bar directly. The HTTP entry boundary creates this anonymous, expiring demo
identity before rendering; LiveView mounts do not create identities. Refreshing
or connecting LiveView reuses the existing valid session.

Automatic entry applies only to an explicitly enabled demo organization and an
anonymous homepage GET. Existing ordinary viewers, operators, member previews,
and viewer impersonation retain their current behavior. HEAD and prefetch
requests do not create identities. Creation uses the existing tenant and
authentication rate limits, and demo entry responses are private and uncached.
If the configured demo catalog is unavailable, entry returns 503 rather than
silently showing an empty landing page.

The explicit `/demo/subscriber` POST remains available through the browser,
tenant, and authentication rate-limit pipelines. The browser pipeline continues
to enforce CSRF protection for this and other mutating requests.

## Portfolio entry URL

The Workshop's production entry is
`https://the-workshop-marquee.jeffreybaird.com/`. A fresh visit opens the private
subscriber demo directly. The former platform URL
`https://marquee.jeffreybaird.com/?org=the-workshop` redirects to that hostname.
Locally, use `http://localhost:4000/?org=the-workshop`.

The browser retains the selected organization for subsequent navigation. Link
to the homepage, not `/demo/subscriber`, which continues to accept only POST.
The platform homepage chooses the tenant URL for the configured resolution mode.
Host-only cookies mean a browser moving from the old platform host receives its
own new demo identity on the tenant hostname.

## Session lifecycle

Demo identities expire after two hours. Token resolution rejects expired sessions,
and an event guard rechecks connected demo LiveViews before processing writes.
Account and payment pages are outside the demo. Progress and watchlists use the
ordinary viewer engagement implementation, including buffered progress and its
read overlay. A final navigation sample is sent before following an in-app link;
the link proceeds after acknowledgement or a bounded fallback.

Each session schedules tenant-scoped cleanup on Oban's bulk queue. A periodic
platform dispatcher discovers organizations with demo viewers in bounded pages
and recovers missed work, including after a demo feature is disabled. Cleanup removes demo
activity and its synthetic identity in bounded batches, preserving ordinary
viewers and other tenants.

## Verification checklist

Use separate browser profiles or cookie stores for two visitors. On desktop and
mobile, start at the platform entry, open the series, play an episode, save another
video, return home, and click the visible Continue Watching item. Confirm actual
playback resumes from the recorded position after navigation and reload. Confirm
the second visitor does not inherit the first visitor's progress or watchlist.

A test-only manifest may validate the player plumbing locally, but does not verify
the final Workshop catalog. Do not describe placeholder/test media as the delivered
portfolio content. Automated tests cover session identity, isolation, expiry,
cleanup, seed behavior, and navigation flushing; real browser playback remains an
explicit delivery check.
