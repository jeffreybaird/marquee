import { beforeEach, describe, expect, it, vi } from "vitest"

import { initializeDemoBanners } from "../js/demo_banner"

function renderBanner(key: string): HTMLElement {
  document.body.innerHTML = `<aside data-demo-banner-key="${key}"><button type="button" data-demo-banner-dismiss><span>Dismiss</span></button></aside>`
  return document.querySelector<HTMLElement>("[data-demo-banner-key]")!
}

describe("demo banner dismissal", () => {
  beforeEach(() => {
    sessionStorage.clear()
    document.body.innerHTML = ""
  })

  it("dismisses immediately and restores dismissal after navigation and repeated initialization", () => {
    const banner = renderBanner("subscriber:viewer-1")
    initializeDemoBanners()
    initializeDemoBanners()
    banner.querySelector<HTMLElement>("span")!.click()
    expect(banner.hidden).toBe(true)

    const replacement = renderBanner("subscriber:viewer-1")
    window.dispatchEvent(new Event("phx:page-loading-stop"))
    expect(replacement.hidden).toBe(true)
    initializeDemoBanners()
    expect(replacement.hidden).toBe(true)
  })

  it("keeps a replaced LiveView banner hidden", async () => {
    const banner = renderBanner("subscriber:viewer-1")
    initializeDemoBanners()
    banner.querySelector<HTMLButtonElement>("button")!.click()
    const replacement = renderBanner("subscriber:viewer-1")
    await vi.waitFor(() => expect(replacement.hidden).toBe(true))
  })

  it("shows another demo identity and another banner type", () => {
    const banner = renderBanner("subscriber:viewer-1")
    initializeDemoBanners()
    banner.querySelector<HTMLButtonElement>("button")!.click()

    const nextDemo = renderBanner("subscriber:viewer-2")
    initializeDemoBanners()
    expect(nextDemo.hidden).toBe(false)

    const admin = renderBanner("admin:org-1")
    initializeDemoBanners()
    expect(admin.hidden).toBe(false)
  })

  it("shows the banner in a fresh browser session", () => {
    const banner = renderBanner("admin:org-1")
    initializeDemoBanners()
    banner.querySelector<HTMLButtonElement>("button")!.click()
    sessionStorage.clear()
    const fresh = renderBanner("admin:org-1")
    initializeDemoBanners()
    expect(fresh.hidden).toBe(false)
  })

  it("still dismisses when browser storage cannot be read or written", () => {
    vi.spyOn(Storage.prototype, "getItem").mockImplementation(() => { throw new Error("blocked") })
    vi.spyOn(Storage.prototype, "setItem").mockImplementation(() => { throw new Error("blocked") })
    const banner = renderBanner("subscriber:viewer-1")
    expect(() => initializeDemoBanners()).not.toThrow()
    expect(() => banner.querySelector<HTMLButtonElement>("button")!.click()).not.toThrow()
    expect(banner.hidden).toBe(true)
  })

  it("moves keyboard focus to visible page content after dismissing the focused control", () => {
    const banner = renderBanner("subscriber:viewer-1")
    const main = document.createElement("main")
    document.body.append(main)
    initializeDemoBanners()
    const button = banner.querySelector<HTMLButtonElement>("button")!
    button.focus()
    button.click()
    expect(banner.hidden).toBe(true)
    expect(document.activeElement).toBe(main)
  })
})
