import { afterEach, beforeEach, describe, expect, it, vi } from "vitest"

import MuxPlayer from "../../js/hooks/mux_player"
import { html, mountHook } from "../support/mount"

/** A stand-in for the <mux-player> web component: just the properties the hook reads. */
interface FakePlayer extends HTMLElement {
  currentTime: number
  duration: number
  paused: boolean
  play: ReturnType<typeof vi.fn>
}

function watchPage(attrs = "") {
  const el = html(`<div id="player-wrap" data-video-id="vid-1" ${attrs}><mux-player></mux-player></div>`)
  const player = el.querySelector("mux-player") as unknown as FakePlayer
  player.currentTime = 0
  player.duration = 0
  player.paused = true
  player.play = vi.fn()
  const mounted = mountHook(MuxPlayer, el)
  return { ...mounted, el, player }
}

function setVisibility(state: "visible" | "hidden") {
  Object.defineProperty(document, "visibilityState", { value: state, configurable: true })
  document.dispatchEvent(new Event("visibilitychange"))
}

/** Advance the clock and play `seconds` of video. */
function play(player: FakePlayer, seconds: number) {
  player.paused = false
  player.currentTime += seconds
  player.dispatchEvent(new Event("timeupdate"))
  vi.advanceTimersByTime(seconds * 1000)
}

describe("MuxPlayer", () => {
  beforeEach(() => {
    vi.useFakeTimers()
    // No jitter: the progress interval starts immediately.
    vi.spyOn(Math, "random").mockReturnValue(0)
    Object.defineProperty(document, "visibilityState", { value: "visible", configurable: true })
  })

  afterEach(() => {
    vi.useRealTimers()
    document.body.innerHTML = ""
  })

  it("does nothing without a <mux-player> child", () => {
    const el = html(`<div id="empty" data-video-id="vid-1"></div>`)
    const { hook, pushEvent, handledEvents } = mountHook(MuxPlayer, el)

    hook.destroyed()

    expect(handledEvents()).toEqual([])
    expect(pushEvent).not.toHaveBeenCalled()
  })

  it("seeks to data-resume-position once metadata loads", () => {
    const { player } = watchPage(`data-resume-position="42.5"`)

    player.dispatchEvent(new Event("loadedmetadata"))
    expect(player.currentTime).toBe(42.5)

    player.currentTime = 10
    player.dispatchEvent(new Event("loadedmetadata"))
    expect(player.currentTime).toBe(10)
  })

  it("reports playback_started on play", () => {
    const { player, pushEvent } = watchPage()

    player.dispatchEvent(new Event("play"))

    expect(pushEvent).toHaveBeenCalledWith("playback_started", { video_id: "vid-1" })
  })

  it("reports progress every 30s while playing, and not while paused", () => {
    const { player, pushEvent } = watchPage()

    play(player, 30)
    expect(pushEvent).toHaveBeenCalledTimes(1)
    expect(pushEvent).toHaveBeenCalledWith("playback_progress", { video_id: "vid-1", position: 30 })

    play(player, 30)
    expect(pushEvent).toHaveBeenCalledTimes(2)
    expect(pushEvent).toHaveBeenLastCalledWith("playback_progress", { video_id: "vid-1", position: 60 })

    player.paused = true
    vi.advanceTimersByTime(60_000)
    expect(pushEvent).toHaveBeenCalledTimes(2)
  })

  it("throttles duplicate progress reports but always reports a pause", () => {
    const { player, pushEvent } = watchPage()
    play(player, 30)
    pushEvent.mockClear()

    // 5s later, 5s further: too soon and too close to the last report.
    player.currentTime += 5
    vi.advanceTimersByTime(5000)
    setVisibility("hidden")
    expect(pushEvent).not.toHaveBeenCalledWith("playback_progress", expect.anything())

    player.dispatchEvent(new Event("pause"))
    expect(pushEvent).toHaveBeenCalledWith("playback_paused", { video_id: "vid-1", position: 35 })
  })

  it("flushes progress when the page is hidden after a real seek", () => {
    const { player, pushEvent } = watchPage()
    play(player, 30)
    pushEvent.mockClear()

    player.currentTime = 200
    setVisibility("hidden")

    expect(pushEvent).toHaveBeenCalledWith("playback_progress", { video_id: "vid-1", position: 200 })
  })

  it("never reports a zero position", () => {
    const { player, pushEvent } = watchPage()

    player.dispatchEvent(new Event("pause"))
    vi.advanceTimersByTime(60_000)

    expect(pushEvent).not.toHaveBeenCalled()
  })

  it("reports playback_ended and suppresses the drop-off for a finished video", () => {
    const { player, pushEvent } = watchPage()
    player.duration = 100
    player.dispatchEvent(new Event("loadedmetadata"))
    play(player, 100)
    pushEvent.mockClear()

    player.dispatchEvent(new Event("ended"))
    expect(pushEvent).toHaveBeenCalledWith("playback_ended", { video_id: "vid-1" })

    player.paused = true
    setVisibility("hidden")
    expect(pushEvent).not.toHaveBeenCalledWith("playback_drop_off", expect.anything())
  })

  it("sends one drop-off per backgrounding with the furthest position watched", () => {
    const { player, pushEvent } = watchPage()
    player.duration = 600
    player.dispatchEvent(new Event("loadedmetadata"))
    player.currentTime = 120
    player.dispatchEvent(new Event("timeupdate"))
    player.currentTime = 90
    player.dispatchEvent(new Event("timeupdate"))
    player.paused = true

    setVisibility("hidden")
    expect(pushEvent).toHaveBeenCalledWith("playback_drop_off", {
      video_id: "vid-1",
      max_position: 120,
      video_duration: 600,
    })

    window.dispatchEvent(new Event("pagehide"))
    expect(pushEvent).toHaveBeenCalledTimes(1)

    setVisibility("visible")
    setVisibility("hidden")
    expect(pushEvent).toHaveBeenCalledTimes(2)
  })

  it("does not send a drop-off before anything was watched", () => {
    const { pushEvent } = watchPage()

    setVisibility("hidden")

    expect(pushEvent).not.toHaveBeenCalled()
  })

  it("applies a server seek", () => {
    const { player, serverPush } = watchPage()

    serverPush("seek_to", { position: 77 })

    expect(player.currentTime).toBe(77)
  })

  it.each(["load_video", "play_next_in_queue"])(
    "%s closes out the current video and loads the next one",
    (event) => {
      const { player, pushEvent, serverPush } = watchPage()
      player.duration = 300
      player.dispatchEvent(new Event("loadedmetadata"))
      player.currentTime = 50
      player.dispatchEvent(new Event("timeupdate"))
      player.paused = true

      serverPush(event, { playback_id: "pb-2", video_id: "vid-2", resume_position: 12 })

      expect(pushEvent).toHaveBeenCalledWith("playback_drop_off", {
        video_id: "vid-1",
        max_position: 50,
        video_duration: 300,
      })
      expect(player.getAttribute("playback-id")).toBe("pb-2")

      player.duration = 200
      player.dispatchEvent(new Event("loadedmetadata"))
      expect(player.currentTime).toBe(12)

      player.currentTime = 20
      player.dispatchEvent(new Event("timeupdate"))
      setVisibility("hidden")
      expect(pushEvent).toHaveBeenLastCalledWith("playback_drop_off", {
        video_id: "vid-2",
        max_position: 20,
        video_duration: 200,
      })
      expect(player.play).toHaveBeenCalledTimes(event === "play_next_in_queue" ? 1 : 0)
    },
  )

  it("does not seek when the next video has no resume position", () => {
    const { player, serverPush } = watchPage()
    player.currentTime = 5

    serverPush("load_video", { playback_id: "pb-2", video_id: "vid-2", resume_position: 0 })
    player.dispatchEvent(new Event("loadedmetadata"))

    expect(player.currentTime).toBe(5)
  })

  it("flushes progress and the drop-off on destroy, then stops reporting", () => {
    const { hook, player, pushEvent } = watchPage()
    player.duration = 100
    player.dispatchEvent(new Event("loadedmetadata"))
    play(player, 10)
    expect(pushEvent).not.toHaveBeenCalled()

    hook.destroyed()

    expect(pushEvent).toHaveBeenCalledWith("playback_progress", { video_id: "vid-1", position: 10 })
    expect(pushEvent).toHaveBeenCalledWith("playback_drop_off", {
      video_id: "vid-1",
      max_position: 10,
      video_duration: 100,
    })
    pushEvent.mockClear()

    play(player, 60)
    setVisibility("hidden")
    window.dispatchEvent(new Event("pagehide"))
    expect(pushEvent).not.toHaveBeenCalled()
  })
})
