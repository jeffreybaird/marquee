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

import Sortable from "../../vendor/sortable"

const QueueSortable = {
  mounted(this: any) {
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
  },

  destroyed(this: any) {
    if (this.sortable) {
      this.sortable.destroy()
    }
  },
}

export default QueueSortable
