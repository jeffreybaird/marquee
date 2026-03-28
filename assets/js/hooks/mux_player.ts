/**
 * MuxPlayer hook
 *
 * Mounts the Mux Player web component and bridges playback events
 * to the LiveView server.
 *
 * Dataset attributes:
 *   - data-playback-id: Mux playback ID
 *   - data-video-id: local video record ID
 *
 * Events sent to server:
 *   - "playback_started" { video_id: string, timestamp: number }
 *   - "playback_paused"  { video_id: string, position: number }
 *   - "playback_ended"   { video_id: string }
 *
 * Events received from server:
 *   - "seek_to" { position: number }
 */
const MuxPlayer = {
  mounted() {
    // Initialize Mux Player and bind event listeners
  },

  destroyed() {
    // Clean up event listeners
  },
}

export default MuxPlayer
