/**
 * HeroCarousel hook
 *
 * Used by: HomeLive
 *
 * Auto-advancing carousel for the homepage hero section.
 * Handles slide transitions, pagination dots, auto-advance timer,
 * pause-on-hover, prev/next arrow navigation, and keyboard support.
 *
 * DOM attributes read:
 *   - data-auto-advance: Interval in ms between auto-advances.
 *     Set to "0" to disable auto-advance entirely. Default: 8000.
 *
 * Accessibility:
 *   - Respects prefers-reduced-motion (disables auto-advance + transitions)
 *   - Arrow key navigation when carousel is focused
 *   - Updates aria-selected on pagination dots
 *
 * No server events -- this is purely client-side behavior.
 */
import { ViewHook } from "phoenix_live_view"

class HeroCarousel extends ViewHook {
  private slides!: NodeListOf<HTMLElement>
  private dots!: NodeListOf<HTMLElement>
  private prevBtn: HTMLElement | null = null
  private nextBtn: HTMLElement | null = null
  private activeIndex = 0
  private totalSlides = 0
  private prefersReducedMotion = false
  private timer: ReturnType<typeof setInterval> | null = null

  mounted() {
    this.slides = this.el.querySelectorAll<HTMLElement>(".hero-slide")
    this.dots = this.el.querySelectorAll<HTMLElement>(".hero-dot")
    this.prevBtn = this.el.querySelector<HTMLElement>(".hero-arrow-prev")
    this.nextBtn = this.el.querySelector<HTMLElement>(".hero-arrow-next")
    this.activeIndex = 0
    this.totalSlides = this.slides.length
    this.prefersReducedMotion = window.matchMedia(
      "(prefers-reduced-motion: reduce)"
    ).matches

    if (this.totalSlides <= 1) {
      this.prevBtn?.classList.add("hidden")
      this.nextBtn?.classList.add("hidden")
      return
    }

    const interval = parseInt(this.el.dataset.autoAdvance || "8000", 10)

    // Dot click handlers
    this.dots.forEach((dot: HTMLElement, index: number) => {
      dot.addEventListener("click", () => this.goToSlide(index))
    })

    // Arrow click handlers
    this.prevBtn?.addEventListener("click", () => this.prevSlide())
    this.nextBtn?.addEventListener("click", () => this.nextSlide())

    // Keyboard navigation
    this.el.addEventListener("keydown", (e: KeyboardEvent) => {
      if (e.key === "ArrowLeft") {
        e.preventDefault()
        this.prevSlide()
      } else if (e.key === "ArrowRight") {
        e.preventDefault()
        this.nextSlide()
      }
    })

    // Auto-advance (only if interval > 0 and user hasn't requested reduced motion)
    if (interval > 0 && !this.prefersReducedMotion) {
      this.startAutoAdvance(interval)

      // Pause on hover
      this.el.addEventListener("mouseenter", () => this.stopAutoAdvance())
      this.el.addEventListener("mouseleave", () =>
        this.startAutoAdvance(interval)
      )
    }
  }

  private goToSlide(index: number) {
    if (index === this.activeIndex) return

    this.slides[this.activeIndex]?.classList.remove("active")
    this.dots[this.activeIndex]?.classList.remove("active")
    this.dots[this.activeIndex]?.setAttribute("aria-selected", "false")

    this.activeIndex = index
    this.slides[this.activeIndex]?.classList.add("active")
    this.dots[this.activeIndex]?.classList.add("active")
    this.dots[this.activeIndex]?.setAttribute("aria-selected", "true")
  }

  private nextSlide() {
    const next = (this.activeIndex + 1) % this.totalSlides
    this.goToSlide(next)
  }

  private prevSlide() {
    const prev = (this.activeIndex - 1 + this.totalSlides) % this.totalSlides
    this.goToSlide(prev)
  }

  private startAutoAdvance(interval: number) {
    this.stopAutoAdvance()
    if (interval > 0 && !this.prefersReducedMotion) {
      this.timer = setInterval(() => this.nextSlide(), interval)
    }
  }

  private stopAutoAdvance() {
    if (this.timer) {
      clearInterval(this.timer)
      this.timer = null
    }
  }

  destroyed() {
    this.stopAutoAdvance()
  }
}

export default HeroCarousel
