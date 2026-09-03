# 04 · Series and seasons

**Target length:** 3:00
**Audience:** anyone with content management rights
**Pages:** `/admin/series`, a season page, the viewer site
**Prerequisites:** Mux configured; two short video files on disk, or at least
two Ready videos not yet in a series.

## Scene 1 — When to use a series (0:00–0:20)

**STAGE:** `/admin/series`. Panel "Series", subtitle "Group seasons and
episodes under a shared story." Sample series listed, each with "Analytics"
and Edit/Delete actions.

**VO:** Collections are shelves. A series is a story with an order: seasons,
and episodes inside each season. Viewers get next-episode playback, season
switching, and continue-watching that tracks where they are.

## Scene 2 — Create the series (0:20–0:55)

**STAGE:** Click **New Series**. Fields: Title, Description, "Cover image",
"Visible to viewers" checkbox. Title "Workshop Diaries", short description,
cover image, leave Visible checked. Save. Flash "Series saved."

**VO:** New Series. Title, description, a cover image, and whether it's
visible yet. Leave it visible if you plan to add episodes now; hide it if
you're building ahead of a launch.

## Scene 3 — Add a season (0:55–1:25)

**STAGE:** Open the series. "No seasons yet" empty state. Click **New
Season**. The name field has placeholder "Leave blank to auto-name (e.g.
‘Season 1’)". Leave it blank, keep "Visible to viewers" checked, save. Flash
"Season saved." "Season 1" appears.

**VO:** Inside the series, add a season. Leave the name blank and it's called
Season 1. Seasons can be hidden individually too, which is how you stage a
new season before it goes live.

## Scene 4 — Add episodes (1:25–2:20)

**STAGE:** Open Season 1. "No episodes yet". Two buttons: **Upload Episode**
and **Add Existing Video**. Click **Upload Episode**: sheet "Upload Episode",
"Select video files", pick both files, edit the "Episode title" inputs
("Episode 1 — The Bench", "Episode 2 — Joinery"), submit. Flash "Upload
complete. Mux is processing the video(s)." Then click **Add Existing Video**:
sheet "Add Existing Videos", tick one Ready video, confirm. Flash "Added 1
episode(s)." Reorder with the arrows so the uploaded ones come first.

**VO:** Episodes come from two places. Upload Episode sends new files straight
to Mux, the same way Content does, and each becomes an episode in order. Add
Existing Video pulls in something already in your library. Either way,
episode order is the order here, so arrange them before viewers arrive.

## Scene 5 — On the site (2:20–2:50)

**STAGE:** **View site**. Scroll to the "Sample Series: Behind the Lens" row
for comparison, then open the new series from a card (or visit `/series/<slug>`).
The series watch page: episode list, season selector, first episode ready to
play. Click the season selector.

**VO:** On the site a series gets its own watch page with the episode list
and a season switcher. When a viewer finishes an episode the next one queues
automatically.

## Scene 6 — Close (2:50–3:00)

**STAGE:** Series watch page. Hold.

**VO:** Next: building your homepage from rows.

## Rough edges

- Episodes uploaded in this scene show as Processing on the season page until
  Mux finishes. Cut the wait.
- Series analytics ("Analytics" link on each row) is covered in script 12.
