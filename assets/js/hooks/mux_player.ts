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
    this.maxPosition = 0
    this.videoDuration = 0
    this.dropOffSent = false

    this.resetDropOffState = (videoId: string) => {
      this.videoId = videoId
      this.maxPosition = 0
      this.videoDuration = 0
      this.dropOffSent = false
    }

    this.sendDropOff = () => {
      if (this.dropOffSent) return
      if (this.maxPosition <= 0) return
      this.dropOffSent = true
      this.pushEvent("playback_drop_off", {
        video_id: this.videoId,
        max_position: this.maxPosition,
        video_duration: this.videoDuration,
      })
    }

    player.addEventListener("timeupdate", () => {
      const pos = Number(player.currentTime || 0)
      if (pos > this.maxPosition) this.maxPosition = pos
    })

    player.addEventListener("loadedmetadata", () => {
      const dur = Number(player.duration || 0)
      if (dur > 0) this.videoDuration = dur
    })

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
      this.dropOffSent = true
      this.pushEvent("playback_ended", { video_id: this.videoId })
    })

    this.onVisibilityChange = () => {
      if (document.visibilityState === "hidden") {
        this.sendDropOff()
      } else {
        this.dropOffSent = false
      }
    }

    window.addEventListener("pagehide", this.sendDropOff)
    document.addEventListener("visibilitychange", this.onVisibilityChange)

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
        this.sendDropOff()
        this.resetDropOffState(video_id)
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
        this.sendDropOff()
        this.resetDropOffState(video_id)
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
  },
}

export default MuxPlayer
