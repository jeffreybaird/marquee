/**
 * QueueSortable hook
 *
 * Used by: WatchlistLive (queue tab), WatchLive (queue panel)
 *
 * Enables drag-and-drop reordering of the playback queue using Sortable.js.
 *
 * Events sent to server:
 *   - "reorder_queue" { ordered_ids: string[] }
 */
import { ViewHook } from "phoenix_live_view"
import Sortable from "../../vendor/sortable"

class QueueSortable extends ViewHook {
  private sortable: Sortable | null = null

  mounted() {
    this.sortable = new Sortable(this.el, {
      animation: 150,
      handle: ".sv-queue-drag-handle",
      ghostClass: "sortable-ghost",
      onEnd: () => {
        const items = Array.from(this.el.children).map(
          (el: Element) => (el as HTMLElement).dataset.id,
        )
        this.pushEvent("reorder_queue", { ordered_ids: items })
      },
    })
  }

  destroyed() {
    if (this.sortable) {
      this.sortable.destroy()
    }
  }
}

export default QueueSortable
