/**
 * "UI overhaul in progress" navigation notice.
 *
 * Some pages (upcoming, history, downloads, status) are mid-redesign:
 * their in-page keyboard/gamepad navigation is still being built — some
 * have partial nav, some none. Rather than silently doing nothing, or
 * half-something, when a user reaches for the d-pad or arrow keys, we
 * surface a small floating notice near the gamepad hint bar so the
 * missing capability is explained rather than mysterious.
 *
 * `withWipNotice` is a decorator applied in `page_behavior.js`: the set of
 * wrapped registry entries is the single source of truth for which pages
 * carry the notice. It is purely additive — the wrapped behavior's own
 * `onAction` result is returned unchanged, so whatever nav those pages do
 * have keeps running. When a page's nav is finished, drop the wrapper from
 * its registry entry and the notice stops appearing there.
 *
 * The notice element and its styling live in `root.html.heex` / `app.css`
 * (`[data-wip-notice]` / `.wip-notice`), as a sibling of the gamepad hint
 * bar. Unlike the hint bar — which is CSS-gated on `data-input=gamepad` —
 * the notice is toggled by class so it surfaces for keyboard users too.
 */

/** How long the notice stays visible after the last action, in ms. */
const VISIBLE_MS = 3200

/** Default DOM implementation for production use. */
const REAL_DOM = (() => {
  let hideTimer = null
  return {
    flash() {
      const notice = document.querySelector("[data-wip-notice]")
      if (!notice) return
      notice.classList.add("wip-notice-visible")
      clearTimeout(hideTimer)
      hideTimer = setTimeout(() => notice.classList.remove("wip-notice-visible"), VISIBLE_MS)
    },
  }
})()

/**
 * Wrap a page behavior so any nav action flashes the WIP notice before
 * being processed normally.
 *
 * @param {import("./page_behavior").PageBehavior} behavior - the page behavior to wrap
 * @param {{flash: function(): void}} [dom] - injectable notice DOM (mocked in tests)
 * @returns {import("./page_behavior").PageBehavior}
 */
export function withWipNotice(behavior, dom = REAL_DOM) {
  return {
    ...behavior,
    onAction(action, context, focused) {
      dom.flash()
      return behavior.onAction?.(action, context, focused) ?? false
    },
  }
}

/** Re-export the real DOM for the registry to pass through in production. */
export { REAL_DOM as wipNoticeDom }
