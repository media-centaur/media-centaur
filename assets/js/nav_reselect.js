// Re-selecting the current page in the sidebar is a "take me back to the
// top" gesture (UIDR-026). Left alone, LiveView would remount the page the
// reader is already on — a flash and a state reset for no navigation at all —
// so the click is intercepted in the capture phase, before LiveView's own
// link handling sees it, and turned into a scroll instead. When only the
// query string differs (a filtered view), the navigation is real and
// proceeds; the scroll-to-top still applies.
export function installNavReselect(doc = document, win = window) {
  doc.addEventListener(
    "click",
    (event) => {
      const link = event.target.closest?.("#sidebar a[href]")
      if (!link) return

      const destination = new URL(link.getAttribute("href"), win.location.href)
      if (destination.pathname !== win.location.pathname) return

      if (destination.search === win.location.search) {
        event.preventDefault()
        event.stopPropagation()
      }
      win.scrollTo({ top: 0, behavior: "smooth" })
    },
    true
  )
}
