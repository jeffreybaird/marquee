/**
 * Guided tour — step definitions (pure data).
 *
 * Two kinds of tour live here:
 *
 *   - `ADMIN_TOUR_STEPS`: the dashboard overview. One step per admin view, each
 *     anchored to its sidebar nav link (present on every admin page via
 *     `AdminLayout`), plus a centered welcome and closing step. It runs
 *     entirely on the dashboard — every anchor is in the sidebar, so no
 *     cross-page navigation is needed.
 *   - `PAGE_TOURS`: per-page walkthroughs, keyed by page. Each is shown the
 *     first time a person visits that page and is anchored to in-page elements
 *     rather than the sidebar. Completion is tracked server-side per person,
 *     per org, per page (`page_tour_completions`).
 *
 * `title` and `text` may be a plain string or a function of the org brand name
 * so the copy can greet the user by service.
 */

export type TourText = string | ((brand: string) => string)

export type TourButton = "back" | "next" | "finish"

export interface TourStep {
  id: string
  title: TourText
  text: TourText
  attachTo?: { element: string; on: "right" | "left" | "top" | "bottom" }
  buttons: TourButton[]
}

// Anchor a step to a sidebar nav link by its `data-test` attribute.
const nav = (key: string): TourStep["attachTo"] => ({
  element: `[data-test='admin-nav-${key}']`,
  on: "right",
})

export const ADMIN_TOUR_STEPS: TourStep[] = [
  {
    id: "welcome",
    title: (brand) => `Welcome to ${brand}!`,
    text: "Let’s take a quick tour of your admin dashboard so you know where everything lives. It only takes a minute.<br><br><em style='font-size:0.85em;opacity:0.7'>Click anywhere outside the tour to explore — a button appears to continue.</em>",
    buttons: ["next"],
  },
  {
    id: "dashboard",
    attachTo: nav("dashboard"),
    title: "Dashboard",
    text: "Your home base. At-a-glance KPIs, recent uploads and signups, and setup nudges that guide your first steps.",
    buttons: ["next"],
  },
  {
    id: "content",
    attachTo: nav("content"),
    title: "Content",
    text: "Upload videos, edit their metadata, manage tags, and publish. This is where your library grows.",
    buttons: ["back", "next"],
  },
  {
    id: "collections",
    attachTo: nav("collections"),
    title: "Collections",
    text: "Group videos into collections — the shelves viewers browse on your site.",
    buttons: ["back", "next"],
  },
  {
    id: "series",
    attachTo: nav("series"),
    title: "Series",
    text: "Organize episodic content into series and seasons so viewers can watch in order.",
    buttons: ["back", "next"],
  },
  {
    id: "tags",
    attachTo: nav("tags"),
    title: "Tags",
    text: "Create and manage tags to categorize content and power search and filtering.",
    buttons: ["back", "next"],
  },
  {
    id: "catalog",
    attachTo: nav("catalog"),
    title: "Catalog",
    text: "Build your homepage: add and reorder rows, and configure the hero banner viewers see first.",
    buttons: ["back", "next"],
  },
  {
    id: "podcasts",
    attachTo: nav("podcasts"),
    title: "Podcasts",
    text: "Publish audio shows and episodes, complete with an RSS feed your listeners can subscribe to.",
    buttons: ["back", "next"],
  },
  {
    id: "landing",
    attachTo: nav("landing"),
    title: "Landing Page",
    text: "Craft the marketing page new visitors land on before they subscribe.",
    buttons: ["back", "next"],
  },
  {
    id: "analytics",
    attachTo: nav("analytics"),
    title: "Analytics",
    text: "Track views, engagement, subscriber growth and churn — and drill into per-video and per-series performance.",
    buttons: ["back", "next"],
  },
  {
    id: "appearance",
    attachTo: nav("appearance"),
    title: "Appearance",
    text: "Customize your brand: colors, fonts and theme, with a live preview of your viewer site.",
    buttons: ["back", "next"],
  },
  {
    id: "members",
    attachTo: nav("members"),
    title: "Members",
    text: "Invite teammates and manage operator roles, plus your viewer members.",
    buttons: ["back", "next"],
  },
  {
    id: "webhooks",
    attachTo: nav("webhooks"),
    title: "Webhooks",
    text: "Send events to your own systems by registering outbound webhook endpoints.",
    buttons: ["back", "next"],
  },
  {
    id: "settings",
    attachTo: nav("settings"),
    title: "Settings",
    text: "Connect Stripe to take payments, and manage your organization’s configuration.",
    buttons: ["back", "next"],
  },
  {
    id: "billing",
    attachTo: nav("billing"),
    title: "Billing",
    text: "Manage your Marquee platform subscription, plan and usage.",
    buttons: ["back", "next"],
  },
  {
    id: "audit-log",
    attachTo: nav("audit-log"),
    title: "Audit Log",
    text: "Every change is recorded here — who did what, and when.",
    buttons: ["back", "next"],
  },
  {
    id: "view-site",
    attachTo: { element: "[data-test='admin-view-site']", on: "right" },
    title: "View Your Site",
    text: "Open your live viewer site in a new tab any time to see exactly what your audience sees.",
    buttons: ["back", "next"],
  },
  {
    id: "done",
    title: "You’re all set!",
    text: "That’s the whole dashboard. You can restart this tour any time from the <strong>Take a tour</strong> link on your dashboard.",
    buttons: ["finish"],
  },
]

// ── Per-page tours ───────────────────────────────────────────────────────────
//
// Anchor a step to an in-page element by its `data-test` attribute. Unlike the
// sidebar `nav()` helper, these targets live in the page's own template, so the
// side the tooltip attaches on is chosen per element.

/** First-visit walkthrough for the Content management page (`/admin/content`). */
export const CONTENT_TOUR_STEPS: TourStep[] = [
  {
    id: "content-welcome",
    title: "Your content library",
    text: "This is where your videos live. Here’s a quick look at what you can do on this page.",
    buttons: ["next"],
  },
  {
    id: "content-upload",
    attachTo: { element: "[data-test='upload-btn']", on: "bottom" },
    title: "Upload videos",
    text: "Add new videos here. You can upload several at once — each is sent straight to Mux for processing, and appears in the list below as it’s prepared.",
    buttons: ["back", "next"],
  },
  {
    id: "content-search",
    attachTo: { element: "[data-test='video-search']", on: "bottom" },
    title: "Find a video",
    text: "Search your library by title as it grows. Once you’ve created tags, filters appear here too so you can narrow the list.",
    buttons: ["back", "next"],
  },
  {
    id: "content-done",
    title: "That’s the content page",
    text: "Upload a video to get started. You can replay this walkthrough any time from the <strong>Page tour</strong> link.",
    buttons: ["finish"],
  },
]

/**
 * Registry of per-page tours, keyed by the page key the PageTour hook reads
 * from `data-tour-page` and reports back to the server (stored in
 * `page_tour_completions.page_key`). Add a page here and mount the PageTour
 * hook on its LiveView to give it a first-visit walkthrough.
 */
export const PAGE_TOURS: Record<string, TourStep[]> = {
  content: CONTENT_TOUR_STEPS,
}
