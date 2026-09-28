# Profiles, phase 5b: the crop. Implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When a person chooses a picture, they drag a square over it to pick what shows, see the tile as it will look, and Save cuts that square.

**Architecture:** The client picks, the server cuts. **croppr** (MIT, 5 KB gzipped, no dependencies; UMD, vendored unmodified as `assets/vendor/croppr.js`, its 900-byte stylesheet folded into `app.css`) draws a square box over the pending upload's `live_img_preview`. The `AvatarCrop` hook writes the box — `crop_x`, `crop_y`, `crop_side`, in the picture's own pixels with orientation applied — into three hidden fields of the profile form and draws the box onto two canvases wearing the own tile's avatar recipe (*How it will look*). On Save the form's params carry the box; `ImageFiles.square_webp/4` takes `crop: {x, y, side}`, autorotates, cuts, and makes the 256×256 master as before. A missing or malformed box, or one off the picture, is the centre crop the master has always been. No new column, no new event, no relay change.

**Tech Stack:** Phoenix LiveView 1.2 uploads (`live_img_preview`), a phx-hook, croppr 2.3.1, `image` 0.72 (libvips `autorot`, `extract_area`), ExUnit + LazyHTML, bun for the hook's pure helpers.

**Design:** `docs/superpowers/specs/2026-09-27-profiles-design.md` § Phase 5 → "The crop" and "The name field, and the card's two columns" (the Picture field is the crop's home). UIDR-047's 2026-09-28 amendment (rule 3). The owner's rule: an exceedingly minimal package for anything required (croppr over Cropper.js and a hand-rolled hook, decided 2026-09-28).

---

## Unify pass (2026-09-28)

**Core idea.** The avatar master is made in one place from one source and one square: `square_webp` owns the cut, whether the square is the centre (today) or the person's (now). The person's square is an input to that function, not a second path.

**Greenfield shape.** A crop is `{x, y, side}` in the picture's oriented pixels; the form carries it as three fields; the master function validates it against the picture it opened and falls back to the centre; the preview is the tile's own recipe over a canvas, never a second drawing of a person.

**Diff against the code, each incoherence decided:**

1. `square_webp/3` centre-crops inside `Image.thumbnail(…, crop: :center)`. With a person's square, the cut and the resize separate: autorotate → cut (the square, or the centred largest square) → thumbnail to 256. **Fixed now** in `square_webp/4`: one pipeline, the centre square computed by the same code path as a given one (`centre_square/1`), so there is one cut.
2. Orientation. Today's master ignores EXIF orientation: `Image.open` reads the stored pixels and `thumbnail` on an image struct does not rotate them, so a phone photo taken in portrait publishes sideways. The browser draws the preview oriented, and croppr's `real` coordinates are in that oriented frame. **Fixed now**: `square_webp/4` autorotates first, so the box and the pixels agree, and a photo publishes the way up the person saw it. This is a behaviour change for pictures without a box too; the spec's § Storage sentence "centre-cropped from the chosen file" stays true.
3. The preview must be the tile as it will look. A second "preview tile" component would be a second drawing of a person. **Use what exists**: a `<span>` with the tile's CSS classes (`identity-tile identity-tile-own identity-tile-avatar` and the size classes) and `IdentityTile.hue_style/1` for the pending hue, a `<canvas>` inside where the `<img>` would be. The recipe draws it; the hook only paints pixels.
4. The hook needs DOM croppr injects to survive LiveView patches: the wrapper is `phx-update="ignore"`, which is the idiom every hook that owns its subtree uses here (`StripChart`). The hidden fields live inside the wrapper; form serialization reads the DOM, so their values ride the submit without a change event. The wrapper is one per pending entry (`:for`), keyed by the entry's ref, so Cancel removes it and the hook is destroyed with it.
5. Where the box is parsed: the form's strings become integers in `SettingsLive` (`crop_from_params/1`), the bounds against the picture are checked in `ImageFiles` (it is the one that opened the picture). Two places, two different questions; not a duplication.

**Coherence cost.** Item 2 changes what an un-cropped upload publishes (upright instead of as stored). It is the correct behaviour and the tests pin it; the CHANGELOG names it.

## Read before starting

- **Never run `mix` directly.** Every command is `~/scripts/agents/agent-mix …`.
- **Test first**, red then green, per task. The suite stays green at every commit.
- Work on `main`, commit per task, push nothing.
- **Commit messages**: conventional, plain prose, the harness's attribution trailer, never `Co-Authored-By`.
- **Vendored JS** is imported into `app.js`/hooks from `assets/vendor/` (`import uPlot from "../../vendor/uplot"` in `strip_chart.js` is the precedent); the file is unmodified, MIT, with its licence header. croppr's `dist/croppr.js` is UMD; esbuild's CommonJS interop makes `import Croppr from "../../vendor/croppr"` the default export. `docs/strip-charts.md` records uPlot's vendoring in a table row; croppr gets the same row in `docs/social.md` (Task 3).
- **Hook tests** run under bun (`assets/js/hooks/*.test.js`, `bun test --dots assets/js/` in precommit). Bun has no DOM; test pure helpers, as `flash_auto_dismiss.test.js` does. Do not stub the DOM for croppr — it needs layout.
- **Images in tests** are made with `Image.new/3`, `Image.write/3`, and for the orientation case `Image.mutate/2` with `Vix.Vips.MutableImage.set(mut, "orientation", :gint, 6)`; no binary fixtures.
- **Copy** goes through the `writing-copy` skill; working strings are given.
- **The Picture field** (`social_section.ex`) is the crop's home: the tile row, then, while an entry is pending, the crop stage, the previews, then the entry line with Cancel.

## What this phase does not do, on purpose

- No zoom, no rotation controls (croppr is a box; the browser's oriented preview is the rotation).
- No client-side master; the server keeps the metadata strip and the cap.
- No crop for a stored avatar (choose the picture again).
- No keyboard path for the box (the input system's rollout; the moduledoc says so, as the slider's does).

## File structure

Created:

- `assets/vendor/croppr.js` — croppr 2.3.1 `dist/croppr.js`, unmodified.
- `assets/js/hooks/avatar_crop.js`, `assets/js/hooks/avatar_crop.test.js`.

Modified: `assets/css/app.css` (croppr's rules, recoloured to the theme, after the `.hue-slider` block), `assets/js/app.js` (the hook), `lib/media_centaur/image_files.ex` (`square_webp/4`), `lib/media_centaur_web/live/settings_live.ex` (`avatar_change/2`, `crop_from_params/1`), `lib/media_centaur_web/live/settings_live/social_section.ex` (the crop stage and previews), `test/media_centaur/image_files_test.exs`, `test/media_centaur_web/live/settings_live_social_test.exs`, `docs/social.md`, `docs/GLOSSARY.md`, the spec, wiki `Settings-Reference.md`, `campaigns/profiles.md`.

---

### Task 1: `square_webp/4` autorotates and cuts the given square

**Files:**
- Modify: `lib/media_centaur/image_files.ex` (`square_webp/3` → `/4`), `lib/media_centaur_web/live/settings_live.ex:~392` (the one caller, `crop: nil` for now)
- Test: `test/media_centaur/image_files_test.exs`

- [ ] **Step 1: Tests**

In `describe "square_webp/3"` (rename it `"square_webp/4"`), add a helper and three tests. The file already aliases `Vix.Vips.Operation` as `Operation` and uses `@moduletag :tmp_dir`.

```elixir
    # A 400×200 picture, red on the left half and blue on the right.
    defp halves(dir, name, opts \\ []) do
      {:ok, red} = Image.new(200, 200, color: :red)
      {:ok, blue} = Image.new(200, 200, color: :blue)
      {:ok, joined} = Operation.join(red, blue, :VIPS_DIRECTION_HORIZONTAL)

      {:ok, image} =
        case Keyword.get(opts, :orientation) do
          nil -> {:ok, joined}
          tag -> Image.mutate(joined, &Vix.Vips.MutableImage.set(&1, "orientation", :gint, tag))
        end

      path = Path.join(dir, name)
      {:ok, _} = Image.write(image, path)
      path
    end

    # The master's centre pixel as {r, g, b}.
    defp centre_rgb(bytes) do
      {:ok, master} = Image.from_binary(bytes)
      {:ok, [r, g, b | _]} = Image.get_pixel(master, 128, 128)
      {round(r), round(g), round(b)}
    end

    test "a given square is cut from the picture; the centre square when none", %{tmp_dir: dir} do
      source = halves(dir, "halves.png")

      {:ok, right} = ImageFiles.square_webp(source, 256, @cap, crop: {200, 0, 200})
      assert {0, 0, 255} = centre_rgb(right)

      {:ok, left} = ImageFiles.square_webp(source, 256, @cap, crop: {0, 0, 200})
      assert {255, 0, 0} = centre_rgb(left)

      # The centre square of a 400×200 straddles the seam: its centre column is the seam.
      {:ok, centre} = ImageFiles.square_webp(source, 256, @cap, crop: nil)
      {:ok, master} = Image.from_binary(centre)
      {:ok, [r, _g, _b | _]} = Image.get_pixel(master, 64, 128)
      {:ok, [_r, _g, b | _]} = Image.get_pixel(master, 192, 128)
      assert round(r) == 255 and round(b) == 255
    end

    test "a square off the picture, or degenerate, is the centre crop", %{tmp_dir: dir} do
      source = halves(dir, "halves.png")
      {:ok, centre} = ImageFiles.square_webp(source, 256, @cap, crop: nil)

      for bad <- [{300, 0, 200}, {0, 100, 200}, {-1, 0, 200}, {0, 0, 0}, {0, 0, 401}] do
        assert {:ok, ^centre} = ImageFiles.square_webp(source, 256, @cap, crop: bad),
               "#{inspect(bad)} must fall back to the centre"
      end
    end

    test "the picture is turned the way up its orientation says before the cut", %{tmp_dir: dir} do
      # Orientation 6 is a quarter turn clockwise: the 400×200 becomes 200×400
      # with red on top, blue below, which is how a browser shows it.
      source = halves(dir, "portrait.jpg", orientation: 6)

      {:ok, top} = ImageFiles.square_webp(source, 256, @cap, crop: {0, 0, 200})
      assert {255, 0, 0} = centre_rgb(top)

      {:ok, bottom} = ImageFiles.square_webp(source, 256, @cap, crop: {0, 200, 200})
      assert {0, 0, 255} = centre_rgb(bottom)

      {:ok, none} = ImageFiles.square_webp(source, 256, @cap, crop: nil)
      {:ok, master} = Image.from_binary(none)
      {:ok, [r, _g, _b | _]} = Image.get_pixel(master, 128, 64)
      {:ok, [_r, _g, b | _]} = Image.get_pixel(master, 128, 192)
      assert round(r) == 255 and round(b) == 255
    end
```

Update the three existing calls in this file to `square_webp(source, 256, @cap, crop: nil)`.

- [ ] **Step 2: Run, expect the arity to fail**

Run: `~/scripts/agents/agent-mix test test/media_centaur/image_files_test.exs`
Expected: FAIL, `square_webp/4` undefined.

- [ ] **Step 3: The function**

Replace `square_webp/3` in `lib/media_centaur/image_files.ex` with:

```elixir
  @typedoc "A square of the picture in its own oriented pixels: the left, the top, the side."
  @type crop :: {non_neg_integer(), non_neg_integer(), pos_integer()}

  @doc """
  A square WebP master of `side` pixels from the image file at `path`:
  the avatar a sender publishes. The picture is first turned the way up
  its orientation tag says (a phone photo's pixels are often stored
  sideways; a browser shows them turned, and a crop chosen on that
  preview is in the turned frame), then `crop:` — `{x, y, side}` in
  those pixels — is cut, or the largest centred square when the option
  is nil, off the picture or degenerate; the square is resized to
  `side`, flattened onto black and stripped of the source's metadata (a
  photo's EXIF carries its GPS position, device and time, and the
  master is published), and returned in memory at most `cap` long.
  Quality starts at 82 and steps down until the bytes fit;
  `{:error, :too_large}` when the lowest step does not. `{:error, reason}`
  when the file is not an image libvips can open. A truncated file with
  a sound header opens without error and yields a partly grey master,
  so the sender sees the result before publishing. `path` is a file the
  app wrote (an upload's temp file), never a user-typed name: libvips
  reads loader options after a `[` in it.
  """
  @spec square_webp(String.t(), pos_integer(), pos_integer(), crop: crop() | nil) ::
          {:ok, binary()} | {:error, :too_large | term()}
  def square_webp(path, side, cap, crop: crop)
      when is_binary(path) and is_integer(side) and side > 0 and is_integer(cap) and cap > 0 do
    with {:ok, image} <- Image.open(path),
         {:ok, {upright, _turn}} <- Image.autorotate(image),
         {x, y, square} = crop_square(upright, crop),
         {:ok, cut} <- Image.crop(upright, x, y, square, square),
         {:ok, resized} <- Image.thumbnail(cut, side),
         {:ok, flat} <- Image.flatten(resized) do
      webp_under(flat, cap, @webp_qualities)
    end
  end

  # The square to cut: the given one when it lies on the picture, else the
  # largest centred one.
  defp crop_square(image, {x, y, square})
       when is_integer(x) and is_integer(y) and is_integer(square) and x >= 0 and y >= 0 and
              square > 0 do
    if x + square <= Image.width(image) and y + square <= Image.height(image),
      do: {x, y, square},
      else: crop_square(image, nil)
  end

  defp crop_square(image, _none_or_bad) do
    width = Image.width(image)
    height = Image.height(image)
    square = min(width, height)
    {div(width - square, 2), div(height - square, 2), square}
  end
```

`lib/media_centaur_web/live/settings_live.ex`: `ImageFiles.square_webp(path, 256, ProfileTranslation.max_avatar_bytes(), crop: nil)` for now.

- [ ] **Step 4: Run, expect green**

Run: `~/scripts/agents/agent-mix test test/media_centaur/image_files_test.exs test/media_centaur/social/profile_test.exs test/media_centaur_web/live/settings_live_social_test.exs`
Expected: 0 failures. If `Image.get_pixel/3` returns a differently shaped list (bands), adjust the destructuring in the helper once; the master is RGB WebP, three bands.

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur/image_files.ex lib/media_centaur_web/live/settings_live.ex test/media_centaur/image_files_test.exs
git commit -m "feat: the avatar master turns the picture upright and cuts a given square, else the centre"
```

---

### Task 2: croppr vendored; the `AvatarCrop` hook; the crop stage and the previews

**Files:**
- Create: `assets/vendor/croppr.js`, `assets/js/hooks/avatar_crop.js`, `assets/js/hooks/avatar_crop.test.js`
- Modify: `assets/js/app.js` (import + `hooks:`), `assets/css/app.css` (after the `.hue-slider` rules), `lib/media_centaur_web/live/settings_live/social_section.ex` (the Picture field), `lib/media_centaur_web/live/settings_live.ex` (`save_profile` passes params; `avatar_change/2`; `crop_from_params/1`)
- Test: `test/media_centaur_web/live/settings_live_social_test.exs`

- [ ] **Step 1: The hook's pure helper test**

`assets/js/hooks/avatar_crop.test.js`:

```js
import { describe, expect, test } from "bun:test"
import { cropFields } from "./avatar_crop"

// croppr hands a box in the picture's pixels as floats; the form carries
// three integers, and a square is one side: the smaller of the two, so a
// rounding drift never pushes the box off the picture's edge.
describe("cropFields", () => {
  test("rounds the box to integers and takes the smaller side", () => {
    expect(cropFields({ x: 12.4, y: 7.6, width: 199.6, height: 200.2 })).toEqual({
      crop_x: "12",
      crop_y: "8",
      crop_side: "200",
    })
  })

  test("a box at the origin", () => {
    expect(cropFields({ x: 0, y: 0, width: 300, height: 300 })).toEqual({
      crop_x: "0",
      crop_y: "0",
      crop_side: "300",
    })
  })

  test("nothing sensible → empty fields, which the server reads as the centre", () => {
    expect(cropFields(null)).toEqual({ crop_x: "", crop_y: "", crop_side: "" })
    expect(cropFields({ x: 1, y: 1, width: 0, height: 0 })).toEqual({ crop_x: "", crop_y: "", crop_side: "" })
  })
})
```

- [ ] **Step 2: Run, expect the module missing**

Run: `cd assets && bun test --dots js/hooks/avatar_crop.test.js` (from the repo root: `bun test --dots assets/js/hooks/avatar_crop.test.js`).
Expected: FAIL, cannot resolve `./avatar_crop`.

- [ ] **Step 3: Vendor croppr**

```bash
curl -sL https://cdn.jsdelivr.net/npm/croppr@2.3.1/dist/croppr.js -o assets/vendor/croppr.js
head -5 assets/vendor/croppr.js   # the licence header names Croppr.js and MIT; keep it
```

If the file has no licence header, prepend one:

```js
/*! Croppr.js 2.3.1 — https://github.com/jamesssooi/Croppr.js — MIT License, James Ooi */
```

- [ ] **Step 4: The hook**

`assets/js/hooks/avatar_crop.js`:

```js
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
// (`ImageFiles.square_webp/4`). No LiveView event: the fields ride the
// form's submit, and Cancel removes this element, which destroys croppr.
// The box has no keyboard path until the input system learns one.

import Croppr from "../../vendor/croppr"

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
```

`assets/js/app.js`: `import {AvatarCrop} from "./hooks/avatar_crop"` beside the other hook imports, and `AvatarCrop,` in the `hooks:` map.

- [ ] **Step 5: Run the bun test, expect green**

Run: `bun test --dots assets/js/hooks/avatar_crop.test.js`
Expected: 3 pass. (Importing the module imports croppr, which touches no globals at import; if bun reports a `window` reference at import, wrap the `import Croppr` in the hook per `dom_stubs.js`'s note and say so in the report.)

- [ ] **Step 6: The CSS**

In `assets/css/app.css`, after the `.hue-slider::-webkit-slider-thumb` rule, croppr's stylesheet recoloured to the theme (its own is black-and-white on white):

```css
/* The crop box over a chosen picture (croppr 2.3.1, vendored; profiles
   phase 5b). Its stylesheet, recoloured: the dim over the picture, the
   square, the four handles. The stage is the Picture field's width. */
.avatar-crop { max-width: 18rem; }
.avatar-crop img[data-role="source"] { display: block; max-width: 100%; height: auto; border-radius: 8px; }
.croppr-container * { user-select: none; box-sizing: border-box; }
.croppr-container img { vertical-align: middle; max-width: 100%; }
.croppr { position: relative; display: inline-block; border-radius: 8px; overflow: hidden; }
.croppr-overlay { background: oklch(0% 0 0 / 0.55); position: absolute; inset: 0; z-index: 1; cursor: crosshair; }
.croppr-region { border: 1px solid oklch(from var(--color-base-content) l c h / 0.9); position: absolute; z-index: 3; cursor: move; top: 0; }
.croppr-imageClipped { position: absolute; inset: 0; z-index: 2; pointer-events: none; }
.croppr-handle { border: 1px solid oklch(0% 0 0 / 0.6); background: var(--color-base-content); width: 10px; height: 10px; border-radius: 2px; position: absolute; z-index: 4; top: 0; }
```

- [ ] **Step 7: The Settings tests**

In `describe "profile"` of `test/media_centaur_web/live/settings_live_social_test.exs`:

```elixir
    test "a chosen picture gets a crop stage with the box's fields and two previews; Cancel removes it",
         %{conn: conn} do
      Identity.ensure()
      {:ok, view, _html} = live_async!(conn, @section)
      {:ok, img} = Image.new(400, 300, color: :blue)
      {:ok, png} = Image.write(img, :memory, suffix: ".png")

      refute has_element?(view, "#profile-form [phx-hook='AvatarCrop']")

      upload = file_input(view, "#profile-form", :avatar, [%{name: "me.png", content: png, type: "image/png"}])
      render_upload(upload, "me.png")

      stage = "#profile-form [phx-hook='AvatarCrop'][phx-update='ignore']"
      assert has_element?(view, stage <> " img[data-role='source']")
      assert has_element?(view, stage <> " input[type='hidden'][name='crop_x']")
      assert has_element?(view, stage <> " input[type='hidden'][name='crop_y']")
      assert has_element?(view, stage <> " input[type='hidden'][name='crop_side']")
      assert has_element?(view, stage <> " canvas[data-role='preview'][width='48']")
      assert has_element?(view, stage <> " canvas[data-role='preview'][width='40']")
      assert has_element?(view, stage <> " .identity-tile.identity-tile-own.identity-tile-avatar")
      assert render(view) =~ "How it will look"

      view |> element("#profile-form button", "Cancel") |> render_click()
      refute has_element?(view, "#profile-form [phx-hook='AvatarCrop']")
    end

    test "Save cuts the square the fields name; without them, the centre", %{conn: conn} do
      Identity.ensure()
      {:ok, view, _html} = live_async!(conn, @section)
      {:ok, red} = Image.new(200, 200, color: :red)
      {:ok, blue} = Image.new(200, 200, color: :blue)
      {:ok, halves} = Vix.Vips.Operation.join(red, blue, :VIPS_DIRECTION_HORIZONTAL)
      {:ok, png} = Image.write(halves, :memory, suffix: ".png")

      upload = file_input(view, "#profile-form", :avatar, [%{name: "halves.png", content: png, type: "image/png"}])
      render_upload(upload, "halves.png")

      view
      |> form("#profile-form", %{"name" => "Sample Name", "crop_x" => "200", "crop_y" => "0", "crop_side" => "200"})
      |> render_submit()

      me = Identity.pubkey()
      {:ok, bytes} = AvatarStore.read(me, "image/webp")
      {:ok, master} = Image.from_binary(bytes)
      {:ok, [r, _g, b | _]} = Image.get_pixel(master, 128, 128)
      assert round(b) == 255 and round(r) == 0

      upload = file_input(view, "#profile-form", :avatar, [%{name: "halves.png", content: png, type: "image/png"}])
      render_upload(upload, "halves.png")
      view |> form("#profile-form", %{"name" => "Sample Name", "crop_x" => "", "crop_y" => "", "crop_side" => ""}) |> render_submit()
      {:ok, bytes} = AvatarStore.read(me, "image/webp")
      {:ok, master} = Image.from_binary(bytes)
      {:ok, [r, _g, _b | _]} = Image.get_pixel(master, 64, 128)
      {:ok, [_r, _g, b | _]} = Image.get_pixel(master, 192, 128)
      assert round(r) == 255 and round(b) == 255
    end
```

Note: `render_submit/2` merges the given params over the form's rendered inputs; the hidden fields exist in the DOM once the entry is pending, so both the given and the empty values are legitimate submissions.

- [ ] **Step 8: Run, expect failures**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/settings_live_social_test.exs`
Expected: FAIL — no `[phx-hook='AvatarCrop']`; the second test's master is the centre.

- [ ] **Step 9: The section**

In `social_section.ex`, alias `MediaCentaurWeb.Components.Discovery.IdentityTile` is already there; import nothing new. Replace the pending-entry paragraph (`<p :for={entry <- @uploads.avatar.entries} …>` … `</p>`) inside the Picture field with:

```heex
              <div :for={entry <- @uploads.avatar.entries} class="mt-3 space-y-3" data-role="pending-picture">
                <div
                  id={"avatar-crop-#{entry.ref}"}
                  phx-hook="AvatarCrop"
                  phx-update="ignore"
                  class="avatar-crop"
                >
                  <.live_img_preview entry={entry} data-role="source" alt="" />
                  <input type="hidden" name="crop_x" value="" />
                  <input type="hidden" name="crop_y" value="" />
                  <input type="hidden" name="crop_side" value="" />
                  <div class="mt-3 flex items-center gap-3">
                    <span
                      class="identity-tile identity-tile-own identity-tile-avatar relative grid size-12 shrink-0 place-items-center overflow-hidden rounded-full"
                      {IdentityTile.hue_style(@profile_hue)}
                      aria-hidden="true"
                    >
                      <canvas data-role="preview" width="48" height="48" class="size-full"></canvas>
                    </span>
                    <span
                      class="identity-tile identity-tile-own identity-tile-avatar relative grid size-10 shrink-0 place-items-center overflow-hidden rounded-full"
                      {IdentityTile.hue_style(@profile_hue)}
                      aria-hidden="true"
                    >
                      <canvas data-role="preview" width="40" height="40" class="size-full"></canvas>
                    </span>
                    <span class="text-xs text-base-content/60">How it will look</span>
                  </div>
                </div>
                <p class="flex items-center gap-2 text-xs text-base-content/60">
                  <span class="truncate">{entry.client_name}</span>
                  <span :for={err <- upload_errors(@uploads.avatar, entry)} class="text-error">
                    {upload_error_words(err, @uploads.avatar)}
                  </span>
                  <.button
                    type="button"
                    variant="dismiss"
                    size="xs"
                    phx-click="cancel_avatar"
                    phx-value-ref={entry.ref}
                    data-nav-item
                    tabindex="0"
                  >
                    Cancel
                  </.button>
                </p>
              </div>
```

The Picture field's description becomes "Shown in your circle. One JPEG, PNG or WebP; drag the square to choose what shows." Update the moduledoc: the Picture field carries the crop stage (`AvatarCrop`, croppr) while a file is chosen, and the two previews in the own tile's recipe; the fields ride the submit.

- [ ] **Step 10: The LiveView**

In `settings_live.ex`: `handle_event("save_profile", %{"name" => name} = params, socket)` and `{:ok, avatar} <- avatar_change(socket, crop_from_params(params))`; `avatar_change(socket, crop)` passes `crop: crop` to `square_webp/4`. Add beside it:

```elixir
  # The square the person dragged over the picture, as the form's three
  # fields; empty, missing or malformed is nil, the centre square.
  defp crop_from_params(params) do
    with {x, ""} <- Integer.parse(Map.get(params, "crop_x", "")),
         {y, ""} <- Integer.parse(Map.get(params, "crop_y", "")),
         {side, ""} <- Integer.parse(Map.get(params, "crop_side", "")) do
      {x, y, side}
    else
      _empty_or_bad -> nil
    end
  end
```

Update `avatar_change`'s comment: the chosen file becomes the master cut at the person's square, else the centre.

- [ ] **Step 11: Run, expect green; look at it**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/settings_live_social_test.exs test/media_centaur_web/page_smoke_test.exs && bun test --dots assets/js/`
Expected: 0 failures.

Then, in the running dev app at http://localhost:2160/settings?section=social, choose a picture (a real JPEG from a phone if one is at hand, for the orientation case) with `page-shot` unable to drive a file picker, use `chromium-probe` or a manual check: the crop stage shows the picture with the square, dragging moves it, the two previews follow, Save publishes the square. Report what was checked and how.

- [ ] **Step 12: Commit**

```bash
git add assets/vendor/croppr.js assets/js/hooks/avatar_crop.js assets/js/hooks/avatar_crop.test.js assets/js/app.js assets/css/app.css lib/media_centaur_web/live/settings_live.ex lib/media_centaur_web/live/settings_live/social_section.ex test/media_centaur_web/live/settings_live_social_test.exs
git commit -m "feat: drag a square over a chosen picture; the previews show the tile as it will look; Save cuts that square"
```

---

### Task 3: The whole suite, `precommit`, the boundaries

- [ ] `~/scripts/agents/agent-mix precommit` (this runs `mix boundaries`, the JS dependency-cruiser: the new vendor import must be reachable from `app.js`, which it is through the hook). Fix everything. Commit as `chore: precommit clean after the crop`.

---

### Task 4: Docs, wiki, glossary, campaign

- [ ] `docs/social.md`: the Settings paragraph gains the crop stage (`AvatarCrop` over `live_img_preview`, croppr vendored, the three fields, `square_webp/4` autorotating and cutting); a vendoring row like `docs/strip-charts.md`'s: `| Crop box | \`assets/vendor/croppr.js\` | croppr 2.3.1, MIT, UMD, unmodified |`.
- [ ] `docs/GLOSSARY.md` § Social: **Crop** and **Preview** rows from the spec's Phase 5 glossary, each naming the hook and `square_webp/4`.
- [ ] `docs/social-protocol.md` § Profile: the sentence "Media Centaur sends a 256×256 WebP, centre-cropped from the picture the person chose" becomes "…cut from the square the person chose on the picture (the centre square by default), turned the way up its orientation tag says".
- [ ] Wiki `Settings-Reference.md`, the Picture bullet: "press **Choose picture** … then drag the square over it to choose what shows; *How it will look* is your circle with that square. Save cuts it…". Wiki `Social.md` line 13 needs nothing.
- [ ] The spec: § The crop gains "as built" notes for any departure; § Storage's "centre-cropped" sentence gains "(or the person's square, phase 5b)".
- [ ] `campaigns/profiles.md`: Status (5b built, unreleased), Decisions (5b as built), ship notes for 5b (the crop, the orientation fix as a user-visible change: "a phone photo now publishes the way up you took it"), Next steps → the release and retirement. `campaigns/README.md` entry.
- [ ] Commit: `docs: the crop in the social guide, the protocol page, the glossary and the wiki; profiles phase 5b as built`.

---

## Self-review (2026-09-28)

**Spec coverage.** croppr vendored and its stylesheet folded in → Task 2; the hook on `live_img_preview` with the box in oriented pixels, the three fields, the previews in the own tile's recipe → Task 2; `square_webp/4` with `crop:`, autorotate, the centre fallback for a missing or bad box → Task 1; Cancel discarding the box → Task 2 (the element goes with the entry); the errors table's "Crop fields missing or off the image → centre crop" → Tasks 1 and 2; docs → Task 4. Not in scope: zoom, a crop for a stored avatar, a keyboard path.

**Type consistency.** `crop :: {x, y, side}` (Task 1) is what `crop_from_params/1` returns (Task 2). The hook's `cropFields/1` returns strings named exactly as the hidden inputs and the params (`crop_x`, `crop_y`, `crop_side`). `square_webp/4` is called with `crop: nil` (Task 1) then `crop: crop` (Task 2). The preview spans use `IdentityTile.hue_style/1`, public since phase 5a.
