---
name: branding-and-theming
description: Use when working on per-tenant theming, branding configuration, CSS variable driven customization, or tenant-specific visual templates and settings.
---

# Branding & Theming

Load this file when working on per-tenant visual customization, template
selection, or the branding configuration UI.

---

## Approach

Per-tenant theming uses **CSS custom properties** set dynamically from the
organization's stored theme configuration. Templates consume these variables —
they never contain hardcoded colors, fonts, or spacing values.

This means a single CSS bundle works for all tenants. The only thing that changes
per-tenant is the `:root` variable block injected into the layout.

---

## Theme Schema

```elixir
schema "themes" do
  belongs_to :organization, Bobine.Accounts.Organization

  # Colors
  field :brand_primary, :string, default: "#1a73e8"
  field :brand_secondary, :string, default: "#174ea6"
  field :background, :string, default: "#0f0f0f"
  field :surface, :string, default: "#1a1a1a"
  field :text_primary, :string, default: "#ffffff"
  field :text_secondary, :string, default: "#a0a0a0"
  field :accent, :string, default: "#e8901a"

  # Typography
  field :font_heading, :string, default: "Inter"
  field :font_body, :string, default: "Inter"

  # Shape
  field :border_radius, :string, default: "8px"
  field :card_border_radius, :string, default: "12px"

  # Assets
  field :logo_url, :string
  field :favicon_url, :string

  timestamps()
end
```

---

## CSS Custom Properties

The layout template renders the theme as CSS variables on `:root`:

```heex
<style>
  :root {
    --sv-brand-primary: <%= @theme.brand_primary %>;
    --sv-brand-secondary: <%= @theme.brand_secondary %>;
    --sv-bg: <%= @theme.background %>;
    --sv-surface: <%= @theme.surface %>;
    --sv-text-primary: <%= @theme.text_primary %>;
    --sv-text-secondary: <%= @theme.text_secondary %>;
    --sv-accent: <%= @theme.accent %>;
    --sv-font-heading: '<%= @theme.font_heading %>', sans-serif;
    --sv-font-body: '<%= @theme.font_body %>', sans-serif;
    --sv-radius: <%= @theme.border_radius %>;
    --sv-card-radius: <%= @theme.card_border_radius %>;
  }
</style>
```

### Usage in components

All viewer-facing components reference these variables. Never use raw color
values or Tailwind color classes for brand-specific styling.

```css
/* ✅ CORRECT */
.video-card {
  background: var(--sv-surface);
  border-radius: var(--sv-card-radius);
  color: var(--sv-text-primary);
}

.btn-primary {
  background: var(--sv-brand-primary);
}

/* ❌ WRONG — hardcoded values bypass theming */
.video-card {
  background: #1a1a1a;
  border-radius: 12px;
}
```

Tailwind is fine for layout utilities (flexbox, grid, spacing, responsive
breakpoints). The rule only applies to brand-customizable properties: colors,
fonts, border radii, and similar visual identity elements.

---

## Templates

### Structure

Viewer-facing templates live in `lib/stream_vane_web/templates/`. Each template
is a directory containing layout and component variant overrides.

```
lib/stream_vane_web/templates/
├── default/
│   ├── layout.html.heex
│   ├── home.html.heex
│   ├── video_card.html.heex
│   └── nav.html.heex
├── minimal/
│   ├── layout.html.heex
│   ├── home.html.heex
│   ├── video_card.html.heex
│   └── nav.html.heex
└── bold/
    ├── layout.html.heex
    ├── home.html.heex
    ├── video_card.html.heex
    └── nav.html.heex
```

### Template selection

The organization's selected template name is stored on the `Theme` schema or
directly on the `Organization`. At render time, the correct template directory
is resolved from this value.

```elixir
defp template_path(organization) do
  template_name = organization.template || "default"
  "templates/#{template_name}"
end
```

### Template rules

- Every template must implement the same set of required files (layout, home,
  video_card, nav). If a template omits a file, it falls back to `default/`.
- Templates only control structure and layout. They all consume the same CSS
  custom properties for colors and typography.
- Templates never contain business logic — no Ecto queries, no API calls,
  no conditional rendering based on subscription status. That logic lives in
  the LiveView; the template just renders assigns.

---

## Operator Branding UI

The branding page in the operator dashboard (`/admin/branding`) allows the
org owner/admin to:

1. Pick a template from the available options (shown as previews)
2. Customize theme colors, fonts, and border radii via a visual editor
3. Upload a logo and favicon
4. Preview changes live before saving

The preview should use an `<iframe>` or a LiveView component that re-renders
the viewer homepage with the draft theme applied, so the operator sees exactly
what their viewers will see.

---

## Logo & Asset Storage

For the MVP, logos and favicons can be stored as URLs (the operator provides a
hosted URL). Later, we can add direct file upload to an object store
(Fly Tigris, S3, or Cloudflare R2).

Do not store binary file data in Postgres.
