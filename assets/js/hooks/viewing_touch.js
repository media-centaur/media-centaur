// ViewingTouch — a touch screen's way into the viewing layer (the phone
// running the TV app). A remote drives the OSD with keys; a finger has taps
// and drags, so on `#viewing-osd` a tap on the picture pushes `viewing_tap`
// (show the bar, or hide it while playing), and the seek bar is a touch
// slider: press, drag with the thumb and the time following under the
// finger, release to seek once (`seek_to`, the command a tap pushes too —
// a press and release with no move is the tap). A tap on a control (the
// prompt, the deck, Audio, subtitles & picture) is left to the control's own
// `phx-click`.
//
// While the finger holds the bar the client owns the thumb: the scrub
// element (`#viewing-scrub`, an ignored container the server renders once
// inside the bar) is positioned from one `--scrub` share, and CSS hides the
// server's fill and handle and keeps the bar up past its hide timer, so the
// session's 1 Hz tick never moves the thumb under the finger. After the
// release the scrub stays until the server's position (`aria-valuenow`,
// watched by a MutationObserver — the hook sits on the OSD, whose `updated`
// does not fire for a patch of the bar alone) reaches it, capped at a few
// seconds, so the handle never snaps back to the old position before the
// seek lands. The server learns nothing of the gesture but the one command.

export function seekSeconds(clientX, rect, duration) {
  if (!(duration > 0) || !(rect.width > 0)) return null
  const share = Math.min(Math.max((clientX - rect.left) / rect.width, 0), 1)
  return Math.round(share * duration)
}

// The clock's format (`MediaCentaur.Format.format_seconds/1`): `m:ss`
// under an hour, `h:mm:ss` from one.
export function formatClock(seconds) {
  if (!Number.isFinite(seconds) || seconds < 0) return "0:00"
  const total = Math.trunc(seconds)
  const hours = Math.floor(total / 3600)
  const mins = Math.floor((total % 3600) / 60)
  const secs = total % 60
  const pad = (n) => String(n).padStart(2, "0")
  return hours > 0 ? `${hours}:${pad(mins)}:${pad(secs)}` : `${mins}:${pad(secs)}`
}

// Where a finger on the bar is: its share of the width, the position in the
// file and the time to show over the thumb. Null when the bar cannot seek.
export function scrubAt(clientX, rect, duration) {
  const seconds = seekSeconds(clientX, rect, duration)
  if (seconds === null) return null
  const share = Math.min(Math.max((clientX - rect.left) / rect.width, 0), 1)
  return { share, seconds, label: formatClock(seconds) }
}

export function tapAction(target) {
  if (target.closest("[data-viewing-seek]")) return "seek"
  if (target.closest("button")) return null
  return "tap"
}

const SETTLE_CAP_MS = 3000

export const ViewingTouch = {
  mounted() {
    this._onClick = (event) => this._tap(event)
    this._onDown = (event) => this._press(event)
    this.el.addEventListener("click", this._onClick)
    this.el.addEventListener("pointerdown", this._onDown)
  },

  destroyed() {
    this.el.removeEventListener("click", this._onClick)
    this.el.removeEventListener("pointerdown", this._onDown)
    this._clear()
  },

  _tap(event) {
    const action = tapAction(event.target)
    if (action === "tap") this.pushEvent("viewing_tap", {})
    // "seek" is the pointer path's: the press and release already seeked.
  },

  _press(event) {
    const bar = event.target.closest("[data-viewing-seek]")
    if (!bar || event.isPrimary === false) return
    const rect = bar.getBoundingClientRect()
    const duration = Number(bar.dataset.duration)
    const at = scrubAt(event.clientX, rect, duration)
    if (!at) return

    event.preventDefault()
    this._clear()
    const state = bar.querySelector(".viewing-scrub-state")
    const time = bar.querySelector(".viewing-scrub-time")
    const { pointerId } = event
    const scrub = { bar, rect, duration, state, time, pointerId, target: null, timer: null, observer: null }
    scrub.onMove = (e) => e.pointerId === pointerId && this._render(scrubAt(e.clientX, rect, duration))
    scrub.onUp = (e) => e.pointerId === pointerId && this._release(e)
    scrub.onCancel = (e) => e.pointerId === pointerId && this._clear()
    bar.addEventListener("pointermove", scrub.onMove)
    bar.addEventListener("pointerup", scrub.onUp)
    bar.addEventListener("pointercancel", scrub.onCancel)
    // Capture keeps the moves coming when the finger leaves the bar's box;
    // a synthetic pointer (a test's) has no id to capture, which is fine.
    try {
      bar.setPointerCapture?.(pointerId)
    } catch {
      // not a captured gesture: the moves over the bar still count
    }
    this._scrub = scrub
    this._render(at)
  },

  _render(at) {
    const scrub = this._scrub
    if (!scrub || !at) return
    scrub.state.style.setProperty("--scrub", String(at.share))
    scrub.state.style.setProperty("--scrub-x", `${at.share * scrub.rect.width}px`)
    scrub.time.textContent = at.label
    scrub.state.setAttribute("data-active", "")
  },

  _release(event) {
    const scrub = this._scrub
    const at = scrubAt(event.clientX, scrub.rect, scrub.duration)
    this._detach(scrub)
    if (!at) return this._clear()
    this._render(at)
    this.pushEvent("viewing_command", { command: "seek_to", seconds: at.seconds })
    scrub.target = at.share * 100
    scrub.timer = setTimeout(() => this._clear(), SETTLE_CAP_MS)
    scrub.observer = new MutationObserver(() => this._settle())
    scrub.observer.observe(scrub.bar, { attributes: true, attributeFilter: ["aria-valuenow"] })
  },

  // After a release, the server's position catching up with the target is
  // the moment to hand the thumb back.
  _settle() {
    const scrub = this._scrub
    if (!scrub || scrub.target === null) return
    const now = Number(scrub.bar.getAttribute("aria-valuenow"))
    if (Math.abs(now - scrub.target) <= 1) this._clear()
  },

  _detach(scrub) {
    scrub.bar.removeEventListener("pointermove", scrub.onMove)
    scrub.bar.removeEventListener("pointerup", scrub.onUp)
    scrub.bar.removeEventListener("pointercancel", scrub.onCancel)
  },

  _clear() {
    const scrub = this._scrub
    if (!scrub) return
    this._detach(scrub)
    if (scrub.timer) clearTimeout(scrub.timer)
    scrub.observer?.disconnect()
    scrub.state.removeAttribute("data-active")
    this._scrub = null
  },
}
