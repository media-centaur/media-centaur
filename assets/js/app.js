// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/media_centaur"
import {createInputHook} from "./input/index"
import {Console} from "./hooks/console"
import {LogTail} from "./hooks/log_tail"
import {CopyButton} from "./hooks/copy_button"
import {MouseAutofocus, shouldAutofocus} from "./hooks/mouse_autofocus"
import {FlashAutoDismiss} from "./hooks/flash_auto_dismiss"
import {SidebarTooltip} from "./hooks/sidebar_tooltip"
import {installReconnectOnVisible} from "./reconnect_on_visible"
import topbar from "../vendor/topbar"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  params: {_csrf_token: csrfToken},
  hooks: {
    ...colocatedHooks,
    InputSystem: createInputHook(),
    Console,
    LogTail,
    CopyButton,
    MouseAutofocus,
    FlashAutoDismiss,
    SidebarTooltip,
    // Publishes the detail scroller's measured geometry as CSS vars for
    // the pinned orientation block's backing replicas — layout facts CSS
    // cannot read about itself:
    //
    // --modal-rail-w: the reserved scrollbar gutter. The block lives
    //   inside this scroller, so it is narrower than the panel by the
    //   gutter, while the panel backdrop deliberately extends under it so
    //   the rail sits over the picture. The backing's clip window adds
    //   the gutter back, or the two backdrop copies cover different boxes
    //   and drift apart (same image, two `cover` scales — visible as a
    //   ghosted second image toward the right edge).
    //
    // --detail-pin-scroll: the scroll offset at which the block pins
    //   (its in-flow top reaches the pin inset). Phases the backing's
    //   sheet replica: post-pin the content sheet keeps moving while the
    //   block doesn't, so the replica translates by −(scroll − pin) — a
    //   scroll-driven animation whose range starts here.
    DetailScrollGeometry: {
      mounted() {
        this._ro = new ResizeObserver(() => this._publish())
        this._observed = new Set()
        this._publish()
      },
      // The vars live in a client-written inline style, and morphdom syncs
      // patched elements back to the server-rendered markup (which has no
      // style attribute) — so any LiveView patch that touches the scroller
      // (e.g. a season toggle) silently wipes them, and the ResizeObserver
      // never re-fires because nothing resized. Re-assert after every
      // patch. Regression: collapse+re-expand a season left the backing
      // 14px (one rail) narrower than the panel backdrop.
      updated() {
        this._publish()
      },
      destroyed() {
        if (this._ro) this._ro.disconnect()
      },
      // Observe once per node (re-observing would re-fire the initial
      // delivery and loop). The scroller catches viewport/panel resizes;
      // the content wrapper catches in-flow growth the scroller can't
      // see (late-loading lockup imagery, list changes), so the
      // published geometry never goes stale between resizes.
      _observe(el) {
        if (el && !this._observed.has(el)) {
          this._observed.add(el)
          this._ro.observe(el)
        }
      },
      _publish() {
        this._observe(this.el)
        this._observe(this.el.querySelector(".modal-page-content"))
        // Layout pixels throughout (offsetTop/offsetHeight/computed
        // `top`, never getBoundingClientRect) — the UI runs under a
        // root zoom, and rects come back in visual pixels.
        const rail = this.el.offsetWidth - this.el.clientWidth
        this.el.style.setProperty("--modal-rail-w", `${rail}px`)

        const block = this.el.querySelector("[data-role='detail-orientation']")
        const content = this.el.querySelector("#detail-content")
        if (!block || !content) return
        // The block's in-flow position can't be read off the block itself
        // (sticky offsets shift offsetTop while stuck), but the content
        // region below it is never sticky: block in-flow top = content
        // top − block height, both stable at any scroll depth. The
        // content's negative margin (--detail-sheet-reach — the sheet's
        // box extending up behind the block) shifts its offsetTop above
        // the block's flow bottom; subtracting the measured margin
        // recovers the true flow edge.
        let contentTop = 0
        for (let el = content; el && el !== this.el; el = el.offsetParent) {
          contentTop += el.offsetTop
        }
        const contentMarginTop = parseFloat(getComputedStyle(content).marginTop) || 0
        const pinInset = parseFloat(getComputedStyle(block).top) || 0
        const pinScroll = contentTop - contentMarginTop - block.offsetHeight - pinInset
        this.el.style.setProperty("--detail-pin-scroll", `${Math.max(0, pinScroll)}px`)
      }
    },
    ScrollToResume: {
      mounted() { this._scrollToTarget() },
      updated() {
        if (this.el.dataset.entityId !== this._lastEntityId) {
          this._scrollToTarget()
        }
      },
      _scrollToTarget() {
        this._lastEntityId = this.el.dataset.entityId
        // `data-scroll-to-resume` is the only signal for whether to
        // scroll — the server decides (DetailPanel.autoscroll_resume?/1).
        // A target row can exist without being somewhere to return to:
        // an unstarted series highlights its first episode but opens on
        // the hero.
        if (this.el.dataset.scrollToResume === undefined) return
        const target = this.el.querySelector("[data-resume-target]")
        if (target) {
          requestAnimationFrame(() => {
            this._reserveOrientationBlock()
            target.scrollIntoView({ block: "center", behavior: "instant" })
          })
        }
      },
      // The orientation block pins over the top of the scrollport, so the
      // region a row can actually be seen in starts below it. Centering
      // against the raw scrollport puts the next episode *behind* the
      // block — measured at over half the scrollport's height on a
      // 1920x1080 display. scroll-padding is the platform's own name for
      // this: it insets the "optimal viewing region" that block:"center"
      // centers within. Left set on the port so later programmatic
      // scrolls (keyboard/gamepad nav stepping through episode rows)
      // land clear of the block too.
      _reserveOrientationBlock() {
        const port = this.el.closest(".modal-detail-scroll")
        const block = port && port.querySelector("[data-role='detail-orientation']")
        if (!port || !block) return
        // Layout pixels throughout — offsetHeight/clientHeight/computed
        // `top`, never getBoundingClientRect(). The media-center UI runs
        // under a `--ui-scale` transform, so rects come back in visual
        // pixels and mixing the two silently doubles one side.
        //
        // Sticky `top` is the gap the block pins at; height is constant
        // whether pinned or at rest, so this is safe to read pre-scroll.
        const pinInset = parseFloat(getComputedStyle(block).top) || 0
        const reserved = pinInset + block.offsetHeight
        // A port too short to hold the block plus a row would push the
        // target off the bottom — leave the default padding alone there.
        if (reserved > port.clientHeight - 96) return
        port.style.scrollPaddingTop = `${Math.round(reserved)}px`
      }
    },
  },
})

// Incoming page: "Clear search" wipes the omnibox input client-side. The
// server resets @omnibox_query, but LiveView never overwrites a focused
// input's value — without this, the stale text would sit in the box.
window.addEventListener("omnibox:clear-input", (event) => {
  event.target.value = ""
})

// Incoming page: closing the plan modal hands the page back to searching, so
// focus returns to the omnibox — pointer users only (same gate as
// MouseAutofocus): for keyboard/gamepad the input system owns focus (ADR-053).
window.addEventListener("phx:omnibox:refocus", () => {
  if (shouldAutofocus(document.documentElement.dataset.input)) {
    document.getElementById("omnibox-media-input")?.focus()
  }
})

// Upcoming page: clicking a marked day in the mini-month scrolls the rail to
// that day's first release card (LiveView pushes the date; only marked days
// are clickable, so a matching card always exists).
window.addEventListener("phx:upcoming:scroll_to_day", ({detail}) => {
  const card = document.querySelector(`[data-nav-zone="rail"] [data-date="${detail.date}"]`)
  card?.scrollIntoView({behavior: "smooth", block: "center"})
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(800))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// Self-update reboot: while an update is being applied, mark <html> so the
// disconnect toast that follows the restart reads as a calm "Applying update"
// rather than the red "Media Centaur isn't responding" error (see layouts.ex). The
// flag is cleared on reconnect by the toast's phx-connected handler, and here
// if the apply fails/stalls/cancels so a genuine disconnect still shows red.
window.addEventListener("phx:mc:update:applying", () =>
  document.documentElement.setAttribute("data-update-applying", "1"))
window.addEventListener("phx:mc:update:aborted", () =>
  document.documentElement.removeAttribute("data-update-applying"))

// Global bindings (backtick, etc.). Reads the current binding from the
// root layout's data-global-bindings attr and listens for updates.
let globalBindings = parseGlobalBindings()

function parseGlobalBindings() {
  try {
    return JSON.parse(document.getElementById("input-system")?.dataset?.globalBindings ?? "{}")
  } catch {
    return {}
  }
}

// Global hotkey to toggle the console. Registered in CAPTURE phase
// so it fires before the input system's bubble-phase keydown listener (which
// calls stopPropagation on unknown keys, which would swallow our hotkey).
//
// The key is read from data-global-bindings (defaults to "`") so the user
// can rebind it from Settings > Controls without a page reload.
//
// Skipped when focused in an input/textarea so the user can type the key
// in form fields normally.
document.addEventListener(
  "keydown",
  (event) => {
    const tag = event.target?.tagName
    if (tag === "INPUT" || tag === "TEXTAREA") return
    if (event.target?.isContentEditable) return
    if (event.ctrlKey || event.metaKey || event.altKey) return

    const consoleKey = globalBindings.toggle_console
    if (!consoleKey || event.key !== consoleKey) return

    event.preventDefault()
    event.stopPropagation()
    window.dispatchEvent(new CustomEvent("mc:console:toggle"))
  },
  { capture: true }
)

window.addEventListener("input:rebindMaps", () => {
  globalBindings = parseGlobalBindings()
})

// connect if there are any LiveViews on the page
liveSocket.connect()
installReconnectOnVisible(liveSocket)

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

