import { afterEach, beforeEach, describe, expect, it, vi } from "vitest"

import CopyToClipboard from "../../js/hooks/copy_to_clipboard"
import { html, mountHook } from "../support/mount"

function stubClipboard(writeText: (text: string) => Promise<void>) {
  Object.defineProperty(navigator, "clipboard", {
    value: { writeText },
    configurable: true,
  })
}

const flush = () => new Promise<void>((resolve) => process.nextTick(resolve))

describe("CopyToClipboard", () => {
  beforeEach(() => {
    vi.useFakeTimers()
    document.execCommand = vi.fn(() => true)
  })

  afterEach(() => {
    vi.useRealTimers()
    document.body.innerHTML = ""
  })

  it("copies data-copy-value and shows the confirmation for 1.5s", async () => {
    const writeText = vi.fn(() => Promise.resolve())
    stubClipboard(writeText)
    const el = html(`<button id="copy" data-copy-value="abc123">Copy link</button>`)
    mountHook(CopyToClipboard, el)

    el.click()
    await flush()

    expect(writeText).toHaveBeenCalledWith("abc123")
    expect(el.textContent).toBe("Copied")

    vi.advanceTimersByTime(1499)
    expect(el.textContent).toBe("Copied")
    vi.advanceTimersByTime(1)
    expect(el.textContent).toBe("Copy link")
  })

  it("uses data-copy-confirm for the confirmation text", async () => {
    stubClipboard(() => Promise.resolve())
    const el = html(
      `<button id="copy" data-copy-value="x" data-copy-confirm="Done!">Copy</button>`,
    )
    mountHook(CopyToClipboard, el)

    el.click()
    await flush()

    expect(el.textContent).toBe("Done!")
  })

  it("falls back to execCommand when the Clipboard API rejects", async () => {
    stubClipboard(() => Promise.reject(new Error("not allowed")))
    const el = html(`<button id="copy" data-copy-value="fallback">Copy</button>`)
    mountHook(CopyToClipboard, el)

    el.click()
    await flush()

    expect(document.execCommand).toHaveBeenCalledWith("copy")
    expect(document.querySelector("textarea")).toBeNull()
    expect(el.textContent).toBe("Copied")
  })

  it("does nothing without a value", async () => {
    const writeText = vi.fn(() => Promise.resolve())
    stubClipboard(writeText)
    const el = html(`<button id="copy">Copy</button>`)
    mountHook(CopyToClipboard, el)

    el.click()
    await flush()

    expect(writeText).not.toHaveBeenCalled()
    expect(el.textContent).toBe("Copy")
  })
})
