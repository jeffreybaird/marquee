import { vi } from "vitest"
import type { ViewHook } from "phoenix_live_view"

import type { PhoenixHookClass } from "../../js/types/phoenix"

type ServerHandler = (payload: unknown) => void

export interface MountedHook<H extends ViewHook> {
  /** The hook instance, already `mounted()`. */
  hook: H
  /** Spy on `pushEvent`, so tests can assert what the hook told the server. */
  pushEvent: ReturnType<typeof vi.fn>
  /** Simulate a `push_event` from the server for an event the hook handles. */
  serverPush: (event: string, payload?: unknown) => void
  /** Names of the server events the hook registered handlers for. */
  handledEvents: () => string[]
}

/**
 * Instantiate a hook on `el` without a LiveView socket and call `mounted()`.
 *
 * `pushEvent` and `handleEvent` are stubbed at the instance level: the real
 * ones need an attached view. Everything else runs the production code.
 */
export function mountHook<E extends HTMLElement, H extends ViewHook<E>>(
  Hook: PhoenixHookClass<E> & (new (view: null, el: E) => H),
  el: E,
): MountedHook<H> {
  if (!el.isConnected) document.body.appendChild(el)

  const hook = new Hook(null, el)
  const handlers = new Map<string, ServerHandler>()

  const pushEvent = vi.fn(() => Promise.resolve())
  hook.pushEvent = pushEvent as unknown as H["pushEvent"]
  hook.handleEvent = (event: string, callback: ServerHandler) => {
    handlers.set(event, callback)
    return { event, callback }
  }

  hook.mounted()

  return {
    hook,
    pushEvent,
    serverPush(event, payload = {}) {
      const handler = handlers.get(event)
      if (!handler) throw new Error(`hook has no handler for "${event}"`)
      handler(payload)
    },
    handledEvents: () => Array.from(handlers.keys()),
  }
}

/** Build an element from an HTML string; the first child is returned. */
export function html<E extends HTMLElement = HTMLElement>(markup: string): E {
  const template = document.createElement("template")
  template.innerHTML = markup.trim()
  return template.content.firstElementChild as E
}
