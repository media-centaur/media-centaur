// HoverPreview — push a preview event when the pointer enters the element.
//
//   <button phx-hook="HoverPreview" id="..."
//           phx-value-tmdb-id="..." phx-value-media-type="..." />
//
// LiveView has no phx-mouseover binding (a green render_focus test says
// nothing about hover), so pointer-driven spotlight previews need this
// hook. Keyboard/gamepad travel uses the real phx-focus binding on the
// same element; both roads push the same "omnibox_preview" event.
export const HoverPreview = {
  mounted() {
    this.el.addEventListener("mouseenter", () => {
      this.pushEvent("omnibox_preview", {
        "tmdb-id": this.el.getAttribute("phx-value-tmdb-id"),
        "media-type": this.el.getAttribute("phx-value-media-type"),
      })
    })
  },
}
