/**
 * PlaybackTracker hook
 *
 * Periodically reports the current playback position to the server
 * so watch progress can be persisted.
 *
 * Dataset attributes:
 *   - data-video-id: local video record ID
 *   - data-interval-ms: reporting interval in milliseconds (default: 10000)
 *
 * Events sent to server:
 *   - "progress_update" { video_id: string, position: number }
 *
 * Events received from server: none
 */
const PlaybackTracker = {
  mounted() {
    // Start periodic position reporting
  },

  destroyed() {
    // Clear reporting interval
  },
}

export default PlaybackTracker
