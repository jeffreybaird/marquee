/**
 * GuidedTour hook
 *
 * Launches the Shepherd admin walkthrough for a new operator. Auto-starts the
 * first time an admin lands on the dashboard (`data-auto-start="true"`) and can
 * be re-triggered by the server pushing a `start-tour` event (the "Take a tour"
 * link). When the tour finishes or is dismissed it tells the server via
 * `tour_completed` so it never auto-starts again for this operator.
 *
 * Dataset attributes:
 *   - data-tour-brand: Organization name substituted into the tour copy (default "Marquee")
 *   - data-auto-start: "true" to start the tour 400ms after mount
 *
 * Events received from server:
 *   - "start-tour" {}
 *
 * Events sent to server:
 *   - "tour_completed" {}
 *
 * All tour logic lives in `../tour`; this hook is a thin bridge between the
 * LiveView and that module.
 */
import { ViewHook } from "phoenix_live_view"
import type { Tour } from "../../vendor/shepherd"

import { buildAdminTour } from "../tour"

const AUTO_START_DELAY_MS = 400

class GuidedTour extends ViewHook {
  private _brand = "Marquee"
  private _active: Tour | null = null

  mounted() {
    this._brand = this.el.dataset.tourBrand || "Marquee"

    this.handleEvent("start-tour", () => this.run())

    if (this.el.dataset.autoStart === "true") {
      // Let the sidebar render before Shepherd measures anchor positions.
      setTimeout(() => this.run(), AUTO_START_DELAY_MS)
    }
  }

  private run() {
    // Guard against a second concurrent tour (e.g. clicking "Take a tour"
    // while one is already open).
    if (this._active) return

    const tour = buildAdminTour(this._brand)
    this._active = tour

    const finish = () => {
      this._active = null
      this.pushEvent("tour_completed", {})
    }

    tour.on("complete", finish)
    tour.on("cancel", finish)
    tour.start()
  }

  destroyed() {
    if (this._active) {
      this._active.cancel()
      this._active = null
    }
  }
}

export default GuidedTour
