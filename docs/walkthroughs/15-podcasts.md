# 15 · Podcasts

**Target length:** 3:00
**Audience:** owner or admin
**Pages:** `/admin/podcasts`, the viewer site (`/podcasts`)
**Prerequisites:** at least one plan; one audio file for a direct-upload
episode, or a public RSS feed URL for the import path.

## Scene 1 — What a show is (0:00–0:25)

**STAGE:** `/admin/podcasts`. Panel "Podcasts", subtitle "Premium audio shows
delivered through tokenized RSS feeds." Empty state "No podcasts yet" /
"Create your first show to publish audio to subscribers." Button **New
show**.

**VO:** Podcasts are subscriber-only audio. Each show gets a private RSS feed
per viewer, so they can listen in any podcast app, and you can revoke access
the moment a subscription lapses.

## Scene 2 — Create a show (0:25–1:35)

**STAGE:** Click **New show**. Form: Title, Slug, Description, Author, "Owner
email". "Source" radios: "Direct upload" and "Import from feed URL" (choosing
the second reveals "Remote feed URL"). "Access mode" radios: "Any active
subscription", "Specific tiers" (reveals "Allowed tiers" checkboxes listing
your plans), "Audio-only plan" (reveals a plan select). Fill title "Workshop
Radio", keep Direct upload, choose Specific tiers and tick the Monthly plan.
Save. Flash "Show saved." The show row: title, slug, "Direct upload · Specific
tiers", "(unpublished)" in amber.

**VO:** Title, slug, description, and the author and owner email that podcast
apps display. Source: upload episodes yourself, or import an existing feed
and let Marquee mirror it. Access mode: any subscriber, only certain plans,
or a dedicated audio-only plan for listeners who don't want video. Shows
start unpublished.

## Scene 3 — Episodes and publish (1:35–2:15)

**STAGE:** Open the show and upload one audio episode (same Mux uploader as
video); it shows as a draft until Mux reports it ready, then publishes on its
own. Back on the list click **Publish** on the show; the amber note
disappears. Note the "Sync now" button on a feed-import show if one exists.

**VO:** Add episodes by upload. Each one is a draft until the audio finishes
processing, then it publishes itself. When the show is ready, click Publish.
Imported shows sync on a schedule, or immediately with Sync now.

## Scene 4 — The listener side (2:15–2:50)

**STAGE:** Viewer profile: `/podcasts` directory, open the show page. The
"Your podcast feed" box shows the personal feed URL with a "Copy feed URL"
button. Click it. Then `/account`: the podcast feeds section with a
regenerate button per show; click it, flash "Feed URL regenerated. Update it
in your podcast app."

**VO:** Subscribers find shows under Podcasts on your site. Each gets a feed
URL that's theirs alone; copy it into any app. If a URL gets shared, they
regenerate it from their account page and the old one stops working. Deleting
a show from the admin revokes every token at once.

## Scene 5 — Close (2:50–3:00)

**STAGE:** `/admin/podcasts` list.

**VO:** Last one: your trial, and how Marquee bills you.

## Rough edges

- Delete warns "Delete this show? Active feed tokens will be revoked."
- The viewer-side directory and player are thinner than the admin; keep
  scene 4 short and avoid promising features not on screen.
