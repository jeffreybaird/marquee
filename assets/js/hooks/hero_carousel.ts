/**
 * HeroCarousel hook
 *
 * Auto-advancing carousel for the homepage hero section.
 * Handles slide transitions, pagination dots, auto-advance timer,
 * pause-on-hover, and prev/next arrow navigation.
 *
 * DOM attributes read:
 *   - data-auto-advance: Interval in ms between auto-advances.
 *     Set to "0" to disable auto-advance entirely. Default: 8000.
 *
 * No server events -- this is purely client-side behavior.
 */
const HeroCarousel = {
  mounted() {
    this.slides = this.el.querySelectorAll<HTMLElement>(".hero-slide")
    this.dots = this.el.querySelectorAll<HTMLElement>(".hero-dot")
    this.prevBtn = this.el.querySelector<HTMLElement>(".hero-arrow-prev")
    this.nextBtn = this.el.querySelector<HTMLElement>(".hero-arrow-next")
    this.activeIndex = 0
    this.totalSlides = this.slides.length

    if (this.totalSlides <= 1) {
      this.prevBtn?.classList.add("hidden")
      this.nextBtn?.classList.add("hidden")
      return
    }

    const interval = parseInt(this.el.dataset.autoAdvance || "8000", 10)
    this.interval = interval

    // Dot click handlers
    this.dots.forEach((dot: HTMLElement, index: number) => {
      dot.addEventListener("click", () => this.goToSlide(index))
    })

    // Arrow click handlers
    this.prevBtn?.addEventListener("click", () => this.prevSlide())
    this.nextBtn?.addEventListener("click", () => this.nextSlide())

    // Auto-advance (only if interval > 0)
    if (interval > 0) {
      this.startAutoAdvance(interval)

      // Pause on hover
      this.el.addEventListener("mouseenter", () => this.stopAutoAdvance())
      this.el.addEventListener("mouseleave", () =>
        this.startAutoAdvance(interval)
      )
    }
  },

  goToSlide(index: number) {
    if (index === this.activeIndex) return

    this.slides[this.activeIndex]?.classList.remove("active")
    this.dots[this.activeIndex]?.classList.remove("active")

    this.activeIndex = index
    this.slides[this.activeIndex]?.classList.add("active")
    this.dots[this.activeIndex]?.classList.add("active")
  },

  nextSlide() {
    const next = (this.activeIndex + 1) % this.totalSlides
    this.goToSlide(next)
  },

  prevSlide() {
    const prev = (this.activeIndex - 1 + this.totalSlides) % this.totalSlides
    this.goToSlide(prev)
  },

  startAutoAdvance(interval: number) {
    this.stopAutoAdvance()
    if (interval > 0) {
      this.timer = setInterval(() => this.nextSlide(), interval)
    }
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
