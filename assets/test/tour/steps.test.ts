import { readFileSync } from "node:fs"
import { resolve } from "node:path"
import { describe, expect, it } from "vitest"

import { ADMIN_TOUR_STEPS } from "../../js/tour/steps"

/**
 * The step data is pure, so these tests pin down its shape: every anchor must
 * exist in the admin sidebar, and the button sets must let the operator move
 * forward from the first step, back from every middle step, and finish at the
 * end. The sidebar anchors are read from the layout source so a renamed
 * `data_test` fails here rather than as a mis-positioned tooltip in production.
 */
const adminLayout = readFileSync(
  resolve(__dirname, "../../../lib/marquee_web/components/admin_layout.ex"),
  "utf8",
)

// The layout writes test ids both as a component attr (`data_test=`) and as a
// plain HTML attribute (`data-test=`).
const sidebarTestIds = new Set(
  Array.from(adminLayout.matchAll(/data[-_]test="(admin-[a-z-]+)"/g), (m) => m[1]),
)

const anchorTestId = (selector: string) => selector.match(/\[data-test='([^']+)'\]/)?.[1]

describe("ADMIN_TOUR_STEPS", () => {
  const first = ADMIN_TOUR_STEPS[0]
  const last = ADMIN_TOUR_STEPS[ADMIN_TOUR_STEPS.length - 1]
  const middle = ADMIN_TOUR_STEPS.slice(1, -1)

  it("has unique ids", () => {
    const ids = ADMIN_TOUR_STEPS.map((s) => s.id)
    expect(new Set(ids).size).toBe(ids.length)
  })

  it("opens with a centered welcome step that only moves forward", () => {
    expect(first.id).toBe("welcome")
    expect(first.attachTo).toBeUndefined()
    expect(first.buttons).toEqual(["next"])
  })

  it("closes with a centered step that only finishes", () => {
    expect(last.id).toBe("done")
    expect(last.attachTo).toBeUndefined()
    expect(last.buttons).toEqual(["finish"])
  })

  it("anchors every middle step to the right of a sidebar element", () => {
    for (const step of middle) {
      expect(step.attachTo, step.id).toBeDefined()
      expect(step.attachTo!.on, step.id).toBe("right")
    }
  })

  it("only anchors to data-test ids that exist in the admin sidebar", () => {
    expect(sidebarTestIds.size).toBeGreaterThan(0)
    for (const step of middle) {
      const id = anchorTestId(step.attachTo!.element)
      expect(id, step.id).toBeDefined()
      expect(sidebarTestIds.has(id!), `${step.id} anchors to missing ${id}`).toBe(true)
    }
  })

  it("lets the operator go back from every step after the first anchored one", () => {
    const [firstAnchored, ...rest] = middle
    expect(firstAnchored.buttons).toEqual(["next"])
    for (const step of rest) {
      expect(step.buttons, step.id).toEqual(["back", "next"])
    }
  })

  it("greets the operator by brand and never mentions a placeholder", () => {
    for (const step of ADMIN_TOUR_STEPS) {
      for (const copy of [step.title, step.text]) {
        const text = typeof copy === "function" ? copy("Acme") : copy
        expect(text, step.id).not.toMatch(/\$\{|undefined/)
      }
    }
    expect(typeof first.title).toBe("function")
  })
})
