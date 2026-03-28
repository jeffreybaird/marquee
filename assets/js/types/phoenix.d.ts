/**
 * Type definitions for the Phoenix LiveView hook lifecycle.
 * esbuild handles .ts files natively; this file exists for editor tooling only.
 */
export interface PhoenixHook {
  /** The DOM element the hook is mounted on */
  el: HTMLElement

  /** Called when the hook's element is added to the DOM */
  mounted(): void

  /** Called before the LiveView patches the DOM */
  beforeUpdate?(): void

  /** Called after the LiveView patches the DOM */
  updated?(): void

  /** Called when the hook's element is removed from the DOM */
  destroyed?(): void

  /** Called when the LiveView socket disconnects */
  disconnected?(): void

  /** Called when the LiveView socket reconnects */
  reconnected?(): void

  /** Push an event to the LiveView server */
  pushEvent(event: string, payload: object, callback?: (reply: object) => void): void

  /** Push an event to a specific LiveView component */
  pushEventTo(
    selectorOrTarget: string | HTMLElement,
    event: string,
    payload: object,
    callback?: (reply: object) => void
  ): void

  /** Register a handler for events sent from the server */
  handleEvent(event: string, callback: (payload: object) => void): void

  /** Remove a previously registered server event handler */
  removeHandleEvent(callbackRef: (payload: object) => void): void

  /** Upload a file to the server */
  upload(name: string, files: FileList): void

  /** Upload a file to an external URL */
  uploadTo(
    selectorOrTarget: string | HTMLElement,
    name: string,
    files: FileList
  ): void
}
