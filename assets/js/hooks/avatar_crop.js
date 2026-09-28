// AvatarCrop — the square a person picks on the picture they chose,
// before the app makes the avatar master (profiles phase 5b).
//
// Expected shape (the Picture field of the profile form, one per pending
// upload entry, `phx-update="ignore"` so croppr's DOM survives patches):
//   <div phx-hook="AvatarCrop" id="avatar-crop-<ref>" phx-update="ignore">
//     <div class="avatar-crop-stage">       cancels the root zoom (app.css)
//       <img data-role="source" …>          the entry's live_img_preview
//     </div>
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

import Croppr from "../../vendor/croppr"
import { cropFields } from "./avatar_crop_fields"
import { parseUiScale } from "../ui_scale"

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
    this._sizePreviews()
    this.cropper = new Croppr(this.img, {
      aspectRatio: 1,
      startSize: [100, 100, "%"],
      returnMode: "real",
      onInitialize: (instance) => write(instance.getValue()),
      onCropEnd: write,
    })
  },

  // The previews' backing store: devicePixelRatio × --ui-scale pixels per
  // CSS px, as the strip chart sizes its plots, so a tile at 2× scale on a
  // HiDPI panel is drawn from as many pixels as it shows. The CSS size is
  // the span's (`size-full`); the design size is the canvas attribute.
  _sizePreviews() {
    const scale = parseUiScale(getComputedStyle(document.documentElement).getPropertyValue("--ui-scale"))
    const density = (window.devicePixelRatio || 1) * scale
    for (const canvas of this.previews) {
      const design = Number(canvas.dataset.design || canvas.getAttribute("width"))
      canvas.dataset.design = String(design)
      canvas.width = Math.round(design * density)
      canvas.height = Math.round(design * density)
    }
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
