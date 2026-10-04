# Manual App Banner

## Problem Statement

A manually added app shows only a monogram tile. The 2026-08-28 Apps
launcher design promised an optional artwork field for manual apps; it
was never built, and nothing in the app can put a banner on one.

## User-Facing Behavior

The Manual tab of Add app, and Edit for a manual app, gain a picture
field: **Choose image**, a crop box locked to the banner shape that can
be moved and resized (resizing is the scaling), a *How it will look*
preview, and **Remove** for a stored image. Save writes the banner; the
card shows it at once. Remove, then Save, returns the card to its
monogram. A Steam app's Edit has no picture field: its art follows the
store.

## Design

### Core idea

A person supplies a picture, picks the region that shows at a fixed
shape, and the app keeps a resized master of that region. The profile
avatar is this at 1:1; the app banner is this at 460:215.

### Shared parts (the avatar crop, generalised)

| Part | Before | After |
|---|---|---|
| Server cut | `ImageFiles.square_webp/4`, crop `{x, y, side}` | private `cut/3` (orient, cut a rect of the target shape, resize, flatten, strip metadata; largest centred rect when the crop is nil, off the picture or degenerate) under two encodings: `webp_master/4` (the avatar: quality stepped down under a byte cap) and `jpeg_master/3` (the banner) |
| Crop type | `{x, y, side}` | `{x, y, width, height}` |
| Form fields | `crop_x`, `crop_y`, `crop_side` | `crop_x`, `crop_y`, `crop_width`, `crop_height` |
| Hook | `AvatarCrop`, aspect 1 | `ImageCrop`, aspect from `data-aspect` |
| CSS | `.avatar-crop*` | `.image-crop*` |
| Markup | ~80 lines inline in `SocialSection` | `Components.PictureField.picture_field/1` with a story; `:current` and `:preview` slots carry each surface's own tile and preview frames |
| Param parsing, error words, upload options | private in `SettingsLive` / `SocialSection` | public on `PictureField` |

### Data Model Changes

None. The banner is `{data_dir}/images/apps/{id}/banner.jpg`, the file
the card already reads (disk is the ledger). Master size 920×430.

### Apps context

- `Apps.Artwork.store_bytes/3` writes a role's master and purges its
  derivatives; `Apps.Artwork.delete_role/2` removes one role.
- `Apps.change_banner/2` takes `:keep | :none | {:new, bytes}` (the
  avatar's change vocabulary) and broadcasts `ArtworkCached` so cards
  repaint. Manual apps only; a Steam app is refused.
- `refresh_steam_artwork/1` already matches Steam origins only; no change.

### Integration Points

None outside this repo. No spec change.

### Constraints

- Compose from the kit (CLAUDE.md): one picture field, not a second copy.
- UIDR-041: the Settings card keeps its stacked field.
- ADR-049: the cut runs inside the save event (synchronous, owned).
- The crop box has no keyboard or gamepad path, as for the avatar;
  managing apps assumes a pointer.

## Acceptance Criteria

- [ ] Adding a manual app with an image shows it on the card; without one, the monogram.
- [ ] Editing a manual app replaces or removes its image; removal returns the monogram.
- [ ] The crop box is locked to 460:215, moves and resizes; the master is that region at 920×430.
- [ ] The master is upright by its orientation tag and carries no EXIF.
- [ ] A wrong type or oversized file is a form error and saves nothing.
- [ ] A replaced image repaints at once (mtime-versioned URL).
- [ ] Removing an app removes its banner (unchanged).
- [ ] Steam apps' Edit shows no picture field.
- [ ] Profile picture choose / crop / save / remove behave as before.
- [ ] One `PictureField` component renders both surfaces; its story shows 1:1 and banner.
- [ ] No `crop_side`, `AvatarCrop`, `.avatar-crop` or `square_webp` remain.
- [ ] Wiki Apps page and glossary **Crop** / **Avatar** updated.

## Decisions

No decision record: this completes the 2026-08-28 Apps design's
artwork field, and the extraction is the compose-from-the-kit rule.

## Smoke Tests

- `image_files_test`: `webp_master/4` (the former square cases at 1:1)
  and `jpeg_master/3` (rect cut, centred fallback, orientation, EXIF).
- `apps/artwork_test`: `store_bytes/3`, `delete_role/2`.
- `apps_test`: `change_banner/2` for manual and Steam apps.
- `apps_live_test`: add with image, replace, remove, rejected type, Steam edit without field.
- `settings_live_social_test`: crop fields renamed.
- `image_crop_fields.test.js`: rect fields, clamped to the picture.
- Storybook: `picture_field` variations.
