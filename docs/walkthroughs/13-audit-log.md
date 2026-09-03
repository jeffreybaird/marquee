# 13 · The audit log

**Target length:** 1:45
**Audience:** owner or admin
**Pages:** `/admin/audit-log`
**Prerequisites:** an org where several changes have been made by more than
one operator, ideally including one action taken while impersonating.

## Scene 1 — Every change, recorded (0:00–0:25)

**STAGE:** `/admin/audit-log`. Header, filter row: "All actions", "All
actors", "All types" selects and the search box "Search actions or resource
ID...". A list of entries: who, what, which resource, when. An **Export CSV**
button and a **Load more** button at the bottom.

**VO:** Every create, update and delete in your organization lands here: who
did it, what changed, and when. Videos, rows, plans, viewer suspensions,
appearance saves. If you ever need to know why something changed, start here.

## Scene 2 — Filter (0:25–0:55)

**STAGE:** Open "All actors" and pick a teammate; the list narrows. Open "All
actions" and pick an update action. Open "All types" and pick videos. Type a
resource ID in the search box. Clear back to all.

**VO:** Filter by the person, by the kind of action, or by the kind of
record. Or paste a resource ID to see everything that happened to one video
or one plan.

## Scene 3 — Expand an entry (0:55–1:20)

**STAGE:** Click an update entry to expand it. The field-level diff shows
before and after values. Find an entry made during impersonation; it shows the
impersonation context alongside the actor.

**VO:** Expand an entry for the exact fields that changed, old value and new.
Actions taken while impersonating a viewer are marked as such, so support
work is never mistaken for the viewer's own.

## Scene 4 — Export, close (1:20–1:45)

**STAGE:** Click **Load more**; more entries append. Click **Export CSV**.
Flash "Export queued. You'll be notified when ready." Cut to the later flash
"Export ready. Download: …".

**VO:** Load more pages back through history. Export CSV builds a file of
whatever you've filtered and tells you when it's ready. Next: live events.

## Rough edges

- The export runs as a background job; the ready flash arrives on the next
  page load. Cut the wait.
