// Separate bundle for the Mux Player web component, loaded via its own
// <script> tag on pages that render <mux-player> — kept out of app.js so the
// ~1MB player is not pulled into the main bundle every page loads. The vendored
// file is a self-contained IIFE that registers the `mux-player` custom element
// as a side effect, so a bare side-effecting import is all that is needed.
import "../vendor/mux-player.js"
