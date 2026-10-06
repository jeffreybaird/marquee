# 07 · Appearance and branding

**Target length:** 3:30
**Audience:** owner or admin
**Pages:** `/admin/appearance`, the viewer site
**Prerequisites:** catalog already has rows (so the preset drawer is closed by
default); a logo URL ready to paste.

## Scene 1 — The page (0:00–0:25)

**STAGE:** `/admin/appearance`. Header "Appearance", subtitle "Preset, accent,
display font, and surface colors". A closed "Preset chooser" drawer with the
note "(advanced — overwrites your catalog)". Below it two columns: the form on
the left, "Preview" on the right showing a miniature of your homepage with
your org name in a faux nav.

**VO:** Appearance is where your site stops looking like a template. The
form is on the left, and everything you change shows up in the preview on the
right as you type. Save when it looks right.

## Scene 2 — Presets, and why to leave them alone (0:25–0:55)

**STAGE:** Open the "Preset chooser" drawer. The red warning: "Heads up.
Applying a preset here replaces your N existing rows with the preset's
defaults. This cannot be undone." Three cards: "Catalog Cinema", "Learning
Platform", "Creator Channel", each with a description and row count. Click one
to preview; the button reads **Overwrite with preset**. Do not click it. Close
the drawer.

**VO:** Presets are starting points: a film catalog, a course platform, a
creator channel. Each sets colors, a font, and a full set of homepage rows.
On a new empty site that's a fast start. On a site with rows already built
it replaces them, so treat this drawer as a reset button, not a theme picker.

## Scene 3 — Brand (0:55–1:50)

**STAGE:** "Brand" section. "Accent color": click the swatch and pick a color;
the text field updates and the preview's buttons and links recolor. Open
"Accent variants" briefly, then close it. "Display font" select: choose
Playfair Display; the line "The quick brown fox" re-renders in it and the
preview's hero headline changes. "Heading font" and "Body font" selects.
"Assets": paste a URL into "Logo URL". Point at "Favicon URL" and "Login
background image URL".

**VO:** Accent is your brand color. Buttons, links, focus rings and progress
bars all pull from it, and the hover and pressed shades are derived
automatically unless you set them. Display font is the editorial serif on
titles; pick one and the sample line shows it. Heading and body fonts cover
the rest of the site. Then your logo, favicon, and an optional background for
the login page.

## Scene 4 — Surface colors (1:50–2:30)

**STAGE:** Scroll to "Surface colors". Hover the "?" on "Background" to show
its hint. Change "Background" to a slightly warmer dark; the preview's page
background changes. Change "Surface" and "Text Primary". Skip the rest.

**VO:** Surface colors are the canvas underneath: page background, cards,
text. Every field has a hint on hover saying where it shows up. Most sites
only ever touch Background, Surface and Text Primary. Keep text at four and a
half to one contrast or better; the hint reminds you.

## Scene 5 — Preview and save (2:30–3:10)

**STAGE:** Click the expand button on the preview (top right of the frame).
The full-screen preview overlays the admin using the real homepage renderer.
Scroll it. Click the × ("Close full-size preview"). Click **Save appearance**.
Flash "Appearance saved." Click **View site**; the homepage now shows the new
accent, font and background.

**VO:** The expand button opens the preview full-screen, rendered by the same
code as your real homepage, so what you see is what viewers get. Close it,
save, and view the site. Changes reach viewers who already have the page open
without a reload.

## Scene 6 — Close (3:10–3:30)

**STAGE:** Viewer homepage with the new look. Hold.

**VO:** Next: connecting Stripe and creating a subscription plan, so this
site can charge for what's on it.

## Rough edges

- Color fields accept hex or `oklch(...)`. The picker writes hex.
- On an org with no catalog rows the drawer is open by default and the button
  reads "Apply preset" (non-destructive). Record on an org with rows so the
  warning is on screen.
