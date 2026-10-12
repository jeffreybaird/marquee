/**
 * ShortsFeed hook contract (issue #16, short-form vertical feed).
 *
 * The hook mounts on the viewer `/shorts` feed container. It decides which
 * clip is active from an IntersectionObserver, keeps at most three
 * `<mux-player>` elements alive (active clip and its two neighbours), drives
 * playback, keyboard navigation and pagination, and reports playback with the
 * same event names, payloads and throttling as `mux_player.ts`.
 *
 * ---------------------------------------------------------------------------
 * Assumed DOM contract (the server must render this shape; see `feed()`):
 *
 *   <section>                                        (any wrapper)
 *     <p data-shorts-live aria-live="polite" class="sr-only"></p>
 *     <button type="button" data-test="shorts-tap-to-play" hidden>Tap to play</button>
 *     <button type="button" data-shorts-prev aria-label="Previous clip">...</button>
 *     <button type="button" data-shorts-next aria-label="Next clip">...</button>
 *     <div id="shorts-feed" phx-hook="ShortsFeed" role="feed" aria-label="Shorts"
 *          aria-busy="false" data-has-more="true|false" tabindex="0">
 *       <!-- one per clip, streamed; direct children of the feed -->
 *       <article id="shorts-v1" tabindex="-1" data-index="0" data-video-id="v1"
 *                data-playback-id="pb-1"            (ONLY when the clip is playable)
 *                data-orientation="portrait" aria-posinset="1" aria-setsize="10"
 *                aria-labelledby="short-title-v1">
 *         <!-- media box: carries the clip's own ratio; the article is the stage -->
 *         <div data-short-media style="aspect-ratio: 9 / 16">
 *           <img data-short-poster alt="Short 1" src="...">
 *           <div id="short-player-v1" data-player-slot phx-update="ignore"></div>  (ONLY when playable)
 *         </div>
 *         <a href="/subscribe" data-test="short-locked-v1">...</a>  (ONLY when locked, outside the box)
 *         <h2 id="short-title-v1">Short 1</h2>
 *         <button type="button" data-shorts-toggle-play aria-pressed="false" aria-label="Play">...</button>
 *         <button type="button" data-shorts-toggle-mute aria-pressed="false" aria-label="Mute">...</button>
 *         <div data-test="short-error-v1" role="alert" hidden>
 *           <p>This clip could not be played.</p>
 *           <button type="button" data-shorts-retry>Retry</button>
 *         </div>
 *       </article>
 *     </div>
 *   </section>
 *
 * Hook-side expectations on that DOM:
 *   - The tap-to-play button, the Previous/Next buttons and the
 *     `[data-shorts-live]` live region sit
 *     OUTSIDE the feed (the feed's children are stream items); the hook finds
 *     them in `document`.
 *   - Players are created with `document.createElement("mux-player")`,
 *     carry `playback-id` (from `data-playback-id`) and `playsinline`
 *     attributes, and are appended inside the clip's `[data-player-slot]`.
 *     Neighbours get `preload="metadata"`; the active player loops.
 *   - Autoplay blocked: feed gets `data-autoplay="blocked"`, tap-to-play loses
 *     `hidden`. Playback error: the article gets `data-state="error"` and its
 *     `[data-test="short-error-{id}"]` panel loses `hidden`.
 *   - The live region announces "Clip N of M: title" (M = aria-setsize,
 *     title = text of the aria-labelledby element).
 * ---------------------------------------------------------------------------
 */
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest"

import ShortsFeed from "../../js/hooks/shorts_feed"
import { setReducedMotion } from "../support/media"
import { html, mountHook } from "../support/mount"

// ---------------------------------------------------------------------------
// Fake IntersectionObserver
//
// jsdom has no layout engine and no IntersectionObserver. Tests decide what is
// visible with `trigger(el, ratio)` / `triggerMany([[el, ratio], ...])`. Only
// elements an observer is currently observing are reported to it, so a hook
// that forgets to observe a newly streamed clip, or that already disconnected,
// hears nothing.
//
// (Kept in this file: the repository's hook policy classifies
// `assets/test/support/*.ts` as source, not test.)
// ---------------------------------------------------------------------------
type IOEntry = [Element, number]

class FakeIntersectionObserver {
  static instances: FakeIntersectionObserver[] = []

  readonly root: Element | Document | null
  readonly rootMargin: string
  readonly thresholds: ReadonlyArray<number>
  readonly observed = new Set<Element>()
  disconnected = false

  constructor(
    private readonly callback: IntersectionObserverCallback,
    options: IntersectionObserverInit = {},
  ) {
    this.root = options.root ?? null
    this.rootMargin = options.rootMargin ?? "0px"
    const threshold = options.threshold ?? 0
    this.thresholds = Array.isArray(threshold) ? threshold : [threshold]
    FakeIntersectionObserver.instances.push(this)
  }

  observe(el: Element): void {
    this.disconnected = false
    this.observed.add(el)
  }

  unobserve(el: Element): void {
    this.observed.delete(el)
  }

  disconnect(): void {
    this.observed.clear()
    this.disconnected = true
  }

  takeRecords(): IntersectionObserverEntry[] {
    return []
  }

  deliver(entries: IOEntry[]): void {
    const mine = entries.filter(([el]) => this.observed.has(el))
    if (mine.length === 0) return
    this.callback(
      mine.map(([target, ratio]) => {
        const rect = target.getBoundingClientRect()
        return {
          target,
          intersectionRatio: ratio,
          isIntersecting: ratio > 0,
          boundingClientRect: rect,
          intersectionRect: rect,
          rootBounds: null,
          time: Date.now(),
        } as IntersectionObserverEntry
      }),
      this as unknown as IntersectionObserver,
    )
  }
}

const io = {
  install() {
    FakeIntersectionObserver.instances = []
    vi.stubGlobal("IntersectionObserver", FakeIntersectionObserver)
  },
  uninstall() {
    vi.unstubAllGlobals()
    FakeIntersectionObserver.instances = []
  },
  trigger(el: Element, ratio: number) {
    io.triggerMany([[el, ratio]])
  },
  triggerMany(entries: IOEntry[]) {
    for (const observer of FakeIntersectionObserver.instances) {
      if (!observer.disconnected) observer.deliver(entries)
    }
  },
  isObserved(el: Element) {
    return FakeIntersectionObserver.instances.some((o) => !o.disconnected && o.observed.has(el))
  },
  allDisconnected() {
    return FakeIntersectionObserver.instances.every((o) => o.disconnected || o.observed.size === 0)
  },
}

// ---------------------------------------------------------------------------
// Fake <mux-player>
//
// `play()` records whether the player was muted at call time and settles with
// whatever `playImpl` returns, so a test can reject with NotAllowedError and
// then accept the muted retry. A resolved play flips `paused` and fires
// `play`; `pause()` on a playing player fires `pause`, like a media element.
// ---------------------------------------------------------------------------
let playImpl: (player: FakeMuxPlayer) => Promise<void> = () => Promise.resolve()

const isMuted = (p: FakeMuxPlayer) => p.muted === true || p.hasAttribute("muted")
const isLooping = (p: FakeMuxPlayer) => p.loop === true || p.hasAttribute("loop")

class FakeMuxPlayer extends HTMLElement {
  paused = true
  muted = false
  loop = false
  ended = false
  currentTime = 0
  duration = 0
  readyState = 0
  volume = 1
  playbackId = ""
  playCalls: Array<{ muted: boolean }> = []

  play = vi.fn((): Promise<void> => {
    this.playCalls.push({ muted: isMuted(this) })
    return playImpl(this).then(() => {
      this.paused = false
      this.dispatchEvent(new Event("play"))
    })
  })

  pause = vi.fn((): void => {
    if (this.paused) return
    this.paused = true
    this.dispatchEvent(new Event("pause"))
  })
}

if (!customElements.get("mux-player")) customElements.define("mux-player", FakeMuxPlayer)

const notAllowed = () => Promise.reject(new DOMException("play() needs a user gesture", "NotAllowedError"))
const notSupported = () => Promise.reject(new DOMException("no supported source", "NotSupportedError"))

// ---------------------------------------------------------------------------
// Fixture
// ---------------------------------------------------------------------------
interface FeedOptions {
  count?: number
  hasMore?: boolean
  locked?: number[]
  setsize?: number
}

function articleMarkup(i: number, setsize: number, locked: boolean): string {
  const id = `v${i + 1}`
  const playable = locked ? "" : `data-playback-id="pb-${i + 1}"`
  const slot = locked ? "" : `<div id="short-player-${id}" data-player-slot phx-update="ignore"></div>`
  const cta = locked ? `<a href="/subscribe" data-test="short-locked-${id}">Subscribe to watch</a>` : ""
  return `
    <article id="shorts-${id}" tabindex="-1" data-index="${i}" data-video-id="${id}" ${playable}
             data-orientation="portrait" aria-posinset="${i + 1}" aria-setsize="${setsize}"
             aria-labelledby="short-title-${id}">
      <div data-short-media style="aspect-ratio: 9 / 16">
        <img data-short-poster alt="Short ${i + 1}" src="/images/placeholder.svg">
        ${slot}
      </div>
      ${cta}
      <h2 id="short-title-${id}">Short ${i + 1}</h2>
      <button type="button" data-shorts-toggle-play aria-pressed="false" aria-label="Play">Play</button>
      <button type="button" data-shorts-toggle-mute aria-pressed="false" aria-label="Mute">Mute</button>
      <div data-test="short-error-${id}" role="alert" hidden>
        <p>This clip could not be played.</p>
        <button type="button" data-shorts-retry>Retry</button>
      </div>
    </article>`
}

function feed(options: FeedOptions = {}) {
  const count = options.count ?? 10
  const setsize = options.setsize ?? count
  const locked = new Set(options.locked ?? [])
  const articles = Array.from({ length: count }, (_, i) => articleMarkup(i, setsize, locked.has(i))).join("")

  const wrapper = html(`
    <section id="shorts-page">
      <p data-shorts-live aria-live="polite" class="sr-only"></p>
      <button type="button" data-test="shorts-tap-to-play" hidden>Tap to play</button>
      <button type="button" data-shorts-prev aria-label="Previous clip">Previous</button>
      <button type="button" data-shorts-next aria-label="Next clip">Next</button>
      <div id="shorts-feed" phx-hook="ShortsFeed" role="feed" aria-label="Shorts"
           aria-busy="false" data-has-more="${options.hasMore ? "true" : "false"}" tabindex="0">
        ${articles}
      </div>
    </section>
  `)
  document.body.appendChild(wrapper)
  const el = wrapper.querySelector<HTMLElement>("#shorts-feed")!
  const mounted = mountHook(ShortsFeed, el)
  return {
    ...mounted,
    el,
    tapToPlay: wrapper.querySelector<HTMLButtonElement>('[data-test="shorts-tap-to-play"]')!,
    liveRegion: wrapper.querySelector<HTMLElement>("[data-shorts-live]")!,
    prevButton: wrapper.querySelector<HTMLButtonElement>("[data-shorts-prev]")!,
    nextButton: wrapper.querySelector<HTMLButtonElement>("[data-shorts-next]")!,
  }
}

const articles = (el: HTMLElement) => Array.from(el.querySelectorAll<HTMLElement>("article"))
const article = (el: HTMLElement, index: number) => articles(el)[index]!
const players = (el: HTMLElement) => Array.from(el.querySelectorAll<FakeMuxPlayer>("mux-player"))
const playerIn = (art: HTMLElement) => art.querySelector<FakeMuxPlayer>("mux-player")
const playerAt = (el: HTMLElement, index: number) => playerIn(article(el, index))!
const indexesWithPlayers = (el: HTMLElement) =>
  articles(el)
    .filter((a) => playerIn(a) !== null)
    .map((a) => Number(a.dataset.index))
const errorPanel = (art: HTMLElement) =>
  art.querySelector<HTMLElement>(`[data-test="short-error-${art.dataset.videoId}"]`)!

/** Let rejected/resolved play() promises and their handlers run. */
async function flush(): Promise<void> {
  for (let i = 0; i < 20; i++) await Promise.resolve()
}

/** Make clip `index` the most visible one, the way scrolling to it would. */
async function activate(el: HTMLElement, index: number, previous?: number): Promise<void> {
  const entries: IOEntry[] = [[article(el, index), 1]]
  if (previous !== undefined) entries.push([article(el, previous), 0])
  io.triggerMany(entries)
  await flush()
}

function key(target: HTMLElement, k: string): KeyboardEvent {
  const code = k === " " ? "Space" : k.length === 1 ? `Key${k.toUpperCase()}` : k
  const event = new KeyboardEvent("keydown", { key: k, code, bubbles: true, cancelable: true })
  target.dispatchEvent(event)
  return event
}

function setVisibility(state: "visible" | "hidden") {
  Object.defineProperty(document, "visibilityState", { value: state, configurable: true })
  Object.defineProperty(document, "hidden", { value: state === "hidden", configurable: true })
  document.dispatchEvent(new Event("visibilitychange"))
}

// ---------------------------------------------------------------------------

describe("ShortsFeed", () => {
  beforeEach(() => {
    io.install()
    setReducedMotion(false)
    playImpl = () => Promise.resolve()
    vi.spyOn(Math, "random").mockReturnValue(0)
    setVisibility("visible")
  })

  afterEach(() => {
    vi.useRealTimers()
    io.uninstall()
    setReducedMotion(false)
    document.body.innerHTML = ""
  })

  describe("activation and the player window", () => {
    it("observes every clip in the feed on mount", () => {
      const { el } = feed()

      for (const art of articles(el)) expect(io.isObserved(art)).toBe(true)
    })

    it("creates players only for the active clip and its neighbours", async () => {
      const { el } = feed()

      await activate(el, 0)
      expect(indexesWithPlayers(el)).toEqual([0, 1])

      await activate(el, 1, 0)
      expect(indexesWithPlayers(el)).toEqual([0, 1, 2])

      await activate(el, 5, 1)
      expect(indexesWithPlayers(el)).toEqual([4, 5, 6])
      expect(players(el).length).toBeLessThanOrEqual(3)
    })

    it("never keeps more than three players while scrolling through the feed", async () => {
      const { el } = feed()

      for (let i = 0; i < 10; i++) {
        await activate(el, i, i === 0 ? undefined : i - 1)
        expect(players(el).length).toBeLessThanOrEqual(3)
        expect(document.querySelectorAll("mux-player").length).toBeLessThanOrEqual(3)
      }
      expect(indexesWithPlayers(el)).toEqual([8, 9])
    })

    it("puts each player in its clip's slot with the clip's playback id", async () => {
      const { el } = feed()

      await activate(el, 1)

      for (const index of [0, 1, 2]) {
        const art = article(el, index)
        const player = playerIn(art)!
        expect(player.parentElement?.hasAttribute("data-player-slot")).toBe(true)
        expect(player.getAttribute("playback-id")).toBe(art.dataset.playbackId)
        expect(player.hasAttribute("playsinline")).toBe(true)
      }
    })

    it("loops the active clip and preloads only metadata for its neighbours", async () => {
      const { el } = feed()

      await activate(el, 1)

      expect(isLooping(playerAt(el, 1))).toBe(true)
      expect(playerAt(el, 0).getAttribute("preload")).toBe("metadata")
      expect(playerAt(el, 2).getAttribute("preload")).toBe("metadata")
    })

    it("plays the active clip and does not play its neighbours", async () => {
      const { el } = feed()

      await activate(el, 1)

      expect(playerAt(el, 1).play).toHaveBeenCalled()
      expect(playerAt(el, 0).play).not.toHaveBeenCalled()
      expect(playerAt(el, 2).play).not.toHaveBeenCalled()
    })

    it("pauses the previously active clip when another becomes active", async () => {
      const { el } = feed()
      await activate(el, 0)
      const first = playerAt(el, 0)
      expect(first.paused).toBe(false)

      await activate(el, 1, 0)

      expect(first.pause).toHaveBeenCalled()
      expect(first.paused).toBe(true)
      expect(playerAt(el, 1).play).toHaveBeenCalled()
      expect(playerAt(el, 1).paused).toBe(false)
    })

    it("never creates a player for a locked clip (no data-playback-id)", async () => {
      const { el } = feed({ locked: [1] })

      await activate(el, 0)
      expect(playerIn(article(el, 1))).toBeNull()

      await activate(el, 1, 0)
      expect(playerIn(article(el, 1))).toBeNull()
      expect(indexesWithPlayers(el)).toEqual([0, 2])
      expect(playerAt(el, 0).paused).toBe(true)
    })

    it("pushes playback_clip_activated with the video id once per activation", async () => {
      const { el, pushEvent } = feed()

      await activate(el, 0)
      expect(pushEvent).toHaveBeenCalledWith("playback_clip_activated", { video_id: "v1" })

      // The same clip reported visible again is not a new activation.
      await activate(el, 0)
      const activations = () => pushEvent.mock.calls.filter(([event]) => event === "playback_clip_activated")
      expect(activations()).toHaveLength(1)

      await activate(el, 1, 0)
      expect(pushEvent).toHaveBeenCalledWith("playback_clip_activated", { video_id: "v2" })
      expect(activations()).toHaveLength(2)
    })

    it("announces the active clip in the live region", async () => {
      const { el, liveRegion } = feed()

      await activate(el, 1)

      expect(liveRegion.textContent).toContain("Clip 2 of 10: Short 2")
    })
  })

  describe("autoplay restrictions and errors", () => {
    it("retries a NotAllowedError muted and keeps playing muted when that succeeds", async () => {
      let calls = 0
      playImpl = () => (++calls === 1 ? notAllowed() : Promise.resolve())
      const { el, tapToPlay } = feed()

      await activate(el, 0)

      const player = playerAt(el, 0)
      expect(player.playCalls).toHaveLength(2)
      expect(player.playCalls[0]!.muted).toBe(false)
      expect(player.playCalls[1]!.muted).toBe(true)
      expect(player.paused).toBe(false)
      expect(el.dataset.autoplay).not.toBe("blocked")
      expect(tapToPlay.hidden).toBe(true)
    })

    it("shows tap-to-play when even the muted retry is refused, and plays on tap", async () => {
      playImpl = notAllowed
      const { el, tapToPlay } = feed()

      await activate(el, 0)

      const player = playerAt(el, 0)
      expect(player.playCalls).toHaveLength(2)
      expect(player.playCalls[1]!.muted).toBe(true)
      expect(el.dataset.autoplay).toBe("blocked")
      expect(tapToPlay.hidden).toBe(false)
      expect(article(el, 0).dataset.state).not.toBe("error")

      playImpl = () => Promise.resolve()
      tapToPlay.click()
      await flush()

      expect(player.play).toHaveBeenCalledTimes(3)
      expect(player.paused).toBe(false)
      expect(el.dataset.autoplay).not.toBe("blocked")
      expect(tapToPlay.hidden).toBe(true)
    })

    it("marks the clip errored and shows its error panel when play fails for another reason", async () => {
      playImpl = notSupported
      const { el, tapToPlay } = feed()

      await activate(el, 0)

      const art = article(el, 0)
      expect(playerAt(el, 0).playCalls).toHaveLength(1)
      expect(art.dataset.state).toBe("error")
      expect(errorPanel(art).hidden).toBe(false)
      expect(tapToPlay.hidden).toBe(true)
      expect(el.dataset.autoplay).not.toBe("blocked")
    })

    it("marks the clip errored when its player fires an error event", async () => {
      const { el } = feed()
      await activate(el, 0)
      const art = article(el, 0)
      expect(errorPanel(art).hidden).toBe(true)

      playerAt(el, 0).dispatchEvent(new Event("error"))

      expect(art.dataset.state).toBe("error")
      expect(errorPanel(art).hidden).toBe(false)
    })

    it("Retry replaces the errored player with a fresh one and plays it", async () => {
      playImpl = notSupported
      const { el } = feed()
      await activate(el, 0)
      const art = article(el, 0)
      const broken = playerAt(el, 0)

      playImpl = () => Promise.resolve()
      errorPanel(art).querySelector<HTMLButtonElement>("button[data-shorts-retry]")!.click()
      await flush()

      const fresh = playerAt(el, 0)
      expect(fresh).not.toBe(broken)
      expect(broken.isConnected).toBe(false)
      expect(fresh.getAttribute("playback-id")).toBe("pb-1")
      expect(fresh.play).toHaveBeenCalled()
      expect(fresh.paused).toBe(false)
      expect(art.dataset.state).not.toBe("error")
      expect(errorPanel(art).hidden).toBe(true)
      expect(art.querySelectorAll("mux-player")).toHaveLength(1)
    })
  })

  describe("keyboard and controls", () => {
    it.each(["ArrowDown", "j", "PageDown"])("%s moves to the next clip", async (k) => {
      const { el } = feed()
      await activate(el, 0)
      const current = article(el, 0)
      const next = article(el, 1)
      const scroll = vi.spyOn(next, "scrollIntoView")
      const focus = vi.spyOn(next, "focus")
      current.focus()

      const event = key(current, k)

      expect(event.defaultPrevented).toBe(true)
      expect(scroll).toHaveBeenCalledWith(expect.objectContaining({ block: "start", behavior: "smooth" }))
      expect(focus).toHaveBeenCalledWith(expect.objectContaining({ preventScroll: true }))
      expect(document.activeElement).toBe(next)
    })

    it.each(["ArrowUp", "k", "PageUp"])("%s moves to the previous clip", async (k) => {
      const { el } = feed()
      await activate(el, 0)
      await activate(el, 1, 0)
      const current = article(el, 1)
      const previous = article(el, 0)
      const scroll = vi.spyOn(previous, "scrollIntoView")
      const focus = vi.spyOn(previous, "focus")
      current.focus()

      const event = key(current, k)

      expect(event.defaultPrevented).toBe(true)
      expect(scroll).toHaveBeenCalledWith(expect.objectContaining({ block: "start", behavior: "smooth" }))
      expect(focus).toHaveBeenCalledWith(expect.objectContaining({ preventScroll: true }))
      expect(document.activeElement).toBe(previous)
    })

    it("navigates from the feed container itself when it has focus", async () => {
      const { el } = feed()
      await activate(el, 0)
      const scroll = vi.spyOn(article(el, 1), "scrollIntoView")
      el.focus()

      key(el, "ArrowDown")

      expect(scroll).toHaveBeenCalled()
      expect(document.activeElement).toBe(article(el, 1))
    })

    it("scrolls instantly under prefers-reduced-motion", async () => {
      setReducedMotion(true)
      const { el } = feed()
      await activate(el, 0)
      const scroll = vi.spyOn(article(el, 1), "scrollIntoView")

      key(article(el, 0), "ArrowDown")

      expect(scroll).toHaveBeenCalledWith(expect.objectContaining({ block: "start", behavior: "auto" }))
    })

    it("does not move past the first or last clip", async () => {
      const { el } = feed({ count: 3 })
      await activate(el, 0)
      const scrolls = articles(el).map((a) => vi.spyOn(a, "scrollIntoView"))

      key(article(el, 0), "ArrowUp")
      for (const scroll of scrolls) expect(scroll).not.toHaveBeenCalled()

      await activate(el, 2, 0)
      key(article(el, 2), "ArrowDown")
      for (const scroll of scrolls) expect(scroll).not.toHaveBeenCalled()
    })

    it("Space toggles play/pause when the clip has focus", async () => {
      const { el } = feed()
      await activate(el, 0)
      const art = article(el, 0)
      const player = playerAt(el, 0)
      art.focus()

      const first = key(art, " ")
      await flush()
      expect(first.defaultPrevented).toBe(true)
      expect(player.pause).toHaveBeenCalledTimes(1)
      expect(player.paused).toBe(true)

      const playsBefore = player.play.mock.calls.length
      key(art, " ")
      await flush()
      expect(player.play.mock.calls.length).toBe(playsBefore + 1)
      expect(player.paused).toBe(false)
    })

    it("Space toggles play/pause when the feed itself has focus", async () => {
      const { el } = feed()
      await activate(el, 0)
      const player = playerAt(el, 0)
      el.focus()

      key(el, " ")

      expect(player.pause).toHaveBeenCalledTimes(1)
    })

    it("Space on a focused button is left to the button", async () => {
      const { el } = feed()
      await activate(el, 0)
      const player = playerAt(el, 0)
      const button = article(el, 0).querySelector<HTMLButtonElement>("[data-shorts-toggle-mute]")!
      button.focus()
      const playsBefore = player.play.mock.calls.length

      const event = key(button, " ")
      await flush()

      expect(event.defaultPrevented).toBe(false)
      expect(player.pause).not.toHaveBeenCalled()
      expect(player.play.mock.calls.length).toBe(playsBefore)
    })

    it("m toggles mute on the active clip", async () => {
      const { el } = feed()
      await activate(el, 0)
      const art = article(el, 0)
      const player = playerAt(el, 0)
      const muteButton = art.querySelector<HTMLButtonElement>("[data-shorts-toggle-mute]")!
      expect(isMuted(player)).toBe(false)

      key(art, "m")
      expect(isMuted(player)).toBe(true)
      expect(muteButton.getAttribute("aria-pressed")).toBe("true")

      key(art, "m")
      expect(isMuted(player)).toBe(false)
      expect(muteButton.getAttribute("aria-pressed")).toBe("false")
    })

    it("the play and mute buttons control the active clip", async () => {
      const { el } = feed()
      await activate(el, 0)
      const art = article(el, 0)
      const player = playerAt(el, 0)

      art.querySelector<HTMLButtonElement>("[data-shorts-toggle-play]")!.click()
      await flush()
      expect(player.pause).toHaveBeenCalledTimes(1)
      expect(player.paused).toBe(true)

      art.querySelector<HTMLButtonElement>("[data-shorts-toggle-play]")!.click()
      await flush()
      expect(player.paused).toBe(false)

      art.querySelector<HTMLButtonElement>("[data-shorts-toggle-mute]")!.click()
      expect(isMuted(player)).toBe(true)
    })

    it("the Next button scrolls to and focuses the next clip", async () => {
      const { el, nextButton } = feed()
      await activate(el, 0)
      const next = article(el, 1)
      const scroll = vi.spyOn(next, "scrollIntoView")
      const focus = vi.spyOn(next, "focus")

      nextButton.click()

      expect(scroll).toHaveBeenCalledWith(expect.objectContaining({ block: "start", behavior: "smooth" }))
      expect(focus).toHaveBeenCalledWith(expect.objectContaining({ preventScroll: true }))
      expect(document.activeElement).toBe(next)
    })

    it("the Previous button scrolls to and focuses the previous clip", async () => {
      const { el, prevButton } = feed()
      await activate(el, 0)
      await activate(el, 1, 0)
      const previous = article(el, 0)
      const scroll = vi.spyOn(previous, "scrollIntoView")
      const focus = vi.spyOn(previous, "focus")

      prevButton.click()

      expect(scroll).toHaveBeenCalledWith(expect.objectContaining({ block: "start", behavior: "smooth" }))
      expect(focus).toHaveBeenCalledWith(expect.objectContaining({ preventScroll: true }))
      expect(document.activeElement).toBe(previous)
    })

    it("Previous on the first clip and Next on the last clip do nothing", async () => {
      const { el, prevButton, nextButton } = feed({ count: 3 })
      await activate(el, 0)
      const scrolls = articles(el).map((a) => vi.spyOn(a, "scrollIntoView"))

      prevButton.click()
      for (const scroll of scrolls) expect(scroll).not.toHaveBeenCalled()

      await activate(el, 2, 0)
      nextButton.click()
      for (const scroll of scrolls) expect(scroll).not.toHaveBeenCalled()
    })

    it("the Previous/Next buttons scroll instantly under prefers-reduced-motion", async () => {
      setReducedMotion(true)
      const { el, prevButton, nextButton } = feed()
      await activate(el, 1)
      const next = vi.spyOn(article(el, 2), "scrollIntoView")
      const previous = vi.spyOn(article(el, 0), "scrollIntoView")

      nextButton.click()
      expect(next).toHaveBeenCalledWith(expect.objectContaining({ block: "start", behavior: "auto" }))

      // Settle back on clip 2 (index 1) before going the other way.
      await activate(el, 1, 2)
      prevButton.click()
      expect(previous).toHaveBeenCalledWith(expect.objectContaining({ block: "start", behavior: "auto" }))
    })
  })

  describe("pagination", () => {
    const loadMoreCalls = (pushEvent: ReturnType<typeof vi.fn>) =>
      pushEvent.mock.calls.filter(([event]) => event === "load_more")

    it("asks for the next page once when the active clip is within 3 of the end", async () => {
      const { el, pushEvent } = feed({ count: 10, hasMore: true })

      for (let i = 0; i <= 5; i++) await activate(el, i, i === 0 ? undefined : i - 1)
      expect(loadMoreCalls(pushEvent)).toHaveLength(0)

      await activate(el, 7, 5)
      expect(loadMoreCalls(pushEvent)).toHaveLength(1)

      await activate(el, 8, 7)
      await activate(el, 9, 8)
      expect(loadMoreCalls(pushEvent)).toHaveLength(1)
    })

    it("observes appended clips and asks again near the new end", async () => {
      const { el, hook, pushEvent } = feed({ count: 10, hasMore: true, setsize: 20 })
      await activate(el, 7)
      expect(loadMoreCalls(pushEvent)).toHaveLength(1)

      // The server streams the next page into the feed.
      for (let i = 10; i < 20; i++) el.insertAdjacentHTML("beforeend", articleMarkup(i, 20, false))
      hook.updated?.()
      await flush()

      for (let i = 10; i < 20; i++) expect(io.isObserved(article(el, i))).toBe(true)

      await activate(el, 12, 7)
      expect(loadMoreCalls(pushEvent)).toHaveLength(1)

      await activate(el, 17, 12)
      expect(loadMoreCalls(pushEvent)).toHaveLength(2)
    })

    it("never asks for more when data-has-more is false", async () => {
      const { el, pushEvent } = feed({ count: 10, hasMore: false })

      for (let i = 0; i < 10; i++) await activate(el, i, i === 0 ? undefined : i - 1)

      expect(loadMoreCalls(pushEvent)).toHaveLength(0)
    })
  })

  describe("backgrounding", () => {
    async function watching() {
      const mounted = feed()
      await activate(mounted.el, 0)
      const player = playerAt(mounted.el, 0)
      player.duration = 30
      player.dispatchEvent(new Event("loadedmetadata"))
      player.currentTime = 12
      player.dispatchEvent(new Event("timeupdate"))
      mounted.pushEvent.mockClear()
      return { ...mounted, player }
    }

    it("pauses the active clip, saves progress and sends a drop-off when the tab is hidden", async () => {
      const { player, pushEvent } = await watching()

      setVisibility("hidden")
      await flush()

      expect(player.pause).toHaveBeenCalled()
      expect(player.paused).toBe(true)
      expect(pushEvent).toHaveBeenCalledWith("playback_paused", { video_id: "v1", position: 12 })
      expect(pushEvent).toHaveBeenCalledWith("playback_drop_off", {
        video_id: "v1",
        max_position: 12,
        video_duration: 30,
      })
    })

    it("does not resume when the tab becomes visible again", async () => {
      const { player } = await watching()
      setVisibility("hidden")
      await flush()
      const playsBefore = player.play.mock.calls.length

      setVisibility("visible")
      await flush()

      expect(player.play.mock.calls.length).toBe(playsBefore)
      expect(player.paused).toBe(true)
    })

    it("pauses and sends a drop-off on pagehide", async () => {
      const { player, pushEvent } = await watching()

      window.dispatchEvent(new Event("pagehide"))
      await flush()

      expect(player.paused).toBe(true)
      expect(pushEvent).toHaveBeenCalledWith("playback_drop_off", {
        video_id: "v1",
        max_position: 12,
        video_duration: 30,
      })
    })
  })

  describe("progress reporting (same as mux_player.ts)", () => {
    beforeEach(() => {
      vi.useFakeTimers({ toFake: ["setTimeout", "clearTimeout", "setInterval", "clearInterval", "Date"] })
    })

    function playFor(player: FakeMuxPlayer, seconds: number) {
      player.currentTime += seconds
      player.dispatchEvent(new Event("timeupdate"))
      vi.advanceTimersByTime(seconds * 1000)
    }

    it("reports playback_started when the active clip starts playing", async () => {
      const { el, pushEvent } = feed()

      await activate(el, 0)

      expect(pushEvent).toHaveBeenCalledWith("playback_started", { video_id: "v1" })
    })

    it("reports progress every 30s while playing, and not while paused", async () => {
      const { el, pushEvent } = feed()
      await activate(el, 0)
      const player = playerAt(el, 0)
      pushEvent.mockClear()

      playFor(player, 30)
      expect(pushEvent).toHaveBeenCalledWith("playback_progress", { video_id: "v1", position: 30 })
      const progress = () => pushEvent.mock.calls.filter(([event]) => event === "playback_progress")
      expect(progress()).toHaveLength(1)

      playFor(player, 30)
      expect(progress()).toHaveLength(2)
      expect(pushEvent).toHaveBeenLastCalledWith("playback_progress", { video_id: "v1", position: 60 })

      player.pause()
      pushEvent.mockClear()
      vi.advanceTimersByTime(60_000)
      expect(progress()).toHaveLength(0)
    })

    it("throttles a close, recent sample but always reports a pause", async () => {
      const { el, pushEvent } = feed()
      await activate(el, 0)
      const player = playerAt(el, 0)
      playFor(player, 30)
      pushEvent.mockClear()

      player.currentTime += 5
      vi.advanceTimersByTime(5000)
      player.pause()

      expect(pushEvent).not.toHaveBeenCalledWith("playback_progress", expect.anything())
      expect(pushEvent).toHaveBeenCalledWith("playback_paused", { video_id: "v1", position: 35 })
    })

    it("never reports a zero position", async () => {
      const { el, pushEvent } = feed()
      await activate(el, 0)
      const player = playerAt(el, 0)
      pushEvent.mockClear()

      player.pause()
      vi.advanceTimersByTime(60_000)

      expect(pushEvent).not.toHaveBeenCalledWith("playback_paused", expect.anything())
      expect(pushEvent).not.toHaveBeenCalledWith("playback_progress", expect.anything())
    })

    it("attributes progress to the clip that is playing after a switch", async () => {
      const { el, pushEvent } = feed()
      await activate(el, 0)
      const first = playerAt(el, 0)
      first.currentTime = 8
      first.dispatchEvent(new Event("timeupdate"))
      pushEvent.mockClear()

      await activate(el, 1, 0)
      expect(pushEvent).toHaveBeenCalledWith("playback_paused", { video_id: "v1", position: 8 })
      expect(pushEvent).toHaveBeenCalledWith("playback_started", { video_id: "v2" })

      const second = playerAt(el, 1)
      pushEvent.mockClear()
      playFor(second, 30)
      expect(pushEvent).toHaveBeenCalledWith("playback_progress", { video_id: "v2", position: 30 })
      expect(pushEvent).not.toHaveBeenCalledWith("playback_progress", expect.objectContaining({ video_id: "v1" }))
    })
  })

  /*
   * Looping clips never fire `ended`, so completion is detected from the
   * player's position. Rule (per activation): a `timeupdate` reporting
   * currentTime < 1s after an earlier `timeupdate` in the same activation
   * reported currentTime >= duration - 1s (duration > 0, read from the
   * player) means the clip completed a loop. The first such wrap pushes
   * `playback_ended` { video_id } once; later wraps in the same activation
   * push nothing. Leaving an active clip that has not completed during this
   * activation pushes `playback_drop_off` { video_id, max_position,
   * video_duration } (alongside `playback_paused`); a completed clip sends no
   * drop-off when left.
   */
  describe("completion and drop-off of looping clips", () => {
    function timeAt(player: FakeMuxPlayer, seconds: number) {
      player.currentTime = seconds
      player.dispatchEvent(new Event("timeupdate"))
    }

    function withDuration(player: FakeMuxPlayer, seconds: number) {
      player.duration = seconds
      player.dispatchEvent(new Event("loadedmetadata"))
    }

    const callsOf = (pushEvent: ReturnType<typeof vi.fn>, name: string) =>
      pushEvent.mock.calls.filter(([event]) => event === name)

    it("pushes playback_ended once when the active clip wraps after its end", async () => {
      const { el, pushEvent } = feed()
      await activate(el, 0)
      const player = playerAt(el, 0)
      withDuration(player, 30)

      timeAt(player, 10)
      timeAt(player, 29.5)
      expect(callsOf(pushEvent, "playback_ended")).toHaveLength(0)

      timeAt(player, 0.2)
      expect(pushEvent).toHaveBeenCalledWith("playback_ended", { video_id: "v1" })
      expect(callsOf(pushEvent, "playback_ended")).toHaveLength(1)

      // Second loop in the same activation: nothing more.
      timeAt(player, 15)
      timeAt(player, 29.6)
      timeAt(player, 0.1)
      expect(callsOf(pushEvent, "playback_ended")).toHaveLength(1)
    })

    it("does not treat a jump back to the start before the end as completion", async () => {
      const { el, pushEvent } = feed()
      await activate(el, 0)
      const player = playerAt(el, 0)
      withDuration(player, 30)

      timeAt(player, 12)
      timeAt(player, 28.5)
      timeAt(player, 0.3)

      expect(callsOf(pushEvent, "playback_ended")).toHaveLength(0)
    })

    it("sends a drop-off for a clip left before it completed", async () => {
      const { el, pushEvent } = feed()
      await activate(el, 0)
      const player = playerAt(el, 0)
      withDuration(player, 30)
      timeAt(player, 8)
      pushEvent.mockClear()

      await activate(el, 1, 0)

      expect(pushEvent).toHaveBeenCalledWith("playback_paused", { video_id: "v1", position: 8 })
      expect(pushEvent).toHaveBeenCalledWith("playback_drop_off", {
        video_id: "v1",
        max_position: 8,
        video_duration: 30,
      })
      expect(callsOf(pushEvent, "playback_drop_off")).toHaveLength(1)
    })

    it.each([
      ["the Next button", async (ctx: ReturnType<typeof feed>) => ctx.nextButton.click()],
      ["ArrowDown", async (ctx: ReturnType<typeof feed>) => void key(article(ctx.el, 0), "ArrowDown")],
    ])("sends the drop-off when %s moves on and the next clip becomes active", async (_label, move) => {
      const ctx = feed()
      await activate(ctx.el, 0)
      const player = playerAt(ctx.el, 0)
      withDuration(player, 30)
      timeAt(player, 6)
      ctx.pushEvent.mockClear()

      await move(ctx)
      await activate(ctx.el, 1, 0)

      expect(ctx.pushEvent).toHaveBeenCalledWith("playback_drop_off", {
        video_id: "v1",
        max_position: 6,
        video_duration: 30,
      })
    })

    it("sends no drop-off for a clip that completed during this activation", async () => {
      const { el, pushEvent } = feed()
      await activate(el, 0)
      const player = playerAt(el, 0)
      withDuration(player, 30)
      timeAt(player, 29.5)
      timeAt(player, 0.4)
      expect(callsOf(pushEvent, "playback_ended")).toHaveLength(1)

      await activate(el, 1, 0)

      expect(pushEvent).not.toHaveBeenCalledWith(
        "playback_drop_off",
        expect.objectContaining({ video_id: "v1" }),
      )
    })

    it("re-activating a clip later allows another completion (and another drop-off)", async () => {
      const { el, pushEvent } = feed()
      await activate(el, 0)
      withDuration(playerAt(el, 0), 30)
      timeAt(playerAt(el, 0), 29.5)
      timeAt(playerAt(el, 0), 0.4)
      await activate(el, 1, 0)
      expect(callsOf(pushEvent, "playback_ended")).toHaveLength(1)

      // Back to clip 1: a new activation.
      await activate(el, 0, 1)
      const again = playerAt(el, 0)
      withDuration(again, 30)
      timeAt(again, 29.4)
      timeAt(again, 0.2)
      const ended = callsOf(pushEvent, "playback_ended")
      expect(ended).toHaveLength(2)
      expect(ended[1]![1]).toEqual({ video_id: "v1" })

      // A third activation left early drops off again.
      await activate(el, 1, 0)
      await activate(el, 0, 1)
      timeAt(playerAt(el, 0), 5)
      pushEvent.mockClear()
      await activate(el, 1, 0)
      expect(pushEvent).toHaveBeenCalledWith(
        "playback_drop_off",
        expect.objectContaining({ video_id: "v1" }),
      )
    })
  })

  describe("destroyed()", () => {
    it("flushes the active clip, then removes every player and stops listening", async () => {
      const { el, hook, pushEvent, tapToPlay, nextButton, prevButton } = feed()
      await activate(el, 1)
      const player = playerAt(el, 1)
      player.duration = 40
      player.dispatchEvent(new Event("loadedmetadata"))
      player.currentTime = 20
      player.dispatchEvent(new Event("timeupdate"))
      pushEvent.mockClear()

      hook.destroyed()
      await flush()

      // Final position and drop-off for the clip being watched.
      expect(
        pushEvent.mock.calls.some(
          ([event, payload]) =>
            (event === "playback_progress" || event === "playback_paused") &&
            (payload as { video_id: string; position: number }).video_id === "v2" &&
            (payload as { video_id: string; position: number }).position === 20,
        ),
      ).toBe(true)
      expect(pushEvent).toHaveBeenCalledWith("playback_drop_off", {
        video_id: "v2",
        max_position: 20,
        video_duration: 40,
      })

      // Players paused and removed; observers disconnected.
      expect(player.paused).toBe(true)
      expect(document.querySelectorAll("mux-player")).toHaveLength(0)
      expect(io.allDisconnected()).toBe(true)

      // Nothing reacts any more: document, window, feed and outside-feed
      // listeners are all gone (however the hook chose to remove them).
      pushEvent.mockClear()
      const scrolls = articles(el).map((a) => vi.spyOn(a, "scrollIntoView"))
      const focusBefore = document.activeElement
      setVisibility("hidden")
      setVisibility("visible")
      window.dispatchEvent(new Event("pagehide"))
      key(article(el, 1), "ArrowDown")
      key(el, "j")
      key(article(el, 1), " ")
      key(article(el, 1), "m")
      nextButton.click()
      prevButton.click()
      tapToPlay.click()
      io.trigger(article(el, 3), 1)
      await flush()

      expect(pushEvent).not.toHaveBeenCalled()
      for (const scroll of scrolls) expect(scroll).not.toHaveBeenCalled()
      expect(document.activeElement).toBe(focusBefore)
      expect(document.querySelectorAll("mux-player")).toHaveLength(0)
    })

    it("still cleans up when the server push rejects because the view has gone", async () => {
      const unhandled: unknown[] = []
      const onUnhandled = (reason: unknown) => unhandled.push(reason)
      process.on("unhandledRejection", onUnhandled)
      try {
        const { el, hook } = feed()
        await activate(el, 1)
        const player = playerAt(el, 1)
        player.duration = 40
        player.dispatchEvent(new Event("loadedmetadata"))
        player.currentTime = 20
        player.dispatchEvent(new Event("timeupdate"))

        // LiveView 1.1: pushEvent returns a promise that rejects once the view
        // has left. A plain function, not vi.fn(): vitest's spies attach their
        // own handler to returned promises, which would hide an unhandled one.
        const pushed: Array<[string, unknown]> = []
        hook.pushEvent = ((event: string, payload: unknown) => {
          pushed.push([event, payload])
          return Promise.reject(new Error("view left"))
        }) as unknown as typeof hook.pushEvent

        expect(() => hook.destroyed()).not.toThrow()
        await flush()
        await new Promise((resolve) => setTimeout(resolve, 0))

        // It still tried to save the final state...
        expect(pushed).toContainEqual([
          "playback_drop_off",
          { video_id: "v2", max_position: 20, video_duration: 40 },
        ])
        // ...and finished tearing down.
        expect(player.paused).toBe(true)
        expect(document.querySelectorAll("mux-player")).toHaveLength(0)
        expect(io.allDisconnected()).toBe(true)
        expect(unhandled).toEqual([])
      } finally {
        process.off("unhandledRejection", onUnhandled)
      }
    })
  })
})
