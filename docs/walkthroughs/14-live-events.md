# 14 · Live events

**Target length:** 4:00
**Audience:** owner or admin
**Pages:** `/admin/live-events`, the event page, the viewer site (`/events`)
**Prerequisites:** Mux configured for live streaming; OBS (or any RTMP
encoder) open; a viewer profile in a second window for chat.

## Scene 1 — Where events live (0:00–0:20)

**STAGE:** Type `/admin/live-events` (no sidebar link). Header "Live Events",
table columns Title, Slug, Status, Access, Scheduled. Button **New Live
Event**.

**VO:** Live events are scheduled streams with their own page, a countdown,
live chat, and a recording that lands in your library afterward. They're
managed from slash admin slash live-events.

## Scene 2 — Create the event (0:20–1:15)

**STAGE:** Click **New Live Event**. Header "New Live Event", subtitle
"Create a new live streaming event." Fields: Title, Slug ("auto-generated
from title"; tab out of Title to fill it), Description, "Scheduled Start",
"Estimated Duration (minutes)", "Cover Image URL", "Access Type" select with
Subscribers Only, Public, Pay Per View. Choose Pay Per View; "Price (USD)"
(placeholder 9.99) and "Access Window (hours)" (48) appear. Set price 9.99.
Click **Create Live Event**. Flash "Live event created." You land on the
event page.

**VO:** Title, and the slug fills itself. Pick a start time and rough length;
both feed the calendar file viewers can download. Access Type decides who can
watch: subscribers, anyone, or pay-per-view with a ticket price and how many
hours the ticket stays valid after the event.

## Scene 3 — Schedule and get credentials (1:15–2:10)

**STAGE:** Event page: title, slug, status pill "Draft", buttons **Schedule**
and **Cancel**. Details grid: Access, "PPV Price", "Access Window",
"Scheduled Start", "Estimated Duration". Click **Schedule**. Flash "Event
status updated to Scheduled." Pill "Scheduled"; buttons now **Go Live**,
**Cancel**, "Mark as Did Not Occur". Section "Streaming Credentials" with
"Credentials are fetched from Mux on demand and never stored in the page."
Click **Get RTMP Credentials**. Modal "RTMP Credentials" with "RTMP URL" and
"Stream Key" (blur the key), and "Regenerate Stream Key". Close.

**VO:** New events start as drafts, invisible to viewers. Schedule publishes
it to the events page with a countdown. Get RTMP Credentials fetches your
stream URL and key from Mux on demand; nothing is stored on the page. Paste
both into your encoder. If a key leaks, Regenerate replaces it.

## Scene 4 — Go live (2:10–3:10)

**STAGE:** Cut to OBS: RTMP URL and key pasted into Stream settings, click
Start Streaming. Back in the admin click **Go Live**. Pill "Live"; button
**End Stream**. Section "Live Chat Moderation" appears with "No messages
yet." Viewer window: `/events`, the event in the "Live now" section with a LIVE
badge and the player running; the viewer sends a chat message. Admin: the message appears in
moderation with **Delete** and **Ban** buttons. Click Delete on it.

**VO:** Start your encoder, then click Go Live. Viewers on the events page
see it move into Live now and the player starts. Chat runs alongside, and
moderation is right here: delete a message, or ban a viewer from the chat
for the rest of the event.

## Scene 5 — End and recording (3:10–3:45)

**STAGE:** Click **End Stream**. Pill "Ended". "Went Live" and "Ended At"
appear in the details. After Mux finishes, a "Recording" row with **View
Recording** appears; click it to land on `/admin/content` with the recording
in the table.

**VO:** End Stream closes the event. Went-live and ended times are recorded,
and once Mux finishes processing, the recording shows up in Content like any
other video, ready to drop into a row or a series.

## Scene 6 — Close (3:45–4:00)

**STAGE:** `/admin/live-events` table with the ended event.

**VO:** Next: podcasts.

## Rough edges

- Recording processing takes minutes; cut the wait or record scene 5 later.
- Delete on the event page opens a confirmation modal. Skip it.
- Viewer calendar links (.ics and Google Calendar) exist on the event card;
  mention only if time allows.
