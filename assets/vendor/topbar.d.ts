/**
 * Type declarations for the vendored topbar 3.0.0 (`topbar.js`, UMD build).
 * Written by hand: topbar publishes no types.
 */
export interface TopbarOptions {
  /** Whether to auto-run the progress animation once shown. */
  autoRun?: boolean
  /** Bar thickness in CSS pixels. */
  barThickness?: number
  /** Gradient stops keyed by position (0–1) → CSS colour. */
  barColors?: Record<number, string>
  /** Blur radius of the drop shadow in CSS pixels. */
  shadowBlur?: number
  /** CSS colour of the drop shadow. */
  shadowColor?: string
  /** CSS class name applied to the canvas element. */
  className?: string
}

export interface Topbar {
  /** Merge options into the current configuration. */
  config(options: TopbarOptions): void
  /** Show the bar, optionally after `delay` milliseconds. */
  show(delay?: number): void
  /** Hide the bar, cancelling a pending delayed show. */
  hide(): void
  /** Read the current progress (0–1), or set it. `"+0.1"` style strings are relative. */
  progress(to?: number | string): number
}

declare const topbar: Topbar
export default topbar
