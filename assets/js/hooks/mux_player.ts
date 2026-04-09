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
 *   - data-video-id: Bobine video ID
 *   - data-resume-position: Seconds to seek to on load
 *
 * Events sent to server:
 *   - "playback_started"  { video_id }
 *   - "playback_progress" { video_id, position }
 *   - "playback_paused"   { video_id, position }
 *   - "playback_ended"    { video_id }
 *
 * Events received from server:
 *   - "seek_to" { position }
 *   - "play_next_in_queue" { playback_id, video_id, resume_position }
 */
const MuxPlayer = {
  mounted(this: any) {
    const player = this.el.querySelector("mux-player") as any
    if (!player) return

    this.player = player
    this.videoId = this.el.dataset.videoId
    this.progressIntervalMs = 30000
    this.progressJitterMs = Math.floor(Math.random() * 5000)
    this.lastReportedPosition = 0
    this.lastReportAt = 0

    this.reportProgress = (eventName = "playback_progress") => {
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
    if (resumePos > 0) {
      player.addEventListener(
        "loadedmetadata",
        () => {
          player.currentTime = resumePos
        },
        { once: true },
      )
    }

    // Report playback started
    player.addEventListener("play", () => {
      this.pushEvent("playback_started", { video_id: this.videoId })
    })

    // Spread out progress updates so reconnect storms do not align all viewers.
    this.startProgressInterval = window.setTimeout(() => {
      this.progressInterval = window.setInterval(() => {
        if (!player.paused && player.currentTime > 0) {
          this.reportProgress()
        }
      }, this.progressIntervalMs)
    }, this.progressJitterMs)

    // Report pause
    player.addEventListener("pause", () => {
      this.reportProgress("playback_paused")
    })

    // Flush a final progress sample when the tab is backgrounded or unloaded.
    this.flushProgress = () => {
      if (!player.paused && player.currentTime > 0) {
        this.reportProgress()
      }
    }

    window.addEventListener("pagehide", this.flushProgress)
    document.addEventListener("visibilitychange", this.flushProgress)

    // Report ended — triggers queue auto-advance on server
    player.addEventListener("ended", () => {
      this.lastReportedPosition = Number(player.duration || player.currentTime || 0)
      this.pushEvent("playback_ended", { video_id: this.videoId })
    })

    // Handle server-initiated seek
    this.handleEvent("seek_to", ({ position }: { position: number }) => {
      player.currentTime = position
    })

    // Handle video load (season switch, episode click, queue advance)
    this.handleEvent(
      "load_video",
      ({
        playback_id,
        video_id,
        resume_position,
      }: {
        playback_id: string
        video_id: string
        resume_position: number
      }) => {
        this.videoId = video_id
        player.setAttribute("playback-id", playback_id)

        if (resume_position > 0) {
          player.addEventListener(
            "loadedmetadata",
            () => {
              player.currentTime = resume_position
            },
            { once: true },
          )
        }
      },
    )

    // Handle queue auto-advance — server pushes next video
    this.handleEvent(
      "play_next_in_queue",
      ({
        playback_id,
        video_id,
        resume_position,
      }: {
        playback_id: string
        video_id: string
        resume_position: number
      }) => {
        this.videoId = video_id
        player.setAttribute("playback-id", playback_id)

        if (resume_position > 0) {
          player.addEventListener(
            "loadedmetadata",
            () => {
              player.currentTime = resume_position
            },
            { once: true },
          )
        }

        player.play()
      },
    )
  },

  destroyed(this: any) {
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
  },
}

export default MuxPlayer
