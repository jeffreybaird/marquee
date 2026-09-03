# 06 · The hero banner

**Target length:** 3:00
**Audience:** anyone with content management rights
**Pages:** `/admin/catalog`, the viewer site
**Prerequisites:** sample content present (the seeded "Featured" hero row has
two slides); one landscape image URL for a custom background.

## Scene 1 — What the hero is (0:00–0:20)

**STAGE:** `/admin/catalog`, "Hero Carousel" section expanded. Its header row
shows the "Visible" pill and an "Auto-rotate" select. Two numbered slide
accordions: "Welcome to Marquee", "Uploading Your First Video". Below them,
"+ Add slide (2/4)".

**VO:** The hero is the full-width banner at the top of your homepage. It
holds up to four slides, each tied to a video, and it's the first thing every
viewer sees.

## Scene 2 — Edit a slide (0:20–1:20)

**STAGE:** Click the first slide to expand it. Fields with show/hide toggles:
Headline, Subheadline, "Brand Tag", Description, "Primary CTA" (placeholder
"Watch now"), "Secondary CTA" ("More info"). Then "Custom Background URL"
("Uses video thumbnail if empty"), "Title Logo URL" ("Replaces the text
headline when set"), "Channel / Studio Logo URL". Change the headline to "New
this week", turn off Subheadline, type a one-line description. Click **Save**;
"Saved" appears in the accordion header.

**VO:** Expand a slide to edit it. Headline and description default to the
video's own title and description; override either here. Each field has a
toggle so you can hide it without clearing it. The two call-to-action buttons
are "Watch now" and "More info" unless you rename them. Save, and the header
confirms it.

## Scene 3 — Artwork (1:20–1:50)

**STAGE:** Paste a URL into "Custom Background URL". Save. Point at "Title
Logo URL" and "Channel / Studio Logo URL" without filling them.

**VO:** By default the background is a frame from the video. Paste your own
image URL for something cleaner. If you have a title treatment as an image,
Title Logo replaces the text headline. Channel logo is for a small network or
studio mark.

## Scene 4 — Add, reorder, rotate (1:50–2:30)

**STAGE:** Click **+ Add slide (2/4)**. Sheet "Add Hero Slide", subtitle "Pick
an existing video or upload a new one to Mux." Tabs "From Content" and
"Upload new". On From Content pick a video; the slide appears as number 3. Expand it, use
**Up** to move it to position 1. Set "Auto-rotate" to 8s. Click the hero
"Visible" pill once to show "Hidden", then back.

**VO:** Add slide picks an existing video or uploads a new one. Up and Down
set the order. Auto-rotate advances slides on a timer, or set it to Off and
let viewers page through by hand. And the Visible toggle hides the whole hero
if you'd rather start the page with rows.

## Scene 5 — On the site (2:30–2:50)

**STAGE:** **View site**. The hero shows the reordered first slide with the
new headline and background. Wait for one auto-advance. Hover the arrows.

**VO:** On the site: your headline, your background, rotating on the timer
you set.

## Scene 6 — Close (2:50–3:00)

**STAGE:** Hold on the hero.

**VO:** Next: Appearance, where you set the colors and fonts that this whole
page inherits.

## Rough edges

- The hero form saves on change with a debounce, so "Saved" may flash before
  you click Save. Click Save anyway for the recording.
- "Replace video" and "Remove" exist per slide; show them only if time allows.
