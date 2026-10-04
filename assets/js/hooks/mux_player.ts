/**
 * MuxPlayer hook
 *
 * Used by: WatchLive (via ViewerComponents.video_player)
 *
 * Mounts the Mux Player web component and bridges playback events
 * to the LiveView server.
 *
 * Dataset attributes:
 *   - data-playback-id: Mux playback ID
 *   - data-video-id: Marquee video ID
 *   - data-resume-position: Seconds to seek to on load
 *
 * Events sent to server:
 *   - "playback_started"  { video_id }
 *   - "playback_progress" { video_id, position }
 *   - "playback_paused"   { video_id, position }
 *   - "playback_ended"    { video_id }
 *   - "playback_drop_off" { video_id, max_position, video_duration }
 *
 * Events received from server:
 *   - "seek_to" { position }
 *   - "load_video" { playback_id, video_id, resume_position }
 *   - "play_next_in_queue" { playback_id, video_id, resume_position }
 */
import { ViewHook } from "phoenix_live_view"
import type { MuxPlayerElement } from "../types/mux"

interface LoadVideoPayload {
  playback_id: string
  video_id: string
  resume_position: number
}

class MuxPlayer extends ViewHook {
  private player: MuxPlayerElement | null = null
  private videoId: string | undefined
  private progressIntervalMs = 30000
  private progressJitterMs = 0
  private lastReportedPosition = 0
  private lastReportAt = 0
  private maxPosition = 0
  private videoDuration = 0
  private dropOffSent = false
  private startProgressInterval: number | null = null
  private progressInterval: number | null = null

  // Closures over the player element, assigned in mounted() so they stay
  // unset (and destroyed() skips them) when no player was found.
  private sendDropOff: (() => void) | null = null
  private flushProgress: (() => void) | null = null
  private onVisibilityChange: (() => void) | null = null
  private onNavigation: ((event: MouseEvent) => void) | null = null
  private navigationTimeout: number | null = null
  private replayingNavigation = false
  private pendingResume: (() => void) | null = null

  private cancelPendingResume() {
    if (this.pendingResume) {
      this.player?.removeEventListener("loadedmetadata", this.pendingResume)
      this.pendingResume = null
    }
  }

  private resumePlayback(position: number, currentSource = false) {
    this.cancelPendingResume()
    const player = this.player
    if (!player || position <= 0) return

    if (currentSource && player.readyState >= 1) {
      player.currentTime = position
      return
    }

    this.pendingResume = () => {
      this.pendingResume = null
      player.currentTime = position
    }
    player.addEventListener("loadedmetadata", this.pendingResume, { once: true })
  }

  mounted() {
    const player = this.el.querySelector("mux-player")
    if (!player) return

    this.player = player
    this.videoId = this.el.dataset.videoId
    this.progressIntervalMs = 30000
    this.progressJitterMs = Math.floor(Math.random() * 5000)
    this.lastReportedPosition = 0
    this.lastReportAt = 0
    this.maxPosition = 0
    this.videoDuration = 0
    this.dropOffSent = false

    const resetDropOffState = (videoId: string) => {
      this.videoId = videoId
      this.maxPosition = 0
      this.videoDuration = 0
      this.dropOffSent = false
    }

    const sendDropOff = () => {
      if (this.dropOffSent) return
      if (this.maxPosition <= 0) return
      this.dropOffSent = true
      this.pushEvent("playback_drop_off", {
        video_id: this.videoId,
        max_position: this.maxPosition,
        video_duration: this.videoDuration,
      })
    }
    this.sendDropOff = sendDropOff

    player.addEventListener("timeupdate", () => {
      const pos = Number(player.currentTime || 0)
      if (pos > this.maxPosition) this.maxPosition = pos
    })

    player.addEventListener("loadedmetadata", () => {
      const dur = Number(player.duration || 0)
      if (dur > 0) this.videoDuration = dur
    })

    const reportProgress = (eventName = "playback_progress") => {
      const position = Number(player.currentTime || 0)
      const now = Date.now()

      if (position <= 0) return

      if (
        eventName === "playback_progress" &&
        now - this.lastReportAt < this.progressIntervalMs - 1000 &&
        Math.abs(position - this.lastReportedPosition) < 15
      ) {
        return
      }

      this.lastReportAt = now
      this.lastReportedPosition = position
      this.pushEvent(eventName, {
        video_id: this.videoId,
        position,
      })
    }

    // Resume playback if position is set
    const resumePos = parseFloat(this.el.dataset.resumePosition || "0")
    this.resumePlayback(resumePos, true)

    // Report playback started
    player.addEventListener("play", () => {
      this.pushEvent("playback_started", { video_id: this.videoId })
    })

    // Spread out progress updates so reconnect storms do not align all viewers.
    this.startProgressInterval = window.setTimeout(() => {
      this.progressInterval = window.setInterval(() => {
        if (!player.paused && player.currentTime > 0) {
          reportProgress()
        }
      }, this.progressIntervalMs)
    }, this.progressJitterMs)

    // Report pause
    player.addEventListener("pause", () => {
      reportProgress("playback_paused")
    })

    // Flush a final progress sample when the tab is backgrounded or unloaded.
    const flushProgress = () => {
      if (!player.paused && player.currentTime > 0) {
        reportProgress()
      }
    }
    this.flushProgress = flushProgress

    // LiveView destroys hooks after leaving the old view. Save while that
    // view still owns its socket, then replay the original link after its ack.
    this.onNavigation = (event: MouseEvent) => {
      if (this.replayingNavigation) return
      if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return
      const link = event.target instanceof Element ? event.target.closest<HTMLElement>('a[href], button[phx-click="play_episode"]') : null
      if (!link || link.hasAttribute("download") || link.dataset.method) return
      if (link instanceof HTMLAnchorElement) {
        const url = new URL(link.href, window.location.href)
        if (link.target === "_blank" || url.origin !== window.location.origin || link.getAttribute("href")?.startsWith("#")) return
      }
      const position = Number(player.currentTime || 0)
      if (position <= 0) return
      event.preventDefault()
      event.stopImmediatePropagation()
      if (this.navigationTimeout !== null) return
      let finished = false
      const navigate = () => {
        if (finished) return
        finished = true
        if (this.navigationTimeout !== null) window.clearTimeout(this.navigationTimeout)
        this.navigationTimeout = null
        this.replayingNavigation = true
        link.click()
        this.replayingNavigation = false
      }
      // A disconnected socket must not trap visitors on the player page.
      this.navigationTimeout = window.setTimeout(navigate, 1500)
      this.pushEvent("playback_paused", { video_id: this.videoId, position }, navigate)
    }
    document.addEventListener("click", this.onNavigation, true)

    window.addEventListener("pagehide", flushProgress)
    document.addEventListener("visibilitychange", flushProgress)

    // Report ended — triggers queue auto-advance on server
    player.addEventListener("ended", () => {
      this.lastReportedPosition = Number(player.duration || player.currentTime || 0)
      this.dropOffSent = true
      this.pushEvent("playback_ended", { video_id: this.videoId })
    })

    const onVisibilityChange = () => {
      if (document.visibilityState === "hidden") {
        sendDropOff()
      } else {
        this.dropOffSent = false
      }
    }
    this.onVisibilityChange = onVisibilityChange

    window.addEventListener("pagehide", sendDropOff)
    document.addEventListener("visibilitychange", onVisibilityChange)

    // Handle server-initiated seek
    this.handleEvent("seek_to", ({ position }: { position: number }) => {
      player.currentTime = position
    })

    // Handle video load (season switch, episode click, queue advance)
    this.handleEvent(
      "load_video",
      ({ playback_id, video_id, resume_position }: LoadVideoPayload) => {
        sendDropOff()
        resetDropOffState(video_id)
        this.resumePlayback(resume_position)
        player.setAttribute("playback-id", playback_id)
      },
    )

    // Handle queue auto-advance — server pushes next video
    this.handleEvent(
      "play_next_in_queue",
      ({ playback_id, video_id, resume_position }: LoadVideoPayload) => {
        sendDropOff()
        resetDropOffState(video_id)
        this.resumePlayback(resume_position)
        player.setAttribute("playback-id", playback_id)

        player.play()
      },
    )
  }

  destroyed() {
    this.cancelPendingResume()
    if (this.onNavigation) document.removeEventListener("click", this.onNavigation, true)
    if (this.navigationTimeout !== null) window.clearTimeout(this.navigationTimeout)
    // Save final position before teardown. pagehide does not fire on
    // LiveView client-side navigation, so without this any watch shorter
    // than the progress interval would lose its position entirely.
    if (this.flushProgress) {
      this.flushProgress()
    }

    if (this.sendDropOff) {
      this.sendDropOff()
    }

    if (this.startProgressInterval) {
      clearTimeout(this.startProgressInterval)
    }

    if (this.progressInterval) {
      clearInterval(this.progressInterval)
    }

    if (this.flushProgress) {
      window.removeEventListener("pagehide", this.flushProgress)
      document.removeEventListener("visibilitychange", this.flushProgress)
    }

    if (this.sendDropOff) {
      window.removeEventListener("pagehide", this.sendDropOff)
    }

    if (this.onVisibilityChange) {
      document.removeEventListener("visibilitychange", this.onVisibilityChange)
    }
  }
}

export default MuxPlayer
