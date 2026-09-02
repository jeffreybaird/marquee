import { afterEach, describe, expect, it, vi } from "vitest"

import ScrollToCurrentEpisode from "../../js/hooks/scroll_to_current_episode"
import { html, mountHook } from "../support/mount"

function season(currentId?: string) {
  const attr = currentId === undefined ? "" : `data-current-video-id="${currentId}"`
  const el = html(`
    <section id="season" ${attr}>
      <div data-test="episode-row-e1"></div>
      <div data-test="episode-row-e2"></div>
    </section>
  `)
  const rows = {
    e1: el.querySelector<HTMLElement>("[data-test='episode-row-e1']")!,
    e2: el.querySelector<HTMLElement>("[data-test='episode-row-e2']")!,
  }
  const scrolled = {
    e1: vi.spyOn(rows.e1, "scrollIntoView"),
    e2: vi.spyOn(rows.e2, "scrollIntoView"),
  }
  return { el, rows, scrolled }
}

const nextFrame = () => new Promise<void>((resolve) => requestAnimationFrame(() => resolve()))

describe("ScrollToCurrentEpisode", () => {
  afterEach(() => {
    document.body.innerHTML = ""
  })

  it("scrolls the current episode row into view on the next frame", async () => {
    const { el, scrolled } = season("e2")
    mountHook(ScrollToCurrentEpisode, el)

    expect(scrolled.e2).not.toHaveBeenCalled()
    await nextFrame()

    expect(scrolled.e2).toHaveBeenCalledWith({ behavior: "smooth", block: "nearest" })
    expect(scrolled.e1).not.toHaveBeenCalled()
  })

  it("follows the current episode as it changes on update", async () => {
    const { el, scrolled } = season("e1")
    const { hook } = mountHook(ScrollToCurrentEpisode, el)
    await nextFrame()
    expect(scrolled.e1).toHaveBeenCalledTimes(1)

    el.dataset.currentVideoId = "e2"
    hook.updated()
    await nextFrame()

    expect(scrolled.e2).toHaveBeenCalledTimes(1)
    expect(scrolled.e1).toHaveBeenCalledTimes(1)
  })

  it("does nothing without a current episode or a matching row", async () => {
    const { el, scrolled } = season()
    const { hook } = mountHook(ScrollToCurrentEpisode, el)

    el.dataset.currentVideoId = "missing"
    hook.updated()
    await nextFrame()

    expect(scrolled.e1).not.toHaveBeenCalled()
    expect(scrolled.e2).not.toHaveBeenCalled()
  })
})
