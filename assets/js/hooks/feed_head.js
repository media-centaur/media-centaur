// assets/js/hooks/feed_head.js
//
// The Feed column's head leaving and returning to the viewport, reported
// once per crossing, so the LiveView knows whether an arrival may move the
// column: at the top an arrival prepends live; scrolled in, it waits behind
// "N new" (UIDR-046). The page scrolls the window, so the observer's root
// is the viewport and scroll-to-top is the window's. The sentinel is a
// one-pixel element at the column's top; the server keeps the head, this
// hook only reports the crossing.
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
    this.handleEvent("feed:scroll_top", () => window.scrollTo({ top: 0, behavior: "instant" }))
  },

  destroyed() {
    this.observer?.disconnect()
  },
}
