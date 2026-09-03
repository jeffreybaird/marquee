/**
 * PageTour hook
 *
 * Launches a per-page Shepherd walkthrough the first time a person visits an
 * admin page. Which tour runs is selected by `data-tour-page`, looked up in the
 * `PAGE_TOURS` registry. Auto-starts once when `data-auto-start="true"`, and can
 * be replayed when the server pushes `start-page-tour` (the "Page tour" link).
 * When the tour finishes or is dismissed it tells the server via
 * `page_tour_completed` (with the page key) so it never auto-starts again for
 * this person on this page.
 *
 * A page with no entry in `PAGE_TOURS` is inert — the hook simply does nothing,
 * so it is safe to mount speculatively.
 *
 * Dataset attributes:
 *   - data-tour-page: page key selecting the step set (e.g. "content")
 *   - data-tour-brand: Organization name substituted into the tour copy (default "Marquee")
 *   - data-auto-start: "true" to start the tour 400ms after mount
 *
 * Events received from server:
 *   - "start-page-tour" {}
 *
 * Events sent to server:
 *   - "page_tour_completed" { page }
 *
 * All tour logic lives in `../tour`; this hook is a thin bridge between the
 * LiveView and that module.
 */
import { ViewHook } from "phoenix_live_view"
import type { Tour } from "../../vendor/shepherd"

import { buildTour } from "../tour"
import { PAGE_TOURS } from "../tour/steps"

const AUTO_START_DELAY_MS = 400

class PageTour extends ViewHook {
  private _brand = "Marquee"
  private _page = ""
  private _active: Tour | null = null
  private _autoStartTimer: ReturnType<typeof setTimeout> | null = null

  mounted() {
    this._brand = this.el.dataset.tourBrand || "Marquee"
    this._page = this.el.dataset.tourPage || ""

    this.handleEvent("start-page-tour", () => this.run())

    if (this.el.dataset.autoStart === "true") {
      // Let the page render before Shepherd measures anchor positions. Guarded
      // by destroyed() so navigating away before it fires doesn't launch the
      // tour on the next page.
      this._autoStartTimer = setTimeout(() => {
        this._autoStartTimer = null
        this.run()
      }, AUTO_START_DELAY_MS)
    }
  }

  private run() {
    // Guard against a second concurrent tour (e.g. clicking "Page tour" while
    // one is already open).
    if (this._active) return

    const steps = PAGE_TOURS[this._page]
    if (!steps) return

    const tour = buildTour(steps, this._brand)
    this._active = tour

    const finish = () => {
      this._active = null
      this.pushEvent("page_tour_completed", { page: this._page })
    }

    tour.on("complete", finish)
    tour.on("cancel", finish)
    tour.start()
  }

  destroyed() {
    if (this._autoStartTimer) {
      clearTimeout(this._autoStartTimer)
      this._autoStartTimer = null
    }
    if (this._active) {
      this._active.cancel()
      this._active = null
    }
  }
}

export default PageTour
