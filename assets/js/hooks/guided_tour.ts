/**
 * GuidedTour hook
 *
 * Launches the Shepherd admin walkthrough for a new operator. Auto-starts the
 * first time an admin lands on the dashboard (`data-auto-start="true"`) and can
 * be re-triggered by the server pushing a `start-tour` event (the "Take a tour"
 * link). When the tour finishes or is dismissed it tells the server via
 * `tour_completed` so it never auto-starts again for this operator.
 *
 * All tour logic lives in `../tour`; this hook is a thin bridge between the
 * LiveView and that module.
 */

import { buildAdminTour } from "../tour"

const GuidedTour = {
  mounted(this: any) {
    this._brand = this.el.dataset.tourBrand || "Marquee"
    this._active = null

    this.handleEvent("start-tour", () => this.run())

    if (this.el.dataset.autoStart === "true") {
      // Let the sidebar render before Shepherd measures anchor positions.
      setTimeout(() => this.run(), 400)
    }
  },

  run(this: any) {
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
  },

  destroyed(this: any) {
    if (this._active) {
      this._active.cancel()
      this._active = null
    }
  },
}

export default GuidedTour
