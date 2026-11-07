// ViewingTouch — a touch screen's way into the viewing layer (the phone
// running the TV app). A remote drives the OSD with keys; a finger has only
// taps, so on `#viewing-osd` a tap on the picture pushes `viewing_tap`
// (show the bar, or hide it while playing) and a tap on the seek bar pushes
// an absolute seek to the tapped point. A tap on a control (the prompt, the
// play/pause button, Audio & subtitles) is left to the control's own
// `phx-click`.

export function seekSeconds(clientX, rect, duration) {
  if (!(duration > 0) || !(rect.width > 0)) return null
  const share = Math.min(Math.max((clientX - rect.left) / rect.width, 0), 1)
  return Math.round(share * duration)
}

export function tapAction(target) {
  if (target.closest("[data-viewing-seek]")) return "seek"
  if (target.closest("button")) return null
  return "tap"
}

export const ViewingTouch = {
  mounted() {
    this._onClick = (event) => this._tap(event)
    this.el.addEventListener("click", this._onClick)
  },

  destroyed() {
    this.el.removeEventListener("click", this._onClick)
  },

  _tap(event) {
    const action = tapAction(event.target)
    if (action === "tap") this.pushEvent("viewing_tap", {})
    if (action !== "seek") return

    const bar = event.target.closest("[data-viewing-seek]")
    const seconds = seekSeconds(event.clientX, bar.getBoundingClientRect(), Number(bar.dataset.duration))
    if (seconds !== null) this.pushEvent("viewing_command", { command: "seek_to", seconds })
  },
}
