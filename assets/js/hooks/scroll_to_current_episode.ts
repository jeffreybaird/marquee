/**
 * ScrollToCurrentEpisode hook
 *
 * Used by: WatchLive season section
 *
 * On mount, scrolls the episode list so the currently-playing episode
 * row is visible. Uses `scrollIntoView` with smooth behavior.
 *
 * Dataset attributes:
 *   - data-current-video-id: The ID of the video currently playing
 */
import { ViewHook } from "phoenix_live_view"

class ScrollToCurrentEpisode extends ViewHook {
  mounted() {
    const currentVideoId = this.el.dataset.currentVideoId
    if (!currentVideoId) return

    const currentRow = this.el.querySelector(
      `[data-test="episode-row-${currentVideoId}"]`,
    )

    if (currentRow) {
      requestAnimationFrame(() => {
        currentRow.scrollIntoView({ behavior: "smooth", block: "nearest" })
      })
    }
  }

  updated() {
    const currentVideoId = this.el.dataset.currentVideoId
    if (!currentVideoId) return

    const currentRow = this.el.querySelector(
      `[data-test="episode-row-${currentVideoId}"]`,
    )

    if (currentRow) {
      requestAnimationFrame(() => {
        currentRow.scrollIntoView({ behavior: "smooth", block: "nearest" })
      })
    }
  }
}

export default ScrollToCurrentEpisode
