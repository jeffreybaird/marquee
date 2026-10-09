/**
 * ScrollToCurrentEpisode hook
 *
 * Used by: WatchLive season section
 *
 * On mount and update, scrolls the episode list so the currently-playing
 * episode row is visible. The hook element is the list's own scroll
 * container (`overflow-y: auto`), and it is the only thing scrolled: the
 * row's position is computed relative to the container and applied with
 * `this.el.scrollTo`, so the page viewport (and the player above the list)
 * is unaffected. Rows already fully visible are left alone.
 *
 * Dataset attributes:
 *   - data-current-video-id: The ID of the video currently playing
 */
import { ViewHook } from "phoenix_live_view"

class ScrollToCurrentEpisode extends ViewHook {
  mounted() {
    this.revealCurrentRow()
  }

  updated() {
    this.revealCurrentRow()
  }

  private revealCurrentRow() {
    const currentVideoId = this.el.dataset.currentVideoId
    if (!currentVideoId) return

    const currentRow = this.el.querySelector<HTMLElement>(
      `[data-test="episode-row-${currentVideoId}"]`,
    )
    if (!currentRow) return

    requestAnimationFrame(() => {
      const list = this.el
      const listRect = list.getBoundingClientRect()
      const rowRect = currentRow.getBoundingClientRect()

      const rowTop = rowRect.top - listRect.top + list.scrollTop
      const rowBottom = rowTop + rowRect.height
      const visibleBottom = list.scrollTop + list.clientHeight

      if (rowTop < list.scrollTop) {
        list.scrollTo({ top: rowTop, behavior: "smooth" })
      } else if (rowBottom > visibleBottom) {
        list.scrollTo({ top: rowBottom - list.clientHeight, behavior: "smooth" })
      }
    })
  }
}

export default ScrollToCurrentEpisode
