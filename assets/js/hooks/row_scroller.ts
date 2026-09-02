/**
 * RowScroller hook
 *
 * Used by: ViewerComponents.content_row (HomeLive, WatchLive)
 *
 * Adds left/right arrow navigation to horizontally scrollable content rows.
 * Scrolls by the visible width of the container on each click.
 *
 * No server events -- purely client-side behavior.
 */
import { ViewHook } from "phoenix_live_view"

class RowScroller extends ViewHook {
  private container: HTMLElement | null = null
  private prevBtn: HTMLElement | null = null
  private nextBtn: HTMLElement | null = null
  private _onResize: (() => void) | null = null

  mounted() {
    this.container = this.el.querySelector<HTMLElement>(".content-row-items")
    this.prevBtn = this.el.querySelector<HTMLElement>(".row-arrow-prev")
    this.nextBtn = this.el.querySelector<HTMLElement>(".row-arrow-next")

    if (!this.container) return

    this.prevBtn?.addEventListener("click", () => this.scrollPrev())
    this.nextBtn?.addEventListener("click", () => this.scrollNext())

    this.container.addEventListener("scroll", () => this.updateArrows(), {
      passive: true,
    })

    this._onResize = () => this.updateArrows()
    window.addEventListener("resize", this._onResize)

    this.updateArrows()
  }

  private scrollPrev() {
    if (!this.container) return
    const scrollAmount = this.container.clientWidth * 0.8
    this.container.scrollBy({ left: -scrollAmount, behavior: "smooth" })
  }

  private scrollNext() {
    if (!this.container) return
    const scrollAmount = this.container.clientWidth * 0.8
    this.container.scrollBy({ left: scrollAmount, behavior: "smooth" })
  }

  destroyed() {
    if (this._onResize) {
      window.removeEventListener("resize", this._onResize)
    }
  }

  private updateArrows() {
    if (!this.container) return
    const { scrollLeft, scrollWidth, clientWidth } = this.container
    const atStart = scrollLeft <= 0
    const atEnd = scrollLeft + clientWidth >= scrollWidth - 1

    this.prevBtn?.classList.toggle("row-arrow-hidden", atStart)
    this.nextBtn?.classList.toggle("row-arrow-hidden", atEnd)
  }
}

export default RowScroller
