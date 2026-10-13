# Shorts in the demos

The admin demo, Workshop subscriber demo, and five reusable demo organizations
offer a Shorts feed using dedicated portrait footage. The six clips in
`priv/demo_shorts/catalog.json` were reviewed on October 13, 2026. Mux reports
`9:16`; their public HLS renditions include 1080×1920 and 720×1280. Existing
landscape catalog footage and episode identities remain intact.

The travel set shows a boat ride, an ocean horizon, and a coastal rock arch.
The Workshop set shows cutting, drilling, and driving a screw into timber.
Titles describe the footage. The shared travel set also supplies the other
reusable demos; it does not claim to show their specialized subject matter.

## Provisioning existing demos

Deployment provisions missing demo content automatically after migrations and
before the traffic swap. `deploy/demo-content-bootstrap.sh` invokes the new
release's guarded `Marquee.Release.seed_missing_demo_content/0` entry point.
A seeding error fails the deployment step, leaving the previous release serving.

The guard checks durable tenant state before calling a seeder. Active existing demo
organizations receive portrait media only when their Shorts initialization
marker is absent. An explicitly enabled existing Workshop tenant receives its
original subscriber catalog only when that catalog has never been initialized.
Existing catalog identifiers, including an intentionally empty playback
allowlist or retained series, count as initialized. The deployment does not
create missing demo organizations or refresh existing catalogs, branding, or
viewer activity. Soft-deleted demo organizations are skipped. Deleted clips,
removed feed items, ordering, and disabled feed
settings remain operator choices.

The release helper starts only the temporary database and event/cache services
required by these offline operations. It does not boot the endpoint or background
job workers alongside the previous release. No Pexels search or Mux ingestion
runs during this deployment step; the original full demo seeder remains an
explicit operator operation.

For a local run of the same guarded deployment operation:

```bash
mix run -e 'Marquee.Release.seed_missing_demo_content() |> IO.inspect()'
```

For explicit portrait enrichment of existing reusable demo organizations locally:

```bash
mix run -e 'Marquee.DemoSeeder.seed_shorts() |> IO.inspect()'
```

This operation uses the reviewed local manifest. It does not ingest footage,
create missing organizations, or need Pexels credentials. The normal full demo
seeder also provisions Shorts when creating or rebuilding demo organizations.

For a manual production retry, run the guarded release operation through the
established deployment procedure:

```bash
bin/marquee eval 'case Marquee.Release.seed_missing_demo_content() do {:ok, _} -> :ok; _ -> System.halt(1) end'
```

Provision or refresh Workshop through its existing entry point:

```bash
mix run -e 'Marquee.DemoSeeder.seed_subscriber_demo() |> IO.inspect()'
# Production release:
bin/marquee eval 'Marquee.Release.seed_subscriber_demo() |> IO.inspect()'
```

New admin demo sessions receive the portrait feed. Existing private sessions keep
their edits until the visitor uses Reset demo; reset allocates a fresh private
sandbox with Shorts. `/admin/shorts` manages the feed and `/shorts` previews it.

Initial feeds are enabled with subscriber access. Subsequent provisioning
preserves edited access settings, disabled feeds, ordering, and removed items.
Workshop portrait IDs join its demo playback allowlist separately from its
long-form episodes.

## Attribution and shared assets

The manifest retains each creator's name and profile, original Pexels source,
and [Pexels license](https://www.pexels.com/license/). Preserve these links when
changing titles or descriptions. Videos refer to shared playback IDs without
owning the Mux assets; deletion, reset, and expiry must not delete shared media.
The protected asset registry retains the actual asset IDs.
