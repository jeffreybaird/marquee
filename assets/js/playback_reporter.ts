/**
 * Playback reporter
 *
 * Used by: MuxPlayer and ShortsFeed hooks.
 *
 * Holds the per-video bookkeeping both player hooks share: the throttle for
 * periodic progress samples, the furthest position watched and the duration
 * for the drop-off report, and whether that drop-off was already sent. It
 * decides only *when* a sample is worth sending; what the server does with it
 * stays server-side. One reporter tracks one video at a time.
 *
 * Events it pushes (through the `push` function it is given):
 *   - "playback_started"  { video_id }
 *   - "playback_progress" { video_id, position }
 *   - "playback_paused"   { video_id, position }
 *   - "playback_ended"    { video_id }
 *   - "playback_drop_off" { video_id, max_position, video_duration }
 *
 * No server events are received and no DOM attributes are read.
 */

/** Sends one playback event to the server. */
export type PushPlaybackEvent = (event: string, payload: Record<string, unknown>) => void

/** How often a playing video sends a progress sample, in milliseconds. */
export const PROGRESS_INTERVAL_MS = 30000

/** Upper bound of the random delay before the first sample, so reconnects do not align viewers. */
export const PROGRESS_JITTER_MS = 5000

/** A progress sample this close (seconds) to the last one, and this recent, is skipped. */
const MIN_POSITION_DELTA = 15

export class PlaybackReporter {
  private lastReportedPosition = 0
  private lastReportAt = 0
  private maxPosition = 0
  private videoDuration = 0
  private dropOffSent = false

  constructor(
    private readonly push: PushPlaybackEvent,
    private videoId: string | undefined,
    private readonly progressIntervalMs = PROGRESS_INTERVAL_MS,
  ) {}

  /** Remember the furthest position watched (from `timeupdate`). */
  trackPosition(position: number): void {
    if (position > this.maxPosition) this.maxPosition = position
  }

  /** Remember the video's duration once it is known (from `loadedmetadata`). */
  trackDuration(duration: number): void {
    if (duration > 0) this.videoDuration = duration
  }

  /** Report that playback started. */
  reportStarted(): void {
    this.push("playback_started", { video_id: this.videoId })
  }

  /**
   * Send a position sample. A zero position is never sent; a progress sample
   * close to and soon after the previous one is skipped, other events always go.
   */
  report(position: number, eventName = "playback_progress"): void {
    const now = Date.now()

    if (position <= 0) return

    if (
      eventName === "playback_progress" &&
      now - this.lastReportAt < this.progressIntervalMs - 1000 &&
      Math.abs(position - this.lastReportedPosition) < MIN_POSITION_DELTA
    ) {
      return
    }

    this.lastReportAt = now
    this.lastReportedPosition = position
    this.push(eventName, { video_id: this.videoId, position })
  }

  /** Report a finished video; a finished video sends no drop-off. */
  reportEnded(position: number): void {
    this.lastReportedPosition = position
    this.dropOffSent = true
    this.push("playback_ended", { video_id: this.videoId })
  }

  /** Send the drop-off once, and only after something was watched. */
  sendDropOff(): void {
    if (this.dropOffSent) return
    if (this.maxPosition <= 0) return
    this.dropOffSent = true
    this.push("playback_drop_off", {
      video_id: this.videoId,
      max_position: this.maxPosition,
      video_duration: this.videoDuration,
    })
  }

  /** Allow another drop-off, e.g. once a backgrounded tab is visible again. */
  rearmDropOff(): void {
    this.dropOffSent = false
  }

  /** Start a new view of the same video: the furthest position and the drop-off start over. */
  beginView(): void {
    this.maxPosition = 0
    this.dropOffSent = false
  }

  /** Start tracking a different video; the progress throttle carries over. */
  switchVideo(videoId: string): void {
    this.videoId = videoId
    this.maxPosition = 0
    this.videoDuration = 0
    this.dropOffSent = false
  }
}
