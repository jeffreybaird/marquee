# TypeScript Hooks

Load this file when working on LiveView hooks, the Mux Player integration,
push notifications, or any client-side JavaScript.

---

## Build System

Phoenix ships with esbuild, which handles TypeScript natively — no webpack, no
babel. Files are named `.ts` and esbuild strips types and bundles them
(`mix esbuild marquee`, entry `assets/js/app.ts`, output `priv/static/assets/js/app.js`).

esbuild does **not** type-check. Type-checking and unit tests run through the
npm toolchain in `assets/package.json`, which exists only for checking and
testing — nothing installed there ships to the browser.

```bash
cd assets
npm ci                 # once per checkout (remote sessions: done by session-start.sh)
npm run typecheck      # tsc --noEmit, strict mode, must exit 0
npm test               # vitest, jsdom environment
npm run test:watch     # vitest in watch mode
```

Both `npm run typecheck` and `npm test` run in CI (`.github/workflows/ci.yml`,
`test` job) before `mix test`, so a type error or a failing hook test blocks
the build. `mix marquee.verify` runs them (plus `mix esbuild marquee`) as
part of the local pre-commit suite.

Pinned versions live in `assets/package.json`; bump them there and re-run
`npm install` to refresh `package-lock.json`.

---

## File Structure

```
assets/
├── js/
│   ├── app.ts                        # Entry point — creates the LiveSocket, registers hooks
│   ├── hooks/
│   │   ├── index.ts                  # Re-exports all hooks as a single object
│   │   ├── analytics_chart_hook.ts   # Chart.js charts fed by server push_event
│   │   ├── card_focus.ts             # Video card hover/focus popup + preview player
│   │   ├── carousel.ts               # Drag-to-scroll rows with momentum
│   │   ├── chat_auto_scroll.ts       # Keeps live-event chat pinned to the bottom
│   │   ├── copy_to_clipboard.ts      # Copies data-copy-value on click
│   │   ├── guided_tour.ts            # Bridges the Shepherd admin tour to the dashboard LiveView
│   │   ├── hero_carousel.ts          # Auto-advancing homepage hero
│   │   ├── mux_player.ts             # Mux Player web component bridge
│   │   ├── mux_uploader.ts           # Direct-to-Mux video upload
│   │   ├── queue_sortable.ts         # Sortable.js queue reordering
│   │   ├── row_scroller.ts           # Arrow navigation for content rows
│   │   ├── scroll_to_current_episode.ts
│   │   ├── spaces_uploader.ts        # Direct-to-Spaces image upload
│   │   ├── stagger_reveal.ts         # Entrance animation for row items
│   │   └── viewer_nav.ts             # Transparent → solid nav on scroll
│   ├── motion.ts                     # prefersReducedMotion(), scrollBehavior(): reduced-motion helpers
│   ├── tour/
│   │   ├── steps.ts                  # Admin tour step data (pure)
│   │   └── index.ts                  # Builds the Shepherd tour from the steps, pause/resume
│   └── types/
│       ├── phoenix.d.ts              # PhoenixHook aliases + window globals used by app.ts
│       └── mux.d.ts                  # Type defs for the <mux-player> element
├── test/
│   ├── setup.ts                      # jsdom stand-ins (matchMedia, scrollIntoView, scrollBy)
│   ├── support/
│   │   ├── mount.ts                  # mountHook(): instantiate a hook without a socket
│   │   ├── media.ts                  # setReducedMotion()
│   │   └── xhr.ts                    # XMLHttpRequest double for the upload hooks
│   ├── hooks/*.test.ts               # One test file per hook, plus index.test.ts
│   ├── motion.test.ts                # prefersReducedMotion()/scrollBehavior() reduced-motion helpers
│   └── tour/*.test.ts                # Step data integrity, tour wiring
├── vendor/
│   ├── chart.js + chart.d.ts         # Vendored builds with their declarations
│   ├── shepherd.js + shepherd.d.ts
│   ├── sortable.js + sortable.d.ts
│   └── topbar.js + topbar.d.ts
├── css/
│   └── app.css
├── package.json                      # typecheck / test scripts, pinned devDependencies
├── tsconfig.json
└── vitest.config.mts
```

### `app.ts` entry point

```typescript
import { hooks } from "./hooks"

const liveSocket = new LiveSocket("/live", Socket, {
  hooks,
  params: { _csrf_token: csrfToken },
})

liveSocket.connect()
```

### `hooks/index.ts`

```typescript
import type { HooksOptions } from "phoenix_live_view"

import MuxPlayer from "./mux_player"
import ViewerNav from "./viewer_nav"

export const hooks = {
  MuxPlayer,
  ViewerNav,
} satisfies HooksOptions
```

`satisfies HooksOptions` makes registering something that is not a hook a
compile error.

---

## Hook Interface

Hooks are classes extending `ViewHook` from `phoenix_live_view` — the typed
hook form LiveView 1.1 supports natively. LiveView instantiates the class once
per hooked element and calls the lifecycle methods on it.

```typescript
import { ViewHook } from "phoenix_live_view"

class MyHook extends ViewHook {
  mounted(): void        // element added to the DOM and its LiveView mounted
  beforeUpdate(): void   // about to be patched
  updated(): void        // patched
  destroyed(): void      // removed from the page
  disconnected(): void   // socket dropped
  reconnected(): void    // socket back

  // Provided by ViewHook
  el: HTMLElement
  pushEvent(event: string, payload: object): Promise<unknown>
  pushEventTo(selectorOrTarget: string | HTMLElement, event: string, payload: object): Promise<unknown>
  handleEvent(event: string, callback: (payload: any) => void): CallbackRef
  removeHandleEvent(ref: CallbackRef): void
}
```

Why classes and not object literals: LiveView's own `Hook` interface carries a
`[key: PropertyKey]: any` index signature, so on an object-literal hook every
`this.anything` silently types as `any`. `ViewHook` has no such signature, so a
misspelt field or method is a compile error, and instance state is declared
with real types.

Hooks that mount on a specific element type say so: `class AnalyticsChart
extends ViewHook<HTMLCanvasElement>` makes `this.el` a canvas.

### Hook template

```typescript
/**
 * MuxPlayer hook
 *
 * Mounts the Mux Player web component and bridges playback events
 * to the LiveView server.
 *
 * Events sent to server:
 *   - "playback_started" { video_id, timestamp }
 *   - "playback_paused"  { video_id, position }
 *   - "playback_ended"   { video_id }
 *
 * Events received from server:
 *   - "seek_to" { position }
 */
import { ViewHook } from "phoenix_live_view"

interface SeekToPayload {
  position: number
}

class MuxPlayer extends ViewHook {
  // Instance state: declared with a type, initialised in mounted().
  private player: MuxPlayerElement | null = null
  private timer: ReturnType<typeof setInterval> | null = null

  mounted() {
    this.player = this.el.querySelector("mux-player")
    this.handleEvent("seek_to", ({ position }: SeekToPayload) => {
      // ...
    })
  }

  destroyed() {
    if (this.timer) clearInterval(this.timer)
  }
}

export default MuxPlayer
```

Conventions the template shows:

- Server payloads get a named `interface`; the `handleEvent` callback
  parameter is annotated with it (`handleEvent` itself is typed `any`).
- Helpers that are not lifecycle methods are `private`.
- State that `destroyed()` must tear down is nullable and only assigned once
  the thing it refers to exists, so `destroyed()` can guard on it.
- A listener that must be removed later is stored on the instance as an arrow
  function field (`private onScroll = () => { ... }`), never re-created inline.

---

## Rules

### 1. Hooks are thin bridges — no business logic

Hooks manage DOM interactions and JS library bindings. They do not make decisions
about what to show, how to filter data, or what permissions the user has. That
logic lives server-side in the LiveView.

```typescript
// ✅ CORRECT — hook reports an event, server decides what to do
this.pushEvent("playback_ended", { video_id: this.el.dataset.videoId })

// ❌ WRONG — hook decides to update the watchlist
fetch("/api/watchlist/remove", { method: "POST", body: ... })
```

### 2. Communicate via `pushEvent` / `handleEvent`

Hooks communicate with the server exclusively through the LiveView socket.
Never make direct HTTP calls (fetch, XMLHttpRequest) from hooks. The only
exceptions are the direct uploads, which go to Mux's and DigitalOcean Spaces'
servers (not ours).

### 3. All hooks must have JSDoc comments

Every hook must document:
- What it does (one sentence)
- Events it **sends** to the server (name + payload shape)
- Events it **receives** from the server (name + payload shape)
- Any DOM attributes it reads from `this.el.dataset`

### 4. Clean up in `destroyed()`

If a hook adds event listeners, timers, or creates objects (e.g. a Mux Player
instance), it must clean them up in `destroyed()` to prevent memory leaks
during LiveView navigation.

### 5. No global state

Hooks must not store state in module-level variables or on `window`. All state
lives on `this` (the hook instance) so it's scoped to the element's lifecycle.

```typescript
// ✅ CORRECT — state on the hook instance
class MuxPlayer extends ViewHook {
  private player: MuxPlayerElement | null = null
  private intervalId: ReturnType<typeof setInterval> | null = null
}

// ❌ WRONG — global state
let player: MuxPlayerElement
let intervalId: number
```

### 6. No `any`, no `@ts-ignore`

`tsconfig.json` is `strict: true` and CI runs `tsc --noEmit`. Fix the type,
don't hide it. An untyped third-party library gets a declaration file next to
it in `assets/vendor/` (see `topbar.d.ts`), or a types-only devDependency
re-exported from one (see `chart.d.ts`, `sortable.d.ts`, `shepherd.d.ts`).

### 7. Every hook has a test

`assets/test/hooks/<hook>.test.ts` covers each branch of the hook: what it
pushes to the server, what it changes in the DOM, and that `destroyed()`
tears everything down. See **Testing** below.

---

## Testing

Tests run in vitest with a jsdom environment. `test/support/mount.ts` is the
entry point:

```typescript
import { describe, expect, it } from "vitest"

import ViewerNav from "../../js/hooks/viewer_nav"
import { html, mountHook } from "../support/mount"

it("becomes solid past the threshold", () => {
  const el = html(`<header id="nav" data-scroll-threshold="50"></header>`)
  const { hook, pushEvent, serverPush } = mountHook(ViewerNav, el)
  // hook       — the instance, already mounted()
  // pushEvent  — spy: expect(pushEvent).toHaveBeenCalledWith("event", {...})
  // serverPush — simulate a push_event from the server: serverPush("seek_to", {position: 1})
  hook.destroyed()
})
```

`mountHook` instantiates the real class with no LiveView attached and stubs
only `pushEvent` and `handleEvent`. Everything else — DOM queries, listeners,
timers — is production code, so drive it with real DOM events
(`el.dispatchEvent(new Event("mouseenter"))`, `button.click()`).

What jsdom lacks and how the tests cover it:

- `matchMedia`: `test/setup.ts` installs one; `setReducedMotion(true)` in
  `test/support/media.ts` flips the reduced-motion query. Hooks read the
  preference through `js/motion.ts` (`prefersReducedMotion()`,
  `scrollBehavior()`) rather than calling `matchMedia` directly.
- Layout (`clientWidth`, `scrollHeight`, `getBoundingClientRect`): define the
  properties on the element under test with `Object.defineProperty` or
  `vi.spyOn`.
- `scrollIntoView` / `scrollBy`: inert stand-ins from `test/setup.ts`; spy on
  the instance (`vi.spyOn(row, "scrollIntoView")`) to assert calls.
- Timers: `vi.useFakeTimers()` and `vi.advanceTimersByTime()`; add
  `requestAnimationFrame` / `performance` to `toFake` when the hook uses them.
- `XMLHttpRequest`: `FakeXMLHttpRequest.install()` from `test/support/xhr.ts`,
  then `FakeXMLHttpRequest.latest().respond(200)` / `.fail()` / `.progress()`.
- Canvas: none, so Chart.js cannot render — `vi.mock("../../vendor/chart.js", ...)`
  with a recording double, as `analytics_chart.test.ts` does.
- The Mux Player web component: a plain `<mux-player>` element with the
  properties the hook reads (`currentTime`, `paused`, `duration`, `play`)
  assigned on it.

The Phoenix packages come from `deps/`, not npm; `vitest.config.mts` aliases
`phoenix` and `phoenix_live_view` to their ESM builds there. `mix deps.get`
must have run before the tests will resolve.

---

## Mux Player Integration

The Mux Player is a web component (`<mux-player>`). It's loaded from the Mux
CDN in the layout head:

```html
<script src="https://cdn.jsdelivr.net/npm/@mux/mux-player"></script>
```

The LiveView renders the element with the playback ID:

```heex
<div id={"player-#{@video.id}"}
     phx-hook="MuxPlayer"
     data-playback-id={@video.mux_playback_id}
     data-video-id={@video.id}>
  <mux-player
    playback-id={@video.mux_playback_id}
    metadata-video-title={@video.title}
    accent-color={@theme.brand_primary}
    stream-type="on-demand"
  />
</div>
```

The `MuxPlayer` hook then binds to the player element's events (play, pause,
timeupdate, ended) and relays them to the server via `pushEvent`.
`js/types/mux.d.ts` registers `mux-player` in `HTMLElementTagNameMap`, so
`el.querySelector("mux-player")` and `document.createElement("mux-player")`
are typed as `MuxPlayerElement` without a cast.

---

## tsconfig.json

```json
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "strict": true,
    "noEmit": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "paths": {
      "@hooks/*": ["./js/hooks/*"],
      "@types/*": ["./js/types/*"],
      "phoenix_html": ["../deps/phoenix_html"],
      "phoenix_live_view": ["../deps/phoenix_live_view"]
    }
  },
  "include": ["js/**/*.ts", "test/**/*.ts", "vitest.config.mts"],
  "exclude": ["node_modules"]
}
```

Notes:

- No `baseUrl`: it is deprecated in TypeScript 6 and removed in 7. `paths`
  entries are relative to `assets/`.
- `phoenix_live_view` and `phoenix_html` map to the Hex packages in `deps/`;
  LiveView 1.1 ships its own `.d.ts` files there. `phoenix` itself has no
  bundled types, so `@types/phoenix` provides them.
- esbuild reads this file too (for `paths`), which is why the esbuild entry in
  `config/config.exs` is the real file `js/app.ts` rather than a package-style
  `js/app.js` that only resolved through `baseUrl`.
