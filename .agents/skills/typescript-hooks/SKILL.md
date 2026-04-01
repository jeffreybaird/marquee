---
name: typescript-hooks
description: Use when working on LiveView hooks, TypeScript assets, client-side browser behavior, Mux player integration, or other front-end hook code in Bobine.
---

# TypeScript Hooks

Load this file when working on LiveView hooks, the Mux Player integration,
push notifications, or any client-side JavaScript.

---

## Build System

Phoenix ships with esbuild, which handles TypeScript natively — no webpack, no
babel, no additional config. Files are named `.ts` and esbuild strips types and
bundles them.

A `tsconfig.json` exists in `assets/` for editor support and CI type checking.
esbuild does **not** type-check — `tsc --noEmit` runs as a separate CI step.

---

## File Structure

```
assets/
├── js/
│   ├── app.ts                      # Entry point — imports and registers hooks
│   ├── hooks/
│   │   ├── index.ts                # Re-exports all hooks as a single object
│   │   ├── mux_player.ts          # Mux Player web component integration
│   │   ├── playback_tracker.ts    # Reports playback position to server
│   │   ├── push_notifications.ts  # Web Push API registration
│   │   └── sortable.ts            # Drag-and-drop for admin row builder
│   └── types/
│       ├── phoenix.d.ts           # Type defs for LiveView hook lifecycle
│       └── mux.d.ts               # Type defs for Mux Player element
├── css/
│   └── app.css
└── tsconfig.json
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
import MuxPlayer from "./mux_player"
import PlaybackTracker from "./playback_tracker"
import PushNotifications from "./push_notifications"
import Sortable from "./sortable"

export const hooks = {
  MuxPlayer,
  PlaybackTracker,
  PushNotifications,
  Sortable,
}
```

---

## Hook Interface

Every hook must conform to the Phoenix LiveView hook lifecycle:

```typescript
interface PhoenixHook {
  mounted(): void
  beforeUpdate?(): void
  updated?(): void
  destroyed?(): void
  disconnected?(): void
  reconnected?(): void

  // Provided by LiveView at runtime
  el: HTMLElement
  pushEvent(event: string, payload: object): void
  pushEventTo(selector: string, event: string, payload: object): void
  handleEvent(event: string, callback: (payload: object) => void): void
}
```

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
const MuxPlayer = {
  mounted() {
    // Initialize Mux Player, bind event listeners
  },

  destroyed() {
    // Clean up event listeners
  },
}

export default MuxPlayer
```

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
exception is the initial Mux direct upload, which goes to Mux's servers
(not ours).

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
mounted() {
  this.player = new MuxPlayerElement()
  this.intervalId = setInterval(() => this.reportPosition(), 10000)
}

// ❌ WRONG — global state
let player: MuxPlayerElement
let intervalId: number
```

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
    "baseUrl": ".",
    "paths": {
      "@hooks/*": ["js/hooks/*"],
      "@types/*": ["js/types/*"]
    }
  },
  "include": ["js/**/*.ts"],
  "exclude": ["node_modules"]
}
```

This is for editor tooling and CI only — esbuild ignores it during builds.
