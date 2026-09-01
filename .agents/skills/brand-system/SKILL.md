---
name: brand-system
description: Use when designing Marquee-branded interfaces, admin pages, marketing surfaces, or shared visual language where the platform brand rather than a tenant brand should guide UI decisions.
---

# Brand System

Load this file when building any UI — LiveView templates, components, admin
dashboard, viewer-facing pages, marketing pages, or any visual output.

---

## Brand Context

Marquee is a B2B video OTT platform. End users (viewers) never see the Marquee
brand — they see the tenant's brand. The Marquee brand exists on the operator
dashboard, the super admin panel, the marketing site, and sales materials.

The brand builds trust with creators and media companies. It signals taste
and professionalism. It feels calm, precise, and reliable.

This is NOT a consumer brand. Nothing playful, loud, or expressive.

---

## Core Principles

Every UI decision must pass through these constraints:

- **Clarity over expression**
- **Restraint over decoration**
- **Warmth without softness**
- **Precision without coldness**
- **Minimal motion**
- **No visual noise**

The product should feel like a well-designed tool, not a designed experience.

**Final rule: if something feels decorative, remove it.**

---

## Logo

### Primary mark — double exposure circle

Two overlapping circles evoking a film reel's geometry through implication,
not literal depiction. Use this SVG exactly:

```html
<svg viewBox="0 0 72 72">
  <circle cx="32" cy="36" r="24" stroke="#5A5753" stroke-width="2" fill="none"/>
  <circle cx="40" cy="36" r="24" stroke="#5A5753" stroke-width="2" fill="none" opacity="0.35"/>
</svg>
```

### Sizes

- Favicon: 16–24px
- Navigation: 20–28px
- Marketing: 40–80px max

### Rules

DO:
- Use in top-left navigation
- Use in footer
- Use in sales and marketing materials
- Use as small watermark in demos

DO NOT:
- Repeat as a pattern
- Animate in product UI
- Use as background decoration
- Over-scale or distort

---

## Typography

### Font stack

```css
font-family:
  "Söhne",
  "Suisse Intl",
  "Inter Tight",
  "Inter",
  -apple-system,
  system-ui,
  sans-serif;
```

### Weights

- **400** — default for all body text
- **500** — emphasis, headings, labels

Never use bold (700+). Never use ultra-light.

### Rules

- Brand name is always lowercase: `marquee`, never `Marquee` or `MARQUEE`
- Slight negative tracking for headlines: `letter-spacing: -0.01em` to `-0.02em`
- Line height in UI: `1.4` to `1.6`
- Typography carries hierarchy — not color or decoration
- If you need to create visual weight, use size and spacing, not bold

---

## Color System

### Base palette

```css
--color-bg-primary:    #F2EBE1;   /* warm cream — primary background */
--color-bg-secondary:  #E9E2D7;   /* slightly darker — cards, panels, surfaces */

--color-text-primary:  #4F4B47;   /* warm charcoal — all primary text */
--color-text-secondary: #7A746F;  /* muted warm gray — secondary text */

--color-border:        #D8D0C4;   /* warm border */
```

### Functional colors

```css
--color-success: #6E8B74;   /* muted sage green */
--color-error:   #A05C52;   /* muted terracotta red */
```

### Accent — rare use only

```css
--color-accent-amber: #C88A52;   /* amber — projector light */
```

The amber accent is used ONLY for:
- Active states
- Key action buttons (primary CTA)
- Playback and progress indicators
- Focus rings (subtle)

If you find yourself reaching for the accent color a third time on a single
page, you're overusing it. Pull back.

### Absolute restrictions

- **No pure black (#000000)** — always use `--color-text-primary` (#4F4B47)
- **No pure white (#FFFFFF)** — always use `--color-bg-primary` (#F2EBE1)
- **No gradients in product UI** — flat fills only
- **No neon, electric, or saturated colors** — everything is muted and warm

### Dark mode

The Marquee brand palette is inherently warm and light. If a dark mode is
needed for the admin dashboard, invert with warm dark tones:

```css
/* Dark mode overrides — warm, not cold */
--color-bg-primary:    #2A2724;
--color-bg-secondary:  #353130;
--color-text-primary:  #E9E2D7;
--color-text-secondary: #A09A94;
--color-border:        #4A4440;
```

Never use cool grays or blue-blacks. The darkness should feel like a
dimly lit cinema, not a code editor.

---

## Layout

### Grid

- 12-column layout
- Consistent gutters
- Max-width containers: 1200–1280px

### Spacing scale

Use ONLY these values. No exceptions.

```
8px   — tight spacing (within components)
16px  — default component padding
24px  — between related elements
32px  — section padding
48px  — between sections
64px  — major section breaks
```

If a spacing value isn't on this list, don't use it. Round to the nearest
value on the scale.

### Layout principles

- Large whitespace is intentional — don't fill it
- Avoid dense UI — one primary focus per screen
- Avoid unnecessary visual grouping (borders, boxes, backgrounds)
- Let breathing room do the work of organization

---

## Components

### Buttons

**Primary:**
```css
background: var(--color-text-primary);
color: var(--color-bg-primary);
```

**Secondary:**
```css
background: transparent;
border: 1px solid var(--color-border);
color: var(--color-text-primary);
```

**Hover:** Subtle darken/lighten only. No dramatic transitions.

### Cards and panels

```css
background: var(--color-bg-secondary);
border: 1px solid var(--color-border);
border-radius: 8px;
```

No shadows, or very subtle only when absolutely needed for depth.

### Inputs

- Clean borders
- No heavy outlines
- Focus state: border shifts slightly darker, optional amber accent (subtle)

### Status badges

Use muted versions of functional colors:
- Success: sage background with darker sage text
- Error: muted terracotta background with darker terracotta text
- Neutral: `--color-bg-secondary` with `--color-text-secondary`

---

## Motion

### Product UI

Minimal or none.

**Allowed:**
- Opacity fades: 150–250ms
- Subtle hover transitions on interactive elements

**Not allowed:**
- Drifting animations
- Looping motion
- Decorative transitions
- Bouncing, sliding, or scaling effects

### Marketing pages

Subtle motion is acceptable but restrained. Nothing that draws attention
to itself.

---

## UI Copy and Tone of Voice

### Style

Direct. Calm. Confident. Minimal.

### Examples

✅ Good:
- "Upload your catalog"
- "Set your pricing"
- "Launch your platform"
- "3 videos ready"
- "Subscription active"

❌ Bad:
- "Transform your creative journey!"
- "Unlock cinematic possibilities"
- "Your amazing streaming empire awaits"

### Rules

- No hype
- No fluff
- No exclamation points
- No emoji in UI (acceptable in support/chat, never in product)
- Sentence case always — never Title Case or ALL CAPS
- Error messages are helpful, not apologetic: "Email is required" not
  "Oops! Looks like you forgot to enter your email"

---

## Product UI Behavior

The interface should communicate:
- Reliability
- Clarity
- Control
- Ownership

NOT:
- Entertainment
- Playfulness
- Trendiness

The operator dashboard is where someone runs their business. It should
feel like a trusted tool, not a social media product.

---

## Per-Tenant Theming Boundary

The Marquee brand system applies to:
- Operator dashboard (`/admin/*`)
- Super admin panel (`/super/*`)
- Marketing site
- Login/registration pages
- Email communications from Marquee

The Marquee brand system does NOT apply to:
- Viewer-facing pages (those use the tenant's theme via CSS custom properties)
- Tenant email communications

When building viewer-facing templates, use the `--sv-*` CSS custom properties
from the tenant's theme (see `.claude/branding-and-theming.md`), not the
Marquee brand palette. The viewer should never know Marquee exists.

---

## Implementation Checklist

When generating any UI:

- [ ] No pure black (#000000) or pure white (#FFFFFF) used anywhere
- [ ] Typography uses only weight 400 and 500
- [ ] Brand name written as lowercase `marquee`
- [ ] Spacing uses only values from the scale (8/16/24/32/48/64)
- [ ] Accent amber used sparingly — max 1-2 instances per page
- [ ] Layout is not dense — clear visual breathing room
- [ ] Motion is minimal or absent
- [ ] Logo used only in approved placements and sizes
- [ ] UI copy is direct, calm, no hype, no exclamation points
- [ ] No gradients, no shadows (or very subtle), no decorative elements
- [ ] Any UI reads clearly in under 3 seconds
- [ ] Viewer-facing pages use tenant theme, not Marquee brand colors
