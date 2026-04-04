/**
 * CardFocus hook
 *
 * Used by: ViewerComponents.content_card (HomeLive, BrowseLive, WatchLive,
 *          WatchlistLive, HistoryLive, CollectionLive)
 *
 * Manages hover/focus state for video card popups. Shows the popup
 * after a delay on mouseenter, hides on mouseleave. When shown,
 * injects a muted auto-playing mux-player into the popup thumbnail
 * area for a video preview. Cleans up the player on hide.
 *
 * Skips focus when the card overlaps a row navigation arrow.
 * Respects prefers-reduced-motion by removing the show delay.
 *
 * No server events — purely client-side behavior.
 */
const SHOW_DELAY_MS = 500
const HIDE_DELAY_MS = 300

const CardFocus = {
  mounted() {
    this._showTimer = null as ReturnType<typeof setTimeout> | null
    this._hideTimer = null as ReturnType<typeof setTimeout> | null
    this._player = null as HTMLElement | null
    this._reducedMotion = window.matchMedia(
      "(prefers-reduced-motion: reduce)"
    ).matches

    this.el.addEventListener("mouseenter", () => this.scheduleShow())
    this.el.addEventListener("mouseleave", () => this.scheduleHide())
    this.el.addEventListener("focusin", () => {
      if (!this.overlapsArrow()) this.show()
    })
    this.el.addEventListener("focusout", (e: FocusEvent) => {
      if (!this.el.contains(e.relatedTarget as Node)) {
        this.hide()
      }
    })

    this.el.addEventListener("keydown", (e: KeyboardEvent) => {
      if (e.key === "Escape") {
        this.hide()
        const link = this.el.querySelector<HTMLElement>("a")
        link?.focus()
      }
    })
  },

  /**
   * Checks if this card overlaps a visible row arrow button.
   * If it does, focus should be suppressed so the arrow stays usable.
   */
  overlapsArrow(): boolean {
    const row = this.el.closest(
      ".sv-row, .content-row, [phx-hook='RowScroller']"
    )
    if (!row) return false

    const arrows = row.querySelectorAll<HTMLElement>(
      ".sv-row-arrow:not(.row-arrow-hidden), .row-arrow:not(.row-arrow-hidden)"
    )
    if (!arrows.length) return false

    const cardRect = this.el.getBoundingClientRect()

    for (const arrow of arrows) {
      const arrowRect = arrow.getBoundingClientRect()
      const overlaps =
        cardRect.left < arrowRect.right &&
        cardRect.right > arrowRect.left &&
        cardRect.top < arrowRect.bottom &&
        cardRect.bottom > arrowRect.top
      if (overlaps) return true
    }
    return false
  },

  scheduleShow() {
    this.cancelHide()

    if (this.overlapsArrow()) return

    const delay = this._reducedMotion ? 0 : SHOW_DELAY_MS
    this._showTimer = setTimeout(() => this.show(), delay)
  },

  scheduleHide() {
    this.cancelShow()
    this._hideTimer = setTimeout(() => this.hide(), HIDE_DELAY_MS)
  },

  show() {
    this.cancelHide()
    this.cancelShow()
    this.el.classList.add("sv-card-focused")
    this.startPreview()
  },

  hide() {
    this.cancelShow()
    this.cancelHide()
    this.el.classList.remove("sv-card-focused")
    this.stopPreview()
  },

  startPreview() {
    if (this._player) return

    const thumbEl = this.el.querySelector<HTMLElement>(".sv-card-popup-thumb")
    if (!thumbEl) return

    const playbackId = thumbEl.dataset.playbackId
    if (!playbackId) return

    const player = document.createElement("mux-player")
    player.setAttribute("stream-type", "on-demand")
    player.setAttribute("playback-id", playbackId)
    player.setAttribute("autoplay", "muted")
    player.setAttribute("muted", "")
    player.setAttribute("loop", "")
    player.setAttribute("preload", "auto")
    player.setAttribute("disable-cookies", "")
    player.setAttribute("disable-tracking", "")
    player.style.setProperty("--controls", "none")
    player.style.setProperty("--media-control-display", "none")

    thumbEl.appendChild(player)
    this._player = player
  },

  stopPreview() {
    if (this._player) {
      this._player.remove()
      this._player = null
    }
  },

  cancelShow() {
    if (this._showTimer) {
      clearTimeout(this._showTimer)
      this._showTimer = null
    }
  },

  cancelHide() {
    if (this._hideTimer) {
      clearTimeout(this._hideTimer)
      this._hideTimer = null
    }
  },

  destroyed() {
    this.cancelShow()
    this.cancelHide()
    this.stopPreview()
  },
}

export default CardFocus
