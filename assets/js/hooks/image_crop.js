// ImageCrop — the region a person picks on the picture they chose, at the
// master's fixed shape, before the app cuts the master: the profile
// avatar at 1:1, an app's banner at 460:215. Rendered by
// `Components.PictureField`.
//
// Expected shape (one per pending upload entry, `phx-update="ignore"` so
// croppr's DOM survives patches):
//   <div phx-hook="ImageCrop" id="image-crop-<ref>" data-aspect="1" phx-update="ignore">
//     <div class="image-crop-stage">        cancels the root zoom (app.css)
//       <img data-role="source" …>          the entry's live_img_preview
//     </div>
//     <input type="hidden" name="crop_x">   the box, written on every crop end
//     <input type="hidden" name="crop_y">
//     <input type="hidden" name="crop_width">
//     <input type="hidden" name="crop_height">
//     <canvas data-role="preview" width="48" height="48">   How it will look
//   </div>
//
// LiveView sets the img's src to an object URL once the entry is picked;
// on its `load` croppr wraps it with a draggable, resizable box locked to
// `data-aspect` (width / height), starting as the largest centred one —
// resizing the box is the scaling. The box is reported in the picture's
// own pixels (`returnMode: "real"`): the browser draws the picture turned
// the way up its orientation tag says and reports that size, and the
// server turns the pixels the same way before it cuts
// (`ImageFiles.webp_master/4`, `jpeg_master/3`). The img sits in
// `.image-crop-stage`, which cancels the root zoom (app.css): croppr mixes
// visual and layout px, and at effective zoom 1 they agree, so the box
// follows the pointer and `real` is the picture's pixels. Each preview
// canvas is painted with the box, filling its own size, so a preview
// carries the master's shape by its width and height attributes. No
// LiveView event: the fields ride the form's submit, and Cancel removes
// this element, which destroys croppr. The box has no keyboard path until
// the input system learns one.

import Croppr from "../../vendor/croppr"
import { cropFields } from "./image_crop_fields"
import { parseUiScale } from "../ui_scale"

const FIELDS = ["crop_x", "crop_y", "crop_width", "crop_height"]

export const ImageCrop = {
  mounted() {
    this.img = this.el.querySelector("img[data-role='source']")
    this.fields = Object.fromEntries(FIELDS.map((name) => [name, this.el.querySelector(`input[name='${name}']`)]))
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
    const picture = { width: source.naturalWidth, height: source.naturalHeight }
    const write = (box) => this._write(source, cropFields(box, picture))
    this._sizePreviews()
    this.cropper = new Croppr(this.img, {
      aspectRatio: 1 / Number(this.el.dataset.aspect || 1),
      startSize: [100, 100, "%"],
      returnMode: "real",
      onInitialize: (instance) => write(instance.getValue()),
      onCropEnd: write,
    })
  },

  // The previews' backing store: devicePixelRatio × --ui-scale pixels per
  // CSS px, as the strip chart sizes its plots, so a tile at 2× scale on a
  // HiDPI panel is drawn from as many pixels as it shows. The CSS size is
  // the frame's (`size-full`); the design size is the canvas attributes.
  _sizePreviews() {
    const scale = parseUiScale(getComputedStyle(document.documentElement).getPropertyValue("--ui-scale"))
    const density = (window.devicePixelRatio || 1) * scale
    for (const canvas of this.previews) {
      const width = Number(canvas.dataset.designWidth || canvas.getAttribute("width"))
      const height = Number(canvas.dataset.designHeight || canvas.getAttribute("height"))
      canvas.dataset.designWidth = String(width)
      canvas.dataset.designHeight = String(height)
      canvas.width = Math.round(width * density)
      canvas.height = Math.round(height * density)
    }
  },

  _write(source, fields) {
    for (const [name, value] of Object.entries(fields)) {
      if (this.fields[name]) this.fields[name].value = value
    }
    if (fields.crop_width === "") return
    const [x, y, width, height] = FIELDS.map((name) => Number(fields[name]))
    for (const canvas of this.previews) {
      const ctx = canvas.getContext("2d")
      ctx.clearRect(0, 0, canvas.width, canvas.height)
      ctx.drawImage(source, x, y, width, height, 0, 0, canvas.width, canvas.height)
    }
  },
}
