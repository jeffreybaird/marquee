import { readFileSync } from "node:fs"
import { resolve } from "node:path"
import { describe, expect, it } from "vitest"

import { CONTENT_TOUR_STEPS, PAGE_TOURS } from "../../js/tour/steps"

/**
 * Per-page tours are pure data, so these tests pin down their shape: each tour
 * opens with a centered welcome and closes with a centered finish, every middle
 * step is anchored to an in-page `data-test` element, and (for the content
 * tour) those anchors are read from the page's own template source so a renamed
 * `data-test` fails here rather than as a mis-positioned tooltip in production.
 */

const anchorTestId = (selector: string) => selector.match(/\[data-test='([^']+)'\]/)?.[1]

describe("PAGE_TOURS", () => {
  it("registers each tour under a page key", () => {
    expect(Object.keys(PAGE_TOURS)).toContain("content")
    expect(PAGE_TOURS.content).toBe(CONTENT_TOUR_STEPS)
  })

  for (const [page, steps] of Object.entries(PAGE_TOURS)) {
    describe(`${page} tour`, () => {
      const first = steps[0]
      const last = steps[steps.length - 1]
      const middle = steps.slice(1, -1)

      it("has unique step ids", () => {
        const ids = steps.map((s) => s.id)
        expect(new Set(ids).size).toBe(ids.length)
      })

      it("opens with a centered welcome that only moves forward", () => {
        expect(first.attachTo).toBeUndefined()
        expect(first.buttons).toEqual(["next"])
      })

      it("closes with a centered step that only finishes", () => {
        expect(last.attachTo).toBeUndefined()
        expect(last.buttons).toEqual(["finish"])
      })

      it("anchors every middle step to an in-page data-test element", () => {
        for (const step of middle) {
          expect(step.attachTo, step.id).toBeDefined()
          expect(anchorTestId(step.attachTo!.element), step.id).toBeDefined()
          expect(step.buttons, step.id).toEqual(["back", "next"])
        }
      })

      it("never leaks a placeholder into the copy", () => {
        for (const step of steps) {
          for (const copy of [step.title, step.text]) {
            const text = typeof copy === "function" ? copy("Acme") : copy
            expect(text, step.id).not.toMatch(/\$\{|undefined/)
          }
        }
      })
    })
  }

  it("only anchors the content tour to data-test ids that exist on the content page", () => {
    const source = readFileSync(
      resolve(__dirname, "../../../lib/marquee_web/live/admin/content_live/components.ex"),
      "utf8",
    )
    const testIds = new Set(
      Array.from(source.matchAll(/data[-_]test="([a-z-]+)"/g), (m) => m[1]),
    )

    for (const step of CONTENT_TOUR_STEPS) {
      if (!step.attachTo) continue
      const id = anchorTestId(step.attachTo.element)
      expect(id, step.id).toBeDefined()
      expect(testIds.has(id!), `${step.id} anchors to missing ${id}`).toBe(true)
    }
  })
})
