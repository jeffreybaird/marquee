/**
 * Carousel hook
 *
 * Used by: MarqueeWeb.Components.Rows scrollable rows (content, continue
 * watching, series, creator showcase, editorial spotlight).
 *
 * Drag-to-scroll with momentum. Arrow buttons scroll by ~75% of
 * container width. Scroll position preserved across LiveView patches
 * via the `updated()` callback.
 *
 * Expected DOM (mounted on row <section>):
 *   [data-carousel-track]  — scrollable flex container
 *   [data-carousel-prev]   — optional left arrow button
 *   [data-carousel-next]   — optional right arrow button
 *
 * No server events — purely client-side behavior.
 */
const VELOCITY_DECAY = 0.92
const VELOCITY_STOP = 0.5
const DRAG_THRESHOLD_PX = 4

const Carousel = {
  mounted() {
    this._track = this.el.querySelector<HTMLElement>("[data-carousel-track]")
    this._prev = this.el.querySelector<HTMLElement>("[data-carousel-prev]")
    this._next = this.el.querySelector<HTMLElement>("[data-carousel-next]")

    if (!this._track) return

    this._isDragging = false
    this._dragMoved = false
    this._startX = 0
    this._startScroll = 0
    this._lastX = 0
    this._lastMoveTime = 0
    this._velocity = 0
    this._momentumFrame = null as number | null

    this._onMouseDown = (e: MouseEvent) => this.startDrag(e.pageX)
    this._onMouseMove = (e: MouseEvent) => this.moveDrag(e.pageX, e)
    this._onMouseUp = () => this.endDrag()
    this._onMouseLeave = () => this.endDrag()

    this._onTouchStart = (e: TouchEvent) => this.startDrag(e.touches[0].pageX)
    this._onTouchMove = (e: TouchEvent) => this.moveDrag(e.touches[0].pageX)
    this._onTouchEnd = () => this.endDrag()

    this._onClickCapture = (e: MouseEvent) => {
      if (this._dragMoved) {
        e.preventDefault()
        e.stopPropagation()
        this._dragMoved = false
      }
    }

    this._track.addEventListener("mousedown", this._onMouseDown)
    window.addEventListener("mousemove", this._onMouseMove)
    window.addEventListener("mouseup", this._onMouseUp)
    this._track.addEventListener("mouseleave", this._onMouseLeave)

    this._track.addEventListener("touchstart", this._onTouchStart, {
      passive: true,
    })
    this._track.addEventListener("touchmove", this._onTouchMove, {
      passive: true,
    })
    this._track.addEventListener("touchend", this._onTouchEnd)

    this._track.addEventListener("click", this._onClickCapture, true)

    this._prev?.addEventListener("click", () => this.scrollBy(-1))
    this._next?.addEventListener("click", () => this.scrollBy(1))

    this._savedScroll = 0
  },

  updated() {
    if (this._track && this._savedScroll) {
      this._track.scrollLeft = this._savedScroll
    }
  },

  startDrag(x: number) {
    if (!this._track) return
    this.cancelMomentum()
    this._isDragging = true
    this._dragMoved = false
    this._startX = x
    this._startScroll = this._track.scrollLeft
    this._lastX = x
    this._lastMoveTime = performance.now()
    this._velocity = 0
    this._track.classList.add("is-dragging")
  },

  moveDrag(x: number, e?: MouseEvent) {
    if (!this._isDragging || !this._track) return

    const dx = x - this._startX
    if (Math.abs(dx) > DRAG_THRESHOLD_PX) {
      this._dragMoved = true
      e?.preventDefault()
    }

    this._track.scrollLeft = this._startScroll - dx

    const now = performance.now()
    const dt = now - this._lastMoveTime
    if (dt > 0) {
      this._velocity = (this._lastX - x) / dt
    }
    this._lastX = x
    this._lastMoveTime = now
  },

  endDrag() {
    if (!this._isDragging || !this._track) return
    this._isDragging = false
    this._track.classList.remove("is-dragging")
    this.savePosition()

    if (Math.abs(this._velocity) > VELOCITY_STOP / 10) {
      this.startMomentum()
    }
  },

  startMomentum() {
    const step = () => {
      if (!this._track) return
      // velocity is px/ms; apply at ~16ms per frame
      this._track.scrollLeft += this._velocity * 16
      this._velocity *= VELOCITY_DECAY

      if (Math.abs(this._velocity) < VELOCITY_STOP / 10) {
        this.cancelMomentum()
        this.savePosition()
        return
      }
      this._momentumFrame = requestAnimationFrame(step)
    }
    this._momentumFrame = requestAnimationFrame(step)
  },

  cancelMomentum() {
    if (this._momentumFrame) {
      cancelAnimationFrame(this._momentumFrame)
      this._momentumFrame = null
    }
  },

  scrollBy(direction: number) {
    if (!this._track) return
    const amount = this._track.clientWidth * 0.75 * direction
    this._track.scrollBy({ left: amount, behavior: "smooth" })

    setTimeout(() => this.savePosition(), 400)
  },

  savePosition() {
    if (this._track) {
      this._savedScroll = this._track.scrollLeft
    }
  },

  destroyed() {
    this.cancelMomentum()

    if (this._track) {
      this._track.removeEventListener("mousedown", this._onMouseDown)
      this._track.removeEventListener("mouseleave", this._onMouseLeave)
      this._track.removeEventListener("touchstart", this._onTouchStart)
      this._track.removeEventListener("touchmove", this._onTouchMove)
      this._track.removeEventListener("touchend", this._onTouchEnd)
      this._track.removeEventListener("click", this._onClickCapture, true)
    }
    window.removeEventListener("mousemove", this._onMouseMove)
    window.removeEventListener("mouseup", this._onMouseUp)
  },
}

export default Carousel
