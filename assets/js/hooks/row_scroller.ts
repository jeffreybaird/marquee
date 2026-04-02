/**
 * RowScroller hook
 *
 * Adds left/right arrow navigation to horizontally scrollable content rows.
 * Scrolls by the visible width of the container on each click.
 *
 * No server events -- purely client-side behavior.
 */
const RowScroller = {
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
  },

  scrollPrev() {
    if (!this.container) return
    const scrollAmount = this.container.clientWidth * 0.8
    this.container.scrollBy({ left: -scrollAmount, behavior: "smooth" })
  },

  scrollNext() {
    if (!this.container) return
    const scrollAmount = this.container.clientWidth * 0.8
    this.container.scrollBy({ left: scrollAmount, behavior: "smooth" })
  },

  destroyed() {
    if (this._onResize) {
      window.removeEventListener("resize", this._onResize)
    }
  },

  updateArrows() {
    if (!this.container) return
    const { scrollLeft, scrollWidth, clientWidth } = this.container
    const atStart = scrollLeft <= 0
    const atEnd = scrollLeft + clientWidth >= scrollWidth - 1

    this.prevBtn?.classList.toggle("row-arrow-hidden", atStart)
    this.nextBtn?.classList.toggle("row-arrow-hidden", atEnd)
  },
}

export default RowScroller
