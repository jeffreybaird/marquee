/**
 * CopyToClipboard hook
 *
 * Copies the value of `data-copy-value` to the clipboard when the host
 * element is clicked. Briefly swaps the element's text with the value of
 * `data-copy-confirm` (default: "Copied") to confirm to the user.
 *
 * No server events — purely client-side behavior.
 */
import { ViewHook } from "phoenix_live_view"

const CONFIRM_MS = 1500

class CopyToClipboard extends ViewHook {
  private _timer: ReturnType<typeof setTimeout> | null = null
  private _originalText = ""

  mounted() {
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
  }

  private flashConfirm() {
    const confirmText = this.el.dataset.copyConfirm ?? "Copied"

    // While a confirmation is showing, the element's text is the confirmation
    // itself, so only capture the label when none is pending.
    if (this._timer) {
      clearTimeout(this._timer)
    } else {
      this._originalText = this.el.textContent ?? ""
    }

    this.el.textContent = confirmText
    this._timer = setTimeout(() => {
      this.el.textContent = this._originalText
      this._timer = null
    }, CONFIRM_MS)
  }

  private fallbackCopy(value: string) {
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
  }

  destroyed() {
    if (this._timer) clearTimeout(this._timer)
  }
}

export default CopyToClipboard
