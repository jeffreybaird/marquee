import { afterEach, beforeEach, describe, expect, it, vi } from "vitest"
import MuxPlayer from "../../js/hooks/mux_player"
import { html, mountHook } from "../support/mount"

interface ResumePlayer extends HTMLElement {
  currentTime: number
  duration: number
  paused: boolean
  readyState: number
  play: ReturnType<typeof vi.fn>
}

function playerFixture(readyState: number) {
  const el = html('<div id="resume-player" data-video-id="episode-one" data-resume-position="23.599245"><mux-player></mux-player></div>')
  const player = el.querySelector("mux-player") as unknown as ResumePlayer
  player.currentTime = 0
  player.duration = 71.4
  player.paused = true
  player.readyState = readyState
  player.play = vi.fn()
  return { el, player }
}

describe("MuxPlayer cached metadata resume", () => {
  beforeEach(() => vi.useFakeTimers())
  afterEach(() => {
    vi.useRealTimers()
    document.body.innerHTML = ""
  })

  it("applies saved position when metadata was already loaded before the hook mounted", () => {
    const { el, player } = playerFixture(1)
    const { hook } = mountHook(MuxPlayer, el)
    expect(player.currentTime).toBe(23.599245)
    player.currentTime = 29
    player.dispatchEvent(new Event("loadedmetadata"))
    expect(player.currentTime).toBe(29)
    hook.destroyed()
  })

  it("waits for pending metadata and applies the saved position exactly once", () => {
    const { el, player } = playerFixture(0)
    const { hook } = mountHook(MuxPlayer, el)
    expect(player.currentTime).toBe(0)
    player.readyState = 1
    player.dispatchEvent(new Event("loadedmetadata"))
    expect(player.currentTime).toBe(23.599245)
    player.currentTime = 29
    player.dispatchEvent(new Event("loadedmetadata"))
    expect(player.currentTime).toBe(29)
    hook.destroyed()
  })

  it.each(["load_video", "play_next_in_queue"])("does not miss synchronous metadata during %s", (event) => {
    const { el, player } = playerFixture(1)
    const { hook, serverPush } = mountHook(MuxPlayer, el)
    const originalSetAttribute = player.setAttribute.bind(player)
    vi.spyOn(player, "setAttribute").mockImplementation((name, value) => {
      originalSetAttribute(name, value)
      if (name === "playback-id") {
        player.currentTime = 0
        player.readyState = 1
        player.dispatchEvent(new Event("loadedmetadata"))
      }
    })
    serverPush(event, { video_id: "episode-two", playback_id: "next-playback", resume_position: 12.5 })
    expect(player.currentTime).toBe(12.5)
    hook.destroyed()
  })

  it("does not apply a superseded episode's pending resume to a newly selected episode", () => {
    const { el, player } = playerFixture(0)
    const { hook, serverPush } = mountHook(MuxPlayer, el)
    serverPush("load_video", { video_id: "episode-two", playback_id: "second", resume_position: 12.5 })
    serverPush("load_video", { video_id: "episode-three", playback_id: "third", resume_position: 0 })
    player.readyState = 1
    player.dispatchEvent(new Event("loadedmetadata"))
    expect(player.currentTime).toBe(0)
    hook.destroyed()
  })
})
