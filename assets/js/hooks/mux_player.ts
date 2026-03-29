/**
 * MuxPlayer hook
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
 */
const MuxPlayer = {
  mounted() {
    const player = this.el.querySelector("mux-player") as any
    if (!player) return

    this.player = player
    this.videoId = this.el.dataset.videoId

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

    // Report progress every 10 seconds
    this.progressInterval = setInterval(() => {
      if (!player.paused && player.currentTime > 0) {
        this.pushEvent("playback_progress", {
          video_id: this.videoId,
          position: player.currentTime,
        })
      }
    }, 10000)

    // Report pause
    player.addEventListener("pause", () => {
      this.pushEvent("playback_paused", {
        video_id: this.videoId,
        position: player.currentTime,
      })
    })

    // Report ended
    player.addEventListener("ended", () => {
      this.pushEvent("playback_ended", { video_id: this.videoId })
    })

    // Handle server-initiated seek
    this.handleEvent("seek_to", ({ position }: { position: number }) => {
      player.currentTime = position
    })
  },

  destroyed() {
    if (this.progressInterval) {
      clearInterval(this.progressInterval)
    }
  },
}

export default MuxPlayer
