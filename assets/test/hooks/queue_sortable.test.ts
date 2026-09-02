import { afterEach, describe, expect, it } from "vitest"

import QueueSortable from "../../js/hooks/queue_sortable"
import Sortable from "../../vendor/sortable"
import { html, mountHook } from "../support/mount"

const queue = () =>
  html(`
    <ul id="queue">
      <li data-id="a"><span class="sv-queue-drag-handle"></span></li>
      <li data-id="b"><span class="sv-queue-drag-handle"></span></li>
      <li data-id="c"><span class="sv-queue-drag-handle"></span></li>
    </ul>
  `)

describe("QueueSortable", () => {
  afterEach(() => {
    document.body.innerHTML = ""
  })

  it("attaches Sortable to the list, restricted to the drag handles", () => {
    const el = queue()
    mountHook(QueueSortable, el)

    const sortable = Sortable.get(el)
    expect(sortable).toBeDefined()
    expect(sortable!.option("handle")).toBe(".sv-queue-drag-handle")
    expect(sortable!.option("ghostClass")).toBe("sortable-ghost")
  })

  it("reports the new order from the DOM when a drag ends", () => {
    const el = queue()
    const { pushEvent } = mountHook(QueueSortable, el)

    // Simulate Sortable having moved the last item to the front.
    el.prepend(el.lastElementChild!)
    Sortable.get(el)!.option("onEnd")!({} as never)

    expect(pushEvent).toHaveBeenCalledWith("reorder_queue", { ordered_ids: ["c", "a", "b"] })
  })

  it("detaches Sortable when destroyed", () => {
    const el = queue()
    const { hook } = mountHook(QueueSortable, el)

    hook.destroyed()

    expect(Sortable.get(el)).toBeFalsy()
  })
})
