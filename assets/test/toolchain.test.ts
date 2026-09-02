import { describe, expect, it } from "vitest"
import { ViewHook } from "phoenix_live_view"

/**
 * Smoke test for the test toolchain itself: the LiveView client resolves from
 * `deps/` through the vitest alias, and hooks can be instantiated on a jsdom
 * element without a live socket attached.
 */
describe("test toolchain", () => {
  it("resolves phoenix_live_view from deps and mounts a hook in jsdom", () => {
    const el = document.createElement("div")
    el.id = "smoke"
    document.body.appendChild(el)

    const hook = new ViewHook(null, el)

    expect(hook.el).toBe(el)
    expect(hook.el.ownerDocument).toBe(document)
  })
})
