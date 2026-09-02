/**
 * Type definitions for the Phoenix LiveView client as used by Marquee.
 *
 * Phoenix LiveView 1.1 ships its own TypeScript declarations (resolved from
 * `deps/phoenix_live_view` via the `paths` entry in tsconfig.json). Hooks are
 * written as classes extending `ViewHook`, which gives `this.el`,
 * `this.pushEvent`, `this.handleEvent` and every declared field a real type
 * with no `any` escape hatch. This file adds what LiveView does not declare:
 * the globals `app.ts` installs on `window` and the phoenix_live_reload
 * development event.
 */
import type { LiveSocket, ViewHook } from "phoenix_live_view"

/** A hook as registered in the `hooks` map handed to `LiveSocket`. */
export type PhoenixHook<E extends HTMLElement = HTMLElement> = ViewHook<E>

/** A hook class: `LiveSocket` instantiates it once per hooked element. */
export type PhoenixHookClass<E extends HTMLElement = HTMLElement> = new (
  ...args: ConstructorParameters<typeof ViewHook<E>>
) => ViewHook<E>

/** The client object phoenix_live_reload attaches in development. */
export interface LiveReloader {
  enableServerLogs(): void
  disableServerLogs(): void
  openEditorAtCaller(targetNode: EventTarget | null): void
  openEditorAtDef(targetNode: EventTarget | null): void
}

declare global {
  interface Window {
    /** Exposed by app.ts for console debugging and latency simulation. */
    liveSocket: LiveSocket
    /** Exposed by app.ts in development only. */
    liveReloader?: LiveReloader
  }

  interface WindowEventMap {
    "phx:live_reload:attached": CustomEvent<LiveReloader>
  }
}
