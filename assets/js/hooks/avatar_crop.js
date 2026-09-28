// AvatarCrop — the square a person picks on the picture they chose,
// before the app makes the avatar master (profiles phase 5b).
//
// Expected shape (the Picture field of the profile form, one per pending
// upload entry, `phx-update="ignore"` so croppr's DOM survives patches):
//   <div phx-hook="AvatarCrop" id="avatar-crop-<ref>" phx-update="ignore">
//     <img data-role="source" …>            the entry's live_img_preview
//     <input type="hidden" name="crop_x">   the box, written on every crop end
//     <input type="hidden" name="crop_y">
//     <input type="hidden" name="crop_side">
//     <canvas data-role="preview" width="48" height="48">   How it will look
//     <canvas data-role="preview" width="40" height="40">
//   </div>
//
// LiveView sets the img's src to an object URL once the entry is picked;
// on its `load` croppr wraps it with a draggable, resizable square box,
// starting as the largest centred square. The box is reported in the
// picture's own pixels (`returnMode: "real"`): the browser draws the
// picture turned the way up its orientation tag says and reports that
// size, and the server turns the pixels the same way before it cuts
// (`ImageFiles.square_webp/4`). The img sits in `.avatar-crop-stage`,
// which cancels the root zoom (app.css): croppr mixes visual and layout
// px, and at effective zoom 1 they agree, so the box follows the pointer
// and `real` is the picture's pixels. No LiveView event: the fields ride
// the form's submit, and Cancel removes this element, which destroys
// croppr. The box has no keyboard path until the input system learns one.

// croppr polyfills requestAnimationFrame, CustomEvent and MouseEvent on
// `window` the moment its module body runs, unguarded. It is therefore
// required on first use, in the browser, not imported at the top: bun runs
// every hook test in one process with no `window`, and a top-level import
// would throw before `cropFields` could be tested. esbuild bundles the
// CommonJS file behind a lazy initialiser, so nothing runs until `_start`.
function loadCroppr() {
  return require("../../vendor/croppr")
}

// The three form fields for a croppr box: integers, and one side — the
// smaller, so rounding never pushes the box past the picture's edge.
// Anything without a positive size is empty, which the server reads as
// the centre square.
export function cropFields(box) {
  if (!box || !(box.width > 0) || !(box.height > 0)) {
    return { crop_x: "", crop_y: "", crop_side: "" }
  }
  const side = Math.round(Math.min(box.width, box.height))
  return {
    crop_x: String(Math.round(box.x)),
    crop_y: String(Math.round(box.y)),
    crop_side: String(side),
  }
}

export const AvatarCrop = {
  mounted() {
    this.img = this.el.querySelector("img[data-role='source']")
    this.fields = {
      crop_x: this.el.querySelector("input[name='crop_x']"),
      crop_y: this.el.querySelector("input[name='crop_y']"),
      crop_side: this.el.querySelector("input[name='crop_side']"),
    }
    this.previews = Array.from(this.el.querySelectorAll("canvas[data-role='preview']"))
    this._onLoad = () => this._start()
    if (this.img.complete && this.img.naturalWidth > 0) this._start()
    else this.img.addEventListener("load", this._onLoad, { once: true })
  },

  destroyed() {
    if (this.img && this._onLoad) this.img.removeEventListener("load", this._onLoad)
    if (this.cropper) this.cropper.destroy()
  },

  _start() {
    // The source for the previews is the same element croppr wraps; it
    // keeps its natural pixels, oriented as the browser shows them.
    const source = this.img
    const write = (box) => this._write(source, box)
    const Croppr = loadCroppr()
    this.cropper = new Croppr(this.img, {
      aspectRatio: 1,
      startSize: [100, 100, "%"],
      returnMode: "real",
      onInitialize: (instance) => write(instance.getValue()),
      onCropEnd: write,
    })
  },

  _write(source, box) {
    const fields = cropFields(box)
    for (const [name, value] of Object.entries(fields)) {
      if (this.fields[name]) this.fields[name].value = value
    }
    if (fields.crop_side === "") return
    const side = Number(fields.crop_side)
    for (const canvas of this.previews) {
      const ctx = canvas.getContext("2d")
      ctx.clearRect(0, 0, canvas.width, canvas.height)
      ctx.drawImage(source, Number(fields.crop_x), Number(fields.crop_y), side, side, 0, 0, canvas.width, canvas.height)
    }
  },
}
