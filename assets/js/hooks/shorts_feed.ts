/**
 * ShortsFeed hook
 *
 * Used by: Viewer.ShortsLive (`/shorts`, the vertical short-form feed)
 *
 * Bridges the server-rendered Shorts feed to the Mux Player: picks the active
 * clip with an IntersectionObserver, keeps at most three `<mux-player>`
 * elements alive (the active clip and its two neighbours), plays the active
 * clip on a loop, handles keyboard and button navigation, and reports
 * playback with the same events, payloads and throttling as the MuxPlayer
 * hook. Which clips are playable, and what each event means, is decided on
 * the server: the hook only creates players for clips that carry a playback id.
 *
 * DOM it reads:
 *   On the hooked element (`#shorts-feed`, the scroll container):
 *     - data-has-more: "true" while the server has another page to stream
 *   On each clip (`article[data-index]`, a direct child of the feed):
 *     - data-video-id: Marquee video ID (event payloads)
 *     - data-playback-id: Mux playback ID; present only on playable clips
 *     - aria-posinset / aria-setsize / aria-labelledby: live announcement
 *     - [data-player-slot]: where the clip's player is mounted
 *     - [data-shorts-toggle-play], [data-shorts-toggle-mute]: clip controls
 *     - [data-test="short-error-{video id}"] with [data-shorts-retry]
 *   Elsewhere in the document (outside the streamed feed):
 *     - [data-shorts-prev], [data-shorts-next]: Previous / Next buttons
 *     - [data-test="shorts-tap-to-play"]: shown when autoplay is refused
 *     - [data-shorts-live]: polite live region for "Clip N of M: title"
 *
 * DOM it writes:
 *   - feed data-autoplay="blocked" while even muted autoplay is refused
 *   - clip data-state="error" and its error panel unhidden on a playback error
 *   - aria-pressed on the play and mute buttons
 *
 * Completion: clips loop, so `ended` never fires. Within one activation, a
 * `timeupdate` below 1s that follows one within 1s of the end is a completed
 * loop; the first pushes "playback_ended", later loops push nothing. Leaving
 * a clip that did not complete in that activation pushes "playback_drop_off"
 * (after "playback_paused").
 *
 * Keys (when the feed or a clip has focus): ArrowDown / j / PageDown next,
 * ArrowUp / k / PageUp previous, Space play/pause, m mute.
 *
 * Events sent to server:
 *   - "playback_clip_activated" { video_id }
 *   - "playback_started"        { video_id }
 *   - "playback_progress"       { video_id, position }
 *   - "playback_paused"         { video_id, position }
 *   - "playback_ended"          { video_id }
 *   - "playback_drop_off"       { video_id, max_position, video_duration }
 *   - "load_more"               {}
 *
 * Events received from server: none (new clips arrive as stream inserts).
 */
import { ViewHook } from "phoenix_live_view"

import { scrollBehavior } from "../motion"
import { PROGRESS_INTERVAL_MS, PROGRESS_JITTER_MS, PlaybackReporter } from "../playback_reporter"
import type { MuxPlayerElement } from "../types/mux"

/** Share of a clip that must be on screen before it becomes the active clip. */
const ACTIVE_RATIO = 0.6

/** Ask for the next page once the active clip is this close to the end. */
const LOAD_MORE_DISTANCE = 3

const CLIP_SELECTOR = ":scope > article[data-index]"
const PREV_SELECTOR = "[data-shorts-prev]"
const NEXT_SELECTOR = "[data-shorts-next]"
const TAP_TO_PLAY_SELECTOR = '[data-test="shorts-tap-to-play"]'
const LIVE_REGION_SELECTOR = "[data-shorts-live]"
const TOGGLE_PLAY_SELECTOR = "[data-shorts-toggle-play]"
const TOGGLE_MUTE_SELECTOR = "[data-shorts-toggle-mute]"
const RETRY_SELECTOR = "[data-shorts-retry]"

const NEXT_KEYS = new Set(["ArrowDown", "j", "PageDown"])
const PREVIOUS_KEYS = new Set(["ArrowUp", "k", "PageUp"])

/** A mounted player and the bookkeeping that lives and dies with it. */
interface Clip {
  article: HTMLElement
  player: MuxPlayerElement
  reporter: PlaybackReporter
  /** Aborting removes every listener added to the player. */
  listeners: AbortController
  /** This activation reached the last second of the clip. */
  reachedEnd: boolean
  /** This activation completed a loop (and reported `playback_ended`). */
  completed: boolean
  /** Version of the latest play request; pauses invalidate pending outcomes. */
  playAttempt: number
}

/** Seconds from either end of a clip that count as its end / its start. */
const LOOP_EDGE_SECONDS = 1

class ShortsFeed extends ViewHook {
  private observer: IntersectionObserver | null = null
  private clips = new Map<HTMLElement, Clip>()
  private active: HTMLElement | null = null
  private muted = false
  /** Clip count at the last `load_more`, so each page is requested once. */
  private loadMoreRequestedAt = -1
  private progressStart: number | null = null
  private progressInterval: number | null = null
  private isDestroyed = false

  private onIntersect = (entries: IntersectionObserverEntry[]) => {
    const visible = entries
      .filter((entry) => entry.intersectionRatio >= ACTIVE_RATIO)
      .sort((a, b) => b.intersectionRatio - a.intersectionRatio)[0]
    if (visible) this.activate(visible.target as HTMLElement)
  }

  private onKeydown = (event: KeyboardEvent) => {
    if (event.defaultPrevented || event.altKey || event.ctrlKey || event.metaKey) return
    if (!this.ownsKeyboardFocus(event.target)) return

    const key = event.key.length === 1 ? event.key.toLowerCase() : event.key
    if (NEXT_KEYS.has(key)) {
      event.preventDefault()
      this.step(1)
    } else if (PREVIOUS_KEYS.has(key)) {
      event.preventDefault()
      this.step(-1)
    } else if (key === " ") {
      event.preventDefault()
      this.togglePlay()
    } else if (key === "m") {
      this.setMuted(!this.muted)
    }
  }

  private onClick = (event: MouseEvent) => {
    const target = event.target instanceof Element ? event.target : null
    if (!target) return

    if (target.closest(PREV_SELECTOR)) return this.step(-1)
    if (target.closest(NEXT_SELECTOR)) return this.step(1)
    if (target.closest(TAP_TO_PLAY_SELECTOR)) return this.playActive()

    const article = this.clipArticleOf(target)
    if (!article) return
    if (target.closest(TOGGLE_PLAY_SELECTOR)) this.togglePlayFor(article)
    else if (target.closest(TOGGLE_MUTE_SELECTOR)) this.setMuted(!this.muted)
    else if (target.closest(RETRY_SELECTOR)) this.retry(article)
  }

  private onVisibilityChange = () => {
    if (document.visibilityState === "hidden") this.pauseForBackground()
    else this.rearmDropOff()
  }

  private onPageHide = () => this.pauseForBackground()

  private onProgressTick = () => {
    const clip = this.activeClip()
    if (clip) this.flushProgress(clip)
  }

  mounted() {
    this.observer = new IntersectionObserver(this.onIntersect, { threshold: [0, ACTIVE_RATIO, 1] })
    this.observeClips()

    this.el.addEventListener("keydown", this.onKeydown)
    document.addEventListener("click", this.onClick)
    document.addEventListener("visibilitychange", this.onVisibilityChange)
    window.addEventListener("pagehide", this.onPageHide)

    // Spread out progress updates so reconnect storms do not align all viewers.
    const jitter = Math.floor(Math.random() * PROGRESS_JITTER_MS)
    this.progressStart = window.setTimeout(() => {
      this.progressStart = null
      this.progressInterval = window.setInterval(this.onProgressTick, PROGRESS_INTERVAL_MS)
    }, jitter)
  }

  updated() {
    this.releaseRemovedClips()
    this.observeClips()
    this.syncControls()
  }

  destroyed() {
    // Save the final state while the view may still accept it; pagehide does
    // not fire on LiveView navigation.
    const clip = this.activeClip()
    if (clip) {
      this.flushProgress(clip)
      clip.reporter.sendDropOff()
    }
    this.isDestroyed = true

    if (this.progressStart !== null) window.clearTimeout(this.progressStart)
    if (this.progressInterval !== null) window.clearInterval(this.progressInterval)
    this.observer?.disconnect()
    this.observer = null

    this.el.removeEventListener("keydown", this.onKeydown)
    document.removeEventListener("click", this.onClick)
    document.removeEventListener("visibilitychange", this.onVisibilityChange)
    window.removeEventListener("pagehide", this.onPageHide)

    for (const existing of Array.from(this.clips.values())) this.releaseClip(existing)
    this.active = null
  }

  // --- activation and the player window -----------------------------------

  private activate(article: HTMLElement) {
    if (article === this.active || article.parentElement !== this.el) return

    this.deactivateCurrent()
    this.active = article
    this.syncPlayerWindow()
    this.announce(article)

    const clip = this.clips.get(article)
    if (clip) {
      this.beginActivation(clip)
      this.push("playback_clip_activated", { video_id: article.dataset.videoId })
      this.play(clip)
    }

    this.requestMoreNearEnd()
  }

  /** Pause the clip being left; one it did not finish this time is a drop-off. */
  private deactivateCurrent() {
    const clip = this.activeClip()
    if (!clip) return
    this.pauseClip(clip)
    clip.reporter.sendDropOff()
  }

  /** Each activation is a fresh view: completion and drop-off start over. */
  private beginActivation(clip: Clip) {
    clip.reachedEnd = false
    clip.completed = false
    clip.reporter.beginView()
  }

  /** Detect a completed loop from the position (looping players never fire `ended`). */
  private trackLoop(clip: Clip) {
    if (clip.article !== this.active || clip.completed) return

    const position = Number(clip.player.currentTime || 0)
    const duration = Number(clip.player.duration || 0)
    if (duration > 0 && position >= duration - LOOP_EDGE_SECONDS) clip.reachedEnd = true
    else if (clip.reachedEnd && position < LOOP_EDGE_SECONDS) this.markCompleted(clip)
  }

  private markCompleted(clip: Clip) {
    if (clip.completed) return
    clip.completed = true
    clip.reporter.reportEnded(Number(clip.player.duration || clip.player.currentTime || 0))
  }

  /** Back from the background: a clip not yet completed can drop off again. */
  private rearmDropOff() {
    const clip = this.activeClip()
    if (clip && !clip.completed) clip.reporter.rearmDropOff()
  }

  /** Keep players for the active clip and its neighbours only. */
  private syncPlayerWindow() {
    const articles = this.articles()
    const index = this.active ? articles.indexOf(this.active) : -1
    const inWindow = new Set(articles.slice(Math.max(index - 1, 0), index + 2))

    for (const clip of Array.from(this.clips.values())) {
      if (!inWindow.has(clip.article)) this.releaseClip(clip)
    }

    for (const article of inWindow) {
      const clip = this.clips.get(article) ?? this.createClip(article)
      if (clip) this.configure(clip, article === this.active)
    }
  }

  private configure(clip: Clip, isActive: boolean) {
    clip.player.loop = isActive
    clip.player.setAttribute("preload", isActive ? "auto" : "metadata")
  }

  private createClip(article: HTMLElement): Clip | null {
    const playbackId = article.dataset.playbackId
    const slot = article.querySelector<HTMLElement>("[data-player-slot]")
    if (!playbackId || !slot) return null

    const player = document.createElement("mux-player")
    player.setAttribute("playback-id", playbackId)
    player.setAttribute("playsinline", "")
    player.setAttribute("stream-type", "on-demand")
    player.muted = this.muted

    const reporter = new PlaybackReporter(this.push, article.dataset.videoId)
    const clip: Clip = {
      article,
      player,
      reporter,
      listeners: new AbortController(),
      reachedEnd: false,
      completed: false,
      playAttempt: 0,
    }
    const { signal } = clip.listeners

    player.addEventListener(
      "timeupdate",
      () => {
        reporter.trackPosition(Number(player.currentTime || 0))
        this.trackLoop(clip)
      },
      { signal },
    )
    player.addEventListener("loadedmetadata", () => reporter.trackDuration(Number(player.duration || 0)), { signal })
    player.addEventListener("play", () => this.markPlaying(clip), { signal })
    player.addEventListener("playing", () => this.recoverPlayback(clip), { signal })
    player.addEventListener("pause", () => this.markPaused(clip), { signal })
    player.addEventListener("ended", () => this.markCompleted(clip), { signal })
    player.addEventListener("error", () => this.showError(article), { signal })

    slot.appendChild(player)
    this.clips.set(article, clip)
    return clip
  }

  /** Stop listening first, so tearing a player down reports nothing. */
  private releaseClip(clip: Clip) {
    clip.listeners.abort()
    this.pauseClip(clip)
    clip.player.remove()
    this.clips.delete(clip.article)
  }

  /** Drop players whose clip the server removed from the stream. */
  private releaseRemovedClips() {
    for (const clip of Array.from(this.clips.values())) {
      if (clip.article.parentElement !== this.el) this.releaseClip(clip)
    }
    if (this.active && this.active.parentElement !== this.el) this.active = null
  }

  private observeClips() {
    for (const article of this.articles()) this.observer?.observe(article)
  }

  // --- playback -------------------------------------------------------------

  private play(clip: Clip) {
    const attempt = ++clip.playAttempt
    this.attemptPlay(clip.player).catch((error: unknown) => {
      if (!this.isCurrentAttempt(clip, attempt) || isPlaybackInterrupted(error)) return
      if (isAutoplayRefusal(error)) this.playMuted(clip)
      else this.showError(clip.article)
    })
  }

  /** Browsers that refuse audible autoplay usually allow it muted. */
  private playMuted(clip: Clip) {
    this.setMuted(true)
    const attempt = ++clip.playAttempt
    this.attemptPlay(clip.player).catch((error: unknown) => {
      if (!this.isCurrentAttempt(clip, attempt) || isPlaybackInterrupted(error)) return
      if (isAutoplayRefusal(error)) this.setAutoplayBlocked(true)
      else this.showError(clip.article)
    })
  }

  /** `play()` may throw synchronously or return a rejected promise. */
  private attemptPlay(player: MuxPlayerElement): Promise<void> {
    try {
      return Promise.resolve(player.play())
    } catch (error) {
      return Promise.reject(error)
    }
  }

  private playActive() {
    const clip = this.activeClip()
    if (clip) this.play(clip)
  }

  private togglePlay() {
    const clip = this.activeClip()
    if (!clip) return
    if (clip.player.paused) this.play(clip)
    else this.pauseClip(clip)
  }

  /** A clip's own play button toggles it when active, and brings it into view otherwise. */
  private togglePlayFor(article: HTMLElement) {
    if (article === this.active) this.togglePlay()
    else this.moveTo(article)
  }

  private markPlaying(clip: Clip) {
    if (!this.isCurrent(clip) || clip.article !== this.active) return
    this.recoverPlayback(clip)
    clip.reporter.reportStarted()
  }

  /** Actual playback recovery removes a stale alert without reporting another start. */
  private recoverPlayback(clip: Clip) {
    if (!this.isCurrent(clip) || clip.article !== this.active) return
    clip.playAttempt++
    this.clearError(clip.article)
    this.setAutoplayBlocked(false)
    this.syncPlayButton(clip)
  }

  private markPaused(clip: Clip) {
    clip.playAttempt++
    clip.reporter.report(Number(clip.player.currentTime || 0), "playback_paused")
    this.syncPlayButton(clip)
  }

  private flushProgress(clip: Clip) {
    if (!clip.player.paused && clip.player.currentTime > 0) {
      clip.reporter.report(Number(clip.player.currentTime || 0))
    }
  }

  /** Backgrounded or unloading: save progress, pause, record the drop-off. Never auto-resumes. */
  private pauseForBackground() {
    const clip = this.activeClip()
    if (!clip) return
    this.flushProgress(clip)
    this.pauseClip(clip)
    clip.reporter.sendDropOff()
  }

  /** A paused pending play can reject later even when no pause event fired. */
  private pauseClip(clip: Clip) {
    clip.playAttempt++
    clip.player.pause()
  }

  private setMuted(muted: boolean) {
    this.muted = muted
    for (const clip of this.clips.values()) clip.player.muted = muted
    this.syncMuteButtons()
  }

  private syncMuteButtons() {
    for (const button of this.el.querySelectorAll(TOGGLE_MUTE_SELECTOR)) {
      button.setAttribute("aria-pressed", String(this.muted))
    }
  }

  private syncPlayButton(clip: Clip) {
    clip.article.querySelector(TOGGLE_PLAY_SELECTOR)?.setAttribute("aria-pressed", String(!clip.player.paused))
  }

  /** Re-apply client-side control state after the server re-renders clips. */
  private syncControls() {
    this.syncMuteButtons()
    for (const clip of this.clips.values()) this.syncPlayButton(clip)
  }

  private setAutoplayBlocked(blocked: boolean) {
    if (blocked) this.el.dataset.autoplay = "blocked"
    else delete this.el.dataset.autoplay

    const tapToPlay = document.querySelector<HTMLElement>(TAP_TO_PLAY_SELECTOR)
    if (tapToPlay) tapToPlay.hidden = !blocked
  }

  // --- errors ---------------------------------------------------------------

  private showError(article: HTMLElement) {
    article.dataset.state = "error"
    const panel = this.errorPanelOf(article)
    if (panel) panel.hidden = false
  }

  private clearError(article: HTMLElement) {
    delete article.dataset.state
    const panel = this.errorPanelOf(article)
    if (panel) panel.hidden = true
  }

  /** Replace the clip's player with a fresh one; play it if the clip is active. */
  private retry(article: HTMLElement) {
    const broken = this.clips.get(article)
    if (broken) this.releaseClip(broken)
    this.clearError(article)
    this.syncPlayerWindow()

    const fresh = this.clips.get(article)
    if (fresh && article === this.active) this.play(fresh)
  }

  // --- navigation and pagination ---------------------------------------------

  private step(offset: number) {
    const articles = this.articles()
    const index = this.active ? articles.indexOf(this.active) : -1
    const target = articles[index + offset]
    if (target) this.moveTo(target)
  }

  /** Scroll the clip into place and move focus to it; activation follows from the observer. */
  private moveTo(article: HTMLElement) {
    article.scrollIntoView({ block: "start", behavior: scrollBehavior() })
    article.focus({ preventScroll: true })
  }

  private announce(article: HTMLElement) {
    const region = document.querySelector(LIVE_REGION_SELECTOR)
    if (!region) return

    const position = article.getAttribute("aria-posinset") ?? String(this.articles().indexOf(article) + 1)
    const total = article.getAttribute("aria-setsize") ?? String(this.articles().length)
    const titleId = article.getAttribute("aria-labelledby")
    const title = titleId ? document.getElementById(titleId)?.textContent?.trim() : ""
    region.textContent = title ? `Clip ${position} of ${total}: ${title}` : `Clip ${position} of ${total}`
  }

  private requestMoreNearEnd() {
    if (this.el.dataset.hasMore !== "true" || !this.active) return

    const articles = this.articles()
    const remaining = articles.length - 1 - articles.indexOf(this.active)
    if (remaining >= LOAD_MORE_DISTANCE || this.loadMoreRequestedAt === articles.length) return

    this.loadMoreRequestedAt = articles.length
    this.push("load_more", {})
  }

  // --- helpers ---------------------------------------------------------------

  /** Send an event; a view that has already gone may reject, which is not an error here. */
  private push = (event: string, payload: Record<string, unknown>) => {
    if (this.isDestroyed) return
    try {
      Promise.resolve(this.pushEvent(event, payload)).catch(() => undefined)
    } catch {
      // The view is gone; nothing left to tell it.
    }
  }

  private articles(): HTMLElement[] {
    return Array.from(this.el.querySelectorAll<HTMLElement>(CLIP_SELECTOR))
  }

  private activeClip(): Clip | undefined {
    return this.active ? this.clips.get(this.active) : undefined
  }

  /** False once the clip's player was released or replaced, or the hook destroyed. */
  private isCurrent(clip: Clip): boolean {
    return !this.isDestroyed && this.clips.get(clip.article) === clip
  }

  /** Only the active player's latest request may change playback UI. */
  private isCurrentAttempt(clip: Clip, attempt: number): boolean {
    return this.isCurrent(clip) && clip.article === this.active && clip.playAttempt === attempt
  }

  private clipArticleOf(target: Element): HTMLElement | null {
    const article = target.closest<HTMLElement>("article[data-index]")
    return article && article.parentElement === this.el ? article : null
  }

  private errorPanelOf(article: HTMLElement): HTMLElement | null {
    const panelName = `short-error-${article.dataset.videoId}`
    const candidates = Array.from(article.querySelectorAll<HTMLElement>("[data-test]"))
    return candidates.find((candidate) => candidate.dataset.test === panelName) ?? null
  }

  /** Shortcuts apply only when the feed itself or one of its clips has focus. */
  private ownsKeyboardFocus(target: EventTarget | null): boolean {
    if (target === this.el) return true
    return target instanceof HTMLElement && target.parentElement === this.el && target.matches("article[data-index]")
  }
}

/** The autoplay policy refused playback (as opposed to a media failure). */
function isAutoplayRefusal(error: unknown): boolean {
  return error instanceof DOMException && error.name === "NotAllowedError"
}

/** Pausing or changing playback interrupts a pending request without a media failure. */
function isPlaybackInterrupted(error: unknown): boolean {
  return error instanceof DOMException && error.name === "AbortError"
}

export default ShortsFeed
