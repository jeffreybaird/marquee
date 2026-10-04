import { afterEach, describe, expect, it, vi } from "vitest"
import MuxPlayer from "../../js/hooks/mux_player"
import { html, mountHook } from "../support/mount"

describe("MuxPlayer episode navigation", () => {
  afterEach(() => {
    document.body.innerHTML = ""
    vi.useRealTimers()
  })

  it("saves the outgoing episode's short playback before replaying an episode selection", () => {
    vi.useFakeTimers()
    const el = html('<div id="player-wrap" data-video-id="outgoing"><mux-player></mux-player></div>')
    const player = el.querySelector("mux-player") as HTMLElement & { currentTime: number; paused: boolean }
    player.currentTime = 10
    player.paused = false
    const { hook, pushEvent } = mountHook(MuxPlayer, el)
    const button = document.createElement("button")
    button.setAttribute("phx-click", "play_episode")
    button.setAttribute("phx-value-video-id", "next-video")
    document.body.appendChild(button)
    const replay = vi.spyOn(button, "click").mockImplementation(() => {})
    const selection = new MouseEvent("click", { bubbles: true, cancelable: true })
    button.dispatchEvent(selection)
    expect(selection.defaultPrevented).toBe(true)
    expect(replay).not.toHaveBeenCalled()
    expect(pushEvent).toHaveBeenCalledWith(
      "playback_paused",
      { video_id: "outgoing", position: 10 },
      expect.any(Function),
    )
    const calls = pushEvent.mock.calls as unknown as Array<[string, unknown, () => void]>
    calls[0][2]()
    expect(replay).toHaveBeenCalledTimes(1)
    vi.advanceTimersByTime(2000)
    expect(replay).toHaveBeenCalledTimes(1)
    hook.destroyed()
  })
})
