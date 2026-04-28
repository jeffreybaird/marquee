/**
 * CopyToClipboard hook
 *
 * Copies the value of `data-copy-value` to the clipboard when the host
 * element is clicked. Briefly swaps the element's text with the value of
 * `data-copy-confirm` (default: "Copied") to confirm to the user.
 *
 * No server events — purely client-side behavior.
 */
const CONFIRM_MS = 1500

const CopyToClipboard = {
  mounted() {
    this._timer = null as ReturnType<typeof setTimeout> | null

    this.el.addEventListener("click", async (e: MouseEvent) => {
      e.preventDefault()
      const value = this.el.dataset.copyValue ?? ""
      if (!value) return

      try {
        await navigator.clipboard.writeText(value)
        this.flashConfirm()
      } catch (_err) {
        // Older browsers / non-secure contexts — fall back to a hidden textarea.
        this.fallbackCopy(value)
        this.flashConfirm()
      }
    })
  },

  flashConfirm() {
    const confirmText = this.el.dataset.copyConfirm ?? "Copied"
    const original = this.el.textContent ?? ""
    this.el.textContent = confirmText

    if (this._timer) clearTimeout(this._timer)
    this._timer = setTimeout(() => {
      this.el.textContent = original
      this._timer = null
    }, CONFIRM_MS)
  },

  fallbackCopy(value: string) {
    const ta = document.createElement("textarea")
    ta.value = value
    ta.setAttribute("readonly", "")
    ta.style.position = "absolute"
    ta.style.left = "-9999px"
    document.body.appendChild(ta)
    ta.select()
    try {
      document.execCommand("copy")
    } finally {
      ta.remove()
    }
  },

  destroyed() {
    if (this._timer) clearTimeout(this._timer)
  },
}

export default CopyToClipboard
