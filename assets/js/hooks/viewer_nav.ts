/**
 * ViewerNav hook
 *
 * Used by: ViewerLayout.viewer_header (all viewer pages)
 *
 * Makes the viewer navigation bar transition from transparent to solid
 * background as the user scrolls past the hero section.
 *
 * No server events — purely client-side scroll listener.
 *
 * @dom data-scroll-threshold - pixels before nav becomes solid (default: 50)
 */
const ViewerNav = {
  mounted() {
    this.threshold = parseInt(this.el.dataset.scrollThreshold || "50", 10)

    this.onScroll = () => {
      const scrolled = window.scrollY > this.threshold
      this.el.classList.toggle("sv-nav-solid", scrolled)
    }

    window.addEventListener("scroll", this.onScroll, { passive: true })
    this.onScroll()
  },

  destroyed() {
    if (this.onScroll) {
      window.removeEventListener("scroll", this.onScroll)
    }
  },
}

export default ViewerNav
