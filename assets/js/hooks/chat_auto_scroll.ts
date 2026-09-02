/**
 * ChatAutoScroll hook
 *
 * Used by: LiveEventWatchLive chat panel
 *
 * Keeps the chat message list pinned to the bottom as new messages stream in,
 * but respects the viewer's scroll position — if they've scrolled up to read
 * older messages, new arrivals do not yank them back down.
 *
 * Attach to the scrollable messages container (the element with
 * `phx-update="stream"`).
 */
import { ViewHook } from "phoenix_live_view"

const NEAR_BOTTOM_PX = 80

class ChatAutoScroll extends ViewHook {
  private stickToBottom = true

  private scrollToBottom = () => {
    this.el.scrollTop = this.el.scrollHeight
  }

  private handleScroll = () => {
    const distanceFromBottom =
      this.el.scrollHeight - this.el.scrollTop - this.el.clientHeight
    this.stickToBottom = distanceFromBottom < NEAR_BOTTOM_PX
  }

  mounted() {
    this.el.addEventListener("scroll", this.handleScroll, { passive: true })
    requestAnimationFrame(this.scrollToBottom)
  }

  updated() {
    if (this.stickToBottom) {
      requestAnimationFrame(this.scrollToBottom)
    }
  }

  destroyed() {
    this.el.removeEventListener("scroll", this.handleScroll)
  }
}

export default ChatAutoScroll
