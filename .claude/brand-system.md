# Brand System

This file is the authoritative reference for all viewer-facing frontend work
on Bobine. Every stage prompt references this file. Before writing any code,
read this file in full. Then read the existing codebase to understand its
conventions before placing or naming anything.

---

## Identity

Bobine is a multi-tenant SaaS OTT white-label video streaming platform.
Name: French for "film reel/spool." Nod to Rochester NY's Kodak heritage.

Aesthetic: warm French cinema — Rohmer palette, Nouvelle Vague typography.
The viewer should feel like they have entered a trusted, curated, beautiful
independent cinema. Not a tech product. Not an algorithmic recommendation
engine. Not an aggressive upsell machine.

Dream customer: Dropout.tv. Primary competitors: Uscreen, Muvi One.

---

## Stack

- Elixir / Phoenix Framework
- Phoenix LiveView (server-rendered, real-time patches)
- Tailwind CSS v4 + daisyUI v5
- Alpine.js for client-only UI state
- Phoenix.LiveView.JS for server-aware transitions
- LiveView Hooks for complex JS behaviors (carousels, animations)
- Heroicons (already bundled)
- Mux for video
- Two font sources: Google Fonts (per-tenant, curated allowlist) and system
  fallbacks. Custom font upload is not supported.

---

## Codebase conventions — discover before building

Before creating any file or module, read the existing codebase to understand:
- How LiveView modules are named and where they live
- How function components are organized and imported
- How the router is structured and what pipe_throughs exist
- How Ecto schemas and context modules are organized
- What layouts exist and how they are applied
- How authentication and tenant resolution currently work

Follow existing conventions exactly. Do not introduce new organizational
patterns unless none exist for the type of thing you are building.

---

## Three tenant archetypes

Each organization selects one of three presets on onboarding. The preset
sets defaults for row layout, card variants, accent color, and display font.
Operators can customize from those defaults.

**Catalog Cinema** — films and TV, like Peacock or Criterion Channel.
Lean-back browsing. Poster artwork is primary. Discovery is ambient.
Default accent: warm ochre `oklch(0.72 0.14 68)`.
Default display font: Cormorant Garamond.
Default card: poster portrait (2:3).

**Learning Platform** — structured courses, like Skillshare or Coursera.
Lean-forward, goal-oriented. Completion percentage is the primary UI signal.
Default accent: cool blue `oklch(0.62 0.18 250)`.
Default display font: DM Serif Display.
Default card: progress course (16:9 with prominent progress bar).

**Creator Channel** — individual creator content, like Pragmatic Programmers.
Creator identity is the primary navigation unit. Content is episodic.
Default accent: warm violet `oklch(0.68 0.20 320)`.
Default display font: Playfair Display.
Default card: landscape episode (16:9).

---

## Color system — OKLCH only

All colors are CSS custom properties. Use semantic token class names in
all Tailwind utilities. Never use hardcoded hex, rgb, or raw oklch values
in templates or component files.

### Surface tokens
- `bg-bg` — page background, warm espresso dark `oklch(0.12 0.018 48)`
- `bg-surface` — cards, panels `oklch(0.17 0.016 48)`
- `bg-elevated` — inputs, raised elements, dropdowns `oklch(0.22 0.014 48)`
- `bg-overlay` — modals, popovers `oklch(0.27 0.012 48)`

### Border tokens
- `border-border` — standard `oklch(0.30 0.012 48)`
- `border-border-subtle` — light dividers `oklch(0.22 0.010 48)`
- `border-border-strong` — emphasis `oklch(0.40 0.015 48)`

### Text tokens
- `text-text-primary` — warm cream `oklch(0.93 0.018 82)`
- `text-text-secondary` — `oklch(0.72 0.022 65)`
- `text-text-muted` — metadata, labels `oklch(0.50 0.016 55)`
- `text-text-disabled` — `oklch(0.35 0.010 50)`

### Accent tokens — tenant-overridable
- `bg-accent` / `text-accent` — primary brand color
- `bg-accent-hover` — hover state
- `bg-accent-active` — active/pressed state
- `bg-accent-subtle` — tinted accent background
- `text-accent-text` — text on accent backgrounds `oklch(0.95 0.02 82)`

### Fixed tokens — never tenant-overridden
- `bg-secondary` — deep burgundy `oklch(0.40 0.14 18)`
- `bg-success` — `oklch(0.62 0.17 145)`
- `bg-warning` — `oklch(0.80 0.15 80)`
- `bg-error` — `oklch(0.58 0.22 25)`

### Multi-tenant theming architecture
Tenant overrides apply to: `--color-accent`, `--color-accent-hover`,
`--color-accent-active`, `--color-accent-subtle`, and `--font-display`.
Applied via a `data-tenant` attribute on the `<html>` element, with
tenant-specific values injected as an inline `<style>` block in the root
layout. Inline injection is required for zero-latency application — no
network request before styles apply.

---

## Typography — four roles, two sources

### The four roles
- `font-display` — editorial serif for titles, collection names, hero headlines
- `font-body` — warm readable serif for synopses, curator notes, long-form text
- `font-ui` — humanist sans-serif for navigation, buttons, labels, form elements
- `font-mono` — monospace for year, duration, episode codes, technical metadata

### Usage rules
- Display: `tracking-tighter` at large sizes, `tracking-tight` at medium,
  always `leading-tight`. Never `font-bold` — use `font-semibold` maximum.
- Body: `leading-relaxed` (1.6), `text-base` minimum size.
- UI: sentence case always. `tracking-wide` only on uppercase labels.
- Mono: `text-xs` for metadata, `text-text-muted` color by default.

### Two font sources

**Source 1 — Google Fonts (per-tenant, curated allowlist only):**
Tenants select one family for their display font from the approved list.
Injection uses the print/onload pattern to avoid render-blocking, with a
noscript fallback. Always include `dns-prefetch`, `preconnect`, and
`preload as="style"` before the stylesheet link.

Approved display fonts: Cormorant Garamond, Playfair Display, DM Serif
Display, Libre Baskerville, Bodoni Moda.
Approved body fonts: Lora, Merriweather, Source Serif 4, Spectral, EB Garamond.
Approved UI fonts: DM Sans, Inter, Nunito Sans, Outfit, Plus Jakarta Sans.
Approved mono fonts: DM Mono, Fira Code, JetBrains Mono, IBM Plex Mono.

**Source 2 — System fallbacks (always present as CSS variable defaults):**
- Display: `'Georgia', 'Times New Roman', serif`
- Body: `'Palatino Linotype', 'Book Antiqua', Georgia, serif`
- UI: `system-ui, -apple-system, 'Segoe UI', sans-serif`
- Mono: `'Menlo', 'Monaco', 'Cascadia Code', monospace`

Custom font upload is not supported. Enterprise tenants requiring
proprietary typefaces are handled via contract.

---

## Animation system

### Easing curves
- Enter: `cubic-bezier(0.0, 0.0, 0.2, 1)` — quick deceleration
- Exit: `cubic-bezier(0.4, 0.0, 1.0, 1)` — gradual acceleration
- Standard: `cubic-bezier(0.4, 0.0, 0.2, 1)` — on-screen movement
- Spring: `cubic-bezier(0.175, 0.885, 0.32, 1.275)` — sparingly
- Cinematic: `cubic-bezier(0.25, 0.46, 0.45, 0.94)` — hero reveals

### Duration scale
- Instant: 100ms — micro-interactions
- Fast: 150ms — hover states
- Normal: 250ms — overlays, dropdowns
- Moderate: 350ms — panel slides
- Slow: 500ms — page-level transitions
- Cinematic: 700ms — hero and Ken Burns

### Rules
- Only animate `transform` and `opacity`. Never animate layout properties
  (width, height, margin, padding, top, left).
- Asymmetric timing: enter faster (~200ms) than exit (~350–400ms).
- Stagger children at 50ms intervals, capped at 400ms total.
- Always respect `prefers-reduced-motion: reduce` — disable all transitions
  globally in app.css.
- Skeletons use a shimmer sweep keyframe at 1.5s intervals.
- Use `Phoenix.LiveView.JS` for show/hide tied to server events.
- Use Alpine.js `x-show` + `x-transition` for client-only UI state.
- Use LiveView Hooks for complex JS: carousels, stagger reveal,
  infinite scroll.

---

## Six card variants

Cards are the atomic unit of the UI. Each is a self-contained function
component that enforces its own aspect ratio, data surface, and hover
behavior. The card's layout footprint never changes on hover — only
overlay opacity transitions.

### Poster Portrait — aspect ratio 2:3
Cinema browsing. Matches movie poster conventions. Image is primary;
title and metadata appear in a hover overlay from the bottom. Optional
progress bar (3px, accent color) at the absolute bottom edge.
Compatible rows: hero, popularity, tags, preferences, editorial spotlight.

### Landscape Episode — aspect ratio 16:9
Series and course episodes. Episode/lesson number badge top-left.
Duration badge top-right. Both badges always visible. Hover reveals
play button. Progress bar at bottom. Below-card metadata: title and
series/episode context.
Compatible rows: series, continue watching, preferences, recently added.

### Creator Identity — aspect ratio 1:1
Creator channel browsing. Creator portrait fills the card. Name and
content count below the card. Hover reveals a "View Channel" pill overlay.
Compatible rows: creator showcase.

### Collection Editorial — aspect ratio 3:2
Curated collections. Permanent gradient overlay at bottom (always visible).
Collection name in display font always visible. Curator note fades in on
hover. Film count in monospace above the title.
Compatible rows: hero, editorial spotlight.

### Progress Course — aspect ratio 16:9 image + below-card metadata
Learning platforms. Completion percentage badge always visible top-right
(turns success color at 100%). Play button appears on hover. Below the
image: title, instructor, lesson progress string, and a labeled progress
bar (thicker than other cards — 6px).
Compatible rows: continue watching, series, preferences.

### Minimal List Item — horizontal layout
Search results and compact views. Small fixed thumbnail (portrait) on
the left. Title, metadata, and synopsis on the right. Chevron appears
on hover. Entire row highlights on hover.
Compatible rows: search results, episode lists.

### Skeleton variants
Every card variant has a corresponding skeleton. Skeletons match the
exact outer dimensions of the card they replace. They use a shimmer
gradient sweep animation. Warm-toned shimmer: `via-white/[0.04]`.

### Compatibility matrix

| Card | hero | popularity | tags | prefs | series | continue-watching | creator-showcase | editorial-spotlight |
|---|---|---|---|---|---|---|---|---|
| poster_portrait | ✓ | ✓ | ✓ | ✓ | — | — | — | ✓ |
| landscape_episode | — | — | ✓ | ✓ | ✓ | ✓ | — | ✓ |
| creator_identity | — | — | — | ✓ | — | — | ✓ | — |
| collection_editorial | ✓ | — | — | — | — | — | — | ✓ |
| progress_course | — | — | ✓ | ✓ | ✓ | ✓ | — | — |
| minimal_list_item | — | — | — | — | ✓ | — | — | — |

---

## Row types

Rows are horizontal building blocks composed from card variants.
A page is an ordered list of rows. Rows declare which card variants
they accept — this is the only composition constraint.

### Hero Image Row
Full-width cinematic billboard. Always occupies position 0 in any layout.
60–70vh height. Background image with dual gradient overlays: bottom-to-top
from page background color, and left-to-right from page background color.
Content block left-aligned: curator byline, title in display font, synopsis
in body font, two CTA buttons. No card component — uses its own layout.
Ken Burns slow zoom on the background image.

### Content Row
Standard horizontal carousel. Handles: preferences, tags, popularity,
recently added. Row header with title and optional "See all →" link.
Arrow buttons appear on desktop hover, hidden on mobile. Drag-to-scroll
with momentum. Snap scrolling. Hidden scrollbar. Stagger reveal on mount.
Compatible cards: poster portrait, landscape episode, progress course.

### Continue Watching Row
Identical structure to content row with two additions: a dismiss (×)
button per card (top-right, visible on card hover), and a time-remaining
label below each card. Never rendered when items list is empty — this
rule is absolute. Cannot be removed from layout configuration.
Compatible cards: landscape episode, progress course.

### Series Row
Same structure as content row. Episode items are sequential. The current
episode (actively in progress) is visually distinguished with an accent
ring. Compatible cards: landscape episode, progress course, minimal list item.

### Creator Showcase Row
Same structure as content row with wider gap between cards. No "See all"
link by default — creator showcase is curated. Only compatible with
creator identity cards.

### Editorial Spotlight Row
One wide collection editorial card followed by 2–3 standard poster portrait
cards in the same scroll container. The editorial card dominates visually.

### Carousel behavior (all scrollable rows)
Drag-to-scroll with momentum decay (velocity × 0.92 per frame until < 0.5).
Touch support with passive listeners. Arrow buttons scroll by ~75% of
container width. Scroll position preserved across LiveView patches in the
hook's `updated()` callback.

### Stagger reveal
On mount, each card child starts at `opacity: 0` and `translateY: 12px`,
then transitions to visible with 50ms stagger between items, capped at
400ms total. Disabled when `prefers-reduced-motion` is set.

---

## Preset system

### Data structure
Each preset defines:
- Display name and description
- Default accent color (all four variants: base, hover, active, subtle)
- Default display font (from the Google Fonts allowlist)
- Ordered list of homepage rows, each with: row type, default card variant,
  and position index

### Catalog Cinema defaults
Row order: hero → continue watching (landscape episode) → popularity
(poster portrait) → editorial spotlight → tags (poster portrait) →
preferences (poster portrait)

### Learning Platform defaults
Row order: hero → continue watching (progress course) → series
(progress course) → popularity (progress course) → tags (landscape episode)

### Creator Channel defaults
Row order: hero → creator showcase → continue watching (landscape episode)
→ series (landscape episode) → popularity (landscape episode)

### Operator configuration
Operators adjust their layout at a settings page. They can:
- Select a preset (resets rows to preset defaults, with confirmation)
- Reorder rows (up/down controls — no drag-and-drop required at MVP)
- Change the card variant for any row (constrained to compatible variants)
- Set their accent color (oklch string with live preview swatch)
- Set their display font (dropdown of approved Google Fonts)

Guard rails enforced at the data layer:
- Incompatible card/row combinations are rejected
- Minimum 2 rows required
- Continue watching row cannot be deleted (only hidden)

### Live propagation
Layout changes broadcast via PubSub to all active viewer sessions for
that organization. Viewer pages update without requiring a page refresh.

---

## Page surfaces

### Viewer homepage
Assembled from the organization's configured row layout. Rows load
asynchronously — skeleton states display while data fetches. New viewers
(no watch history) see a welcome state instead of an empty continue
watching row. Returning users see continue watching as the first or second
row. Layout updates received via PubSub rebuild the row list live.

### Auth flow
Three pages sharing a minimal layout (no navigation, no footer):
landing page, login, and registration.

Landing: full-viewport, atmospheric background (blurred/darkened backdrop
from org content), org logo centered, headline and subheadline from org
configuration, two CTAs (get started, sign in).

Login: centered form card, org logo above, email + password with
show/hide toggle, "forgot password" link, primary sign-in button,
social login option, link to registration. Auto-focus email on mount.
Error messages are specific ("No account found with that email") not
generic ("Authentication failed").

Registration: same card structure, step indicator, password strength
indicator, link back to login.

### Browse and discovery
Sticky filter bar with horizontal genre pills. Active genre highlighted
with accent color. Content grid adapts from 2 columns (mobile) to 6
(wide desktop). Card variant determined by org's browse default setting.
Infinite scroll loads additional items without replacing the grid.
Stagger reveal on initial load and on genre change.

### Search
Full-width search input, auto-focused on mount. Results update live
with 300ms debounce. Empty query state shows curated suggestions.
Results grouped by type (films, series, collections). No-results state
includes suggestions. Uses minimal list item card for results.

### Content detail modal
Triggered from any card. Backdrop image at top with gradient fade into
the panel. Title, metadata, genre tags, synopsis, director/cast, two
CTAs (watch, add to list). Enter/exit with scale + opacity transition.
Closes on backdrop click and Escape key.

### Navigation
Desktop: sticky top bar with org logo, nav links, and viewer avatar menu.
Mobile: fixed bottom dock with icon tabs for Home, Browse, Search, Profile.
Both use semantic token colors and respect the tenant accent.

---

## CSS architecture

All token definitions live in the main CSS file using Tailwind v4's
`@theme` directive and `@layer base`. Do not use `tailwind.config.js`
for token definitions.

Required keyframes: shimmer (skeleton sweep), fade-in, slide-up, ken-burns.

`prefers-reduced-motion: reduce` must disable all transitions and
animations globally. This is non-negotiable.

Global base styles: warm dark `color-scheme`, antialiased text rendering,
warm-toned scrollbar styling, accent-colored visible focus rings.

---

## Absolute rules — never violate these

- Never use hardcoded hex, rgb, or raw oklch values in templates or components
- Never use pure black or pure white
- Never use cool blue-gray dark backgrounds — warm brown-black only
- Never use daisyUI theme names for color values
- Never use tailwind.config.js for token definitions
- Never use transform:scale on cards within a grid or row (causes layout reflow)
- Never render an empty continue watching row
- Never autoplay video or audio on any surface
- Never use font-bold on serif typefaces — font-semibold maximum
- Never animate layout properties (width, height, margin, padding, top, left)
- Never use placeholder-only form labels — always use visible label elements
- Never support custom font upload — direct inquiries to enterprise contact
- Never modify existing tests to make new features pass
- Never break existing tests