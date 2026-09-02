/**
 * Guided admin tour — step definitions.
 *
 * Pure data: one step per admin view, each anchored to its sidebar nav link
 * (which is present on every admin page via `AdminLayout`), plus a centered
 * welcome and closing step. `title` and `text` may be a plain string or a
 * function of the org brand name so the copy greets the operator by service.
 *
 * The tour lives entirely on the dashboard — every anchor is in the sidebar,
 * so no cross-page navigation is needed.
 */

export type TourText = string | ((brand: string) => string)

export interface TourStep {
  id: string
  title: TourText
  text: TourText
  attachTo?: { element: string; on: "right" | "left" | "top" | "bottom" }
  buttons: string[]
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
