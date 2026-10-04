/**
 * Type definitions for the Mux Player web component.
 * Loaded from CDN: https://cdn.jsdelivr.net/npm/@mux/mux-player
 */
export interface MuxPlayerElement extends HTMLElement {
  /** Mux playback ID */
  playbackId: string

  /** Current playback position in seconds */
  currentTime: number

  /** Media readiness; 1 means metadata is available. */
  readyState: number

  /** Whether the player is paused */
  paused: boolean

  /** Whether the player has ended */
  ended: boolean

  /** Playback duration in seconds */
  duration: number

  /** Playback volume (0–1) */
  volume: number

  /** Whether the player is muted */
  muted: boolean

  /** Seek to a specific position in seconds */
  play(): Promise<void>

  pause(): void
}

declare global {
  interface HTMLElementTagNameMap {
    "mux-player": MuxPlayerElement
  }
}
