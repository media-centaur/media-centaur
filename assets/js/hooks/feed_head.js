// assets/js/hooks/feed_head.js
//
// The Feed column's head leaving and returning to the viewport, reported
// once per crossing, so the LiveView knows whether an arrival may move the
// column: at the top an arrival prepends live; scrolled in, it waits behind
// "N new" (UIDR-046). The page scrolls the window, so the observer's root
// is the viewport and scroll-to-top is the window's. The sentinel is a
// one-pixel element at the column's top; the server keeps the head, this
// hook only reports the crossing. "N new" dispatches `feed:scroll-top` on
// the sentinel: the scroll happens here, and the crossing it causes is what
// tells the server to land the queue.
export const FeedHead = {
  mounted() {
    this.atTop = true
    this.observer = new IntersectionObserver(([entry]) => {
      const atTop = entry.isIntersecting
      if (atTop === this.atTop) return
      this.atTop = atTop
      this.pushEvent(atTop ? "feed_at_top" : "feed_scrolled", {})
    })
    this.observer.observe(this.el)
    this.onScrollTop = () => window.scrollTo({ top: 0, behavior: "instant" })
    this.el.addEventListener("feed:scroll-top", this.onScrollTop)
  },

  destroyed() {
    this.observer?.disconnect()
    this.el.removeEventListener("feed:scroll-top", this.onScrollTop)
  },
}
