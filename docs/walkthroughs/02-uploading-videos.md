# 02 · Uploading videos

**Target length:** 3:00
**Audience:** anyone with content management rights
**Pages:** `/admin/content`, the viewer site
**Prerequisites:** Mux configured; one short video file (under two minutes) on
disk; at least one tag already exists so the tag filter bar renders (create
"Trailer" on `/admin/tags` beforehand).

## Scene 1 — The content library (0:00–0:20)

**STAGE:** `/admin/content`. Panel title "Content", subtitle "Manage videos,
thumbnails, and tags across your catalog." Search box "Search videos by
title…", "Filter by tag" pill row, and the table with columns Video, Tags,
Status, Duration, Uploaded. Sample videos show green "Ready" badges.

**VO:** Content is your video library. Every video you upload lands in this
table with its processing status, length and tags. Let's add one.

## Scene 2 — Upload (0:20–1:05)

**STAGE:** Click **Upload Video** (top right). The "Upload Videos" sheet
slides in with subtitle "Direct-to-Mux upload. Titles default from filename."
Click **Select video files**, pick the file. The sheet now shows "1 file(s)
selected. Assign a title to each video:" with the filename and a title input.
Replace the title with "Behind the scenes" and click **Upload 1 Video**.

**VO:** Click Upload Video. You can pick one file or several. Each one gets a
title, pre-filled from the filename, so fix it here rather than later. Then
upload. The file goes straight from your browser to Mux, our video host, so
it's fast and it never touches our servers.

## Scene 3 — Progress and processing (1:05–1:40)

**STAGE:** The sheet shows "Uploading 1 of 1… 43%" with a progress bar. Let it
finish. Flash: "Upload complete. Processing video...". The new row appears at
the top of the table with an amber "Processing" badge. Wait for it to flip to
green "Ready" without refreshing (it updates over a live connection). Cut the
wait if it's more than ten seconds.

**VO:** You'll see the progress bar, then the video shows up as Processing
while Mux encodes it. The badge turns to Ready on its own, no refresh needed.
Ready means it can play on your site.

## Scene 4 — Metadata and thumbnails (1:40–2:25)

**STAGE:** Click the video title. The detail view: player on the left,
"Tags" panel on the right. Click **Edit**. Fields: Title, Description,
"Portrait thumbnail (2:3)" and "Landscape thumbnail (16:9)" with their help
text "Optional — Mux will be used if empty." Type a one-line description, drop
an image on the landscape field, click **Save**. Flash "Video updated."

**VO:** Open a video to edit its details. Description shows on the watch page
and in cards. Thumbnails are optional: leave them empty and Marquee uses a
frame from the video. Upload your own if you want poster art. Portrait is used
by poster-style rows, landscape by episode rows and the hero.

## Scene 5 — Tags (2:25–2:45)

**STAGE:** In the "Tags" panel click **Add Tag**. Type "Trailer" in "Search or
create tag…" and click it. Type "Interview", click **Create "Interview"**. Both
appear as chips. Click **Back**. The row now shows both tags under the Tags
column.

**VO:** Tags are free-form labels. Pick an existing one or type a new one and
create it on the spot. Tags power the filter bar here, tag-based rows on your
homepage, and viewer filtering.

## Scene 6 — On the site (2:45–3:00)

**STAGE:** Click **View site**. Scroll to the "Recently Added" row. The new
video is there. Hover its card.

**VO:** And it's already on your site, in Recently Added. There is no separate
publish step: once a video is Ready, any row or collection that includes it
will show it.

## Rough edges

- Hitting the trial cap produces the flash "You've reached your plan's 5.0h of
  video. Upgrade in Billing to add more." Sample content does not count toward
  the cap.
- "Waiting" is a possible badge between upload and Processing. Do not narrate
  it.
- Deleting from the table asks "Are you sure you want to delete this video?"
  and soft-deletes. Out of scope for this script.
