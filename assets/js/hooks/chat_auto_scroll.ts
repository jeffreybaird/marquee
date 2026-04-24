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
const NEAR_BOTTOM_PX = 80

const ChatAutoScroll = {
  mounted(this: any) {
    this.stickToBottom = true

    this.scrollToBottom = () => {
      this.el.scrollTop = this.el.scrollHeight
    }

    this.handleScroll = () => {
      const distanceFromBottom =
        this.el.scrollHeight - this.el.scrollTop - this.el.clientHeight
      this.stickToBottom = distanceFromBottom < NEAR_BOTTOM_PX
    }

    this.el.addEventListener("scroll", this.handleScroll, { passive: true })
    requestAnimationFrame(this.scrollToBottom)
  },

  updated(this: any) {
    if (this.stickToBottom) {
      requestAnimationFrame(this.scrollToBottom)
    }
  },

  destroyed(this: any) {
    this.el.removeEventListener("scroll", this.handleScroll)
  },
}

export default ChatAutoScroll
