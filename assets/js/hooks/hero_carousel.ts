/**
 * HeroCarousel hook
 *
 * Auto-advancing carousel for the homepage hero section.
 * Handles slide transitions, pagination dots, auto-advance timer,
 * and pause-on-hover.
 *
 * DOM attributes read:
 *   - data-auto-advance: Interval in ms between auto-advances (default: 8000)
 *
 * No server events -- this is purely client-side behavior.
 */
const HeroCarousel = {
  mounted() {
    this.slides = this.el.querySelectorAll<HTMLElement>(".hero-slide")
    this.dots = this.el.querySelectorAll<HTMLElement>(".hero-dot")
    this.activeIndex = 0
    this.totalSlides = this.slides.length

    if (this.totalSlides <= 1) return

    const interval = parseInt(this.el.dataset.autoAdvance || "8000", 10)

    // Dot click handlers
    this.dots.forEach((dot: HTMLElement, index: number) => {
      dot.addEventListener("click", () => this.goToSlide(index))
    })

    // Auto-advance
    this.startAutoAdvance(interval)

    // Pause on hover
    this.el.addEventListener("mouseenter", () => this.stopAutoAdvance())
    this.el.addEventListener("mouseleave", () =>
      this.startAutoAdvance(interval)
    )

    // Store interval for resume
    this.interval = interval
  },

  goToSlide(index: number) {
    if (index === this.activeIndex) return

    // Deactivate current
    this.slides[this.activeIndex]?.classList.remove("active")
    this.dots[this.activeIndex]?.classList.remove("active")

    // Activate new
    this.activeIndex = index
    this.slides[this.activeIndex]?.classList.add("active")
    this.dots[this.activeIndex]?.classList.add("active")
  },

  nextSlide() {
    const next = (this.activeIndex + 1) % this.totalSlides
    this.goToSlide(next)
  },

  startAutoAdvance(interval: number) {
    this.stopAutoAdvance()
    this.timer = setInterval(() => this.nextSlide(), interval)
  },

  stopAutoAdvance() {
    if (this.timer) {
      clearInterval(this.timer)
      this.timer = null
    }
  },

  destroyed() {
    this.stopAutoAdvance()
  },
}

export default HeroCarousel
