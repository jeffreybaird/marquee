/**
 * Sortable hook
 *
 * Used by: Admin.CatalogLive (row reordering)
 *
 * Enables drag-and-drop reordering in the admin row builder.
 * Uses the native HTML5 drag-and-drop API.
 *
 * Dataset attributes:
 *   - data-group: sortable group name (items in the same group can be reordered)
 *
 * Events sent to server:
 *   - "reordered" { ids: string[] }
 *
 * Events received from server: none
 */
const Sortable = {
  mounted() {
    // Initialize drag-and-drop event listeners
  },

  destroyed() {
    // Clean up drag-and-drop event listeners
  },
}

export default Sortable
