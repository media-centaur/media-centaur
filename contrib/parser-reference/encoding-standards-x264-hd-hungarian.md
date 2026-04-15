
# Hungarian HD x264 Release Rules and Standards

> Source: https://github.com/encoding-hun/rules-and-standards/blob/master/series-and-movies-x264-hd.md


Based on international scene standards, adapted for Hungarian context as of April 15, 2020.

---

## Section 1: General Rules

- Only `.mkv` container format is permitted
- MKVToolNix (mkvmerge) is the recommended muxer
- Header compression is forbidden
- All muxed tracks must be enabled
- Film trimming/cutting is prohibited
- Video compression (rar, zip) and splitting is forbidden
- SFV or MD5 checksums are recommended but optional
- Sample creation is optional (50-120 seconds, not from beginning/end, extracted without re-encoding)
- mHD, HDLight, and similar bitstarved encodes are strictly forbidden
- Chapterlist is mandatory if the source contains one
- Watermarks are forbidden

---

## Section 2: Tagging - Directory Names

- Accented characters are forbidden
- Allowed characters: `a-z` `A-Z` `0-9` `.` `-` `_` `+`
- Repeated separator characters are forbidden
- Reserved system names (CON, PRN, AUX, NUL, COM*, LPT*) cannot begin filenames when separated by a dot

### Naming Formats

Series:
```
[name].[season].[resolution].[source].[audio].[video].[language]-[group]
```

Films:
```
[title].[year].[resolution].[source].[audio].[video].[language]-[group]
```

- `[series.name]` and `[movie.title]` must be in original or English only
- WEB-DL and WEBRip sources must specify the exact platform (e.g., NF.WEB-DL)
- REPACK and RERiP tags are mandatory when fixing own releases
- Using iNT or iNTERNAL tags to avoid DUPEs is forbidden
- READ.NFO tag is mandatory for non-Retail/non-WEB sources
- PROPER/REPACK/RERiP and READ.NFO tags cannot be used together
- Maximum filename length is 255 characters (250 recommended)

### Platform Tags for WEB Sources

Common platform identifiers used in P2P/community releases:
- `NF` - Netflix
- `AMZN` - Amazon Prime Video
- `ATVP` - Apple TV+
- `DSNP` - Disney+
- `HMAX` / `MAX` - HBO Max / Max
- `HULU` - Hulu
- `PCOK` - Peacock
- `PMTP` - Paramount+
- `iT` - iTunes
- `CR` - Crunchyroll
- `STAN` - Stan
- `RED` - YouTube Red/Premium

Note: Platform tags are a P2P/community convention, NOT part of official scene standards. Scene WEB releases use only `WEB` or `WEBRip` without platform identifiers.

---

## Section 3: NFO

- NFO file is mandatory
- Language: English and/or Hungarian
- Required: title, creation date, original title, IMDb URL, duration, video source, encoder, resolution, bitrate, FPS, audio details, subtitle details
- Insulting other groups is forbidden
- PROPER/REPACK/RERiP releases must detail previous issues and include proof
- Only one NFO per release

---

## Section 4: Sources

Source priority (highest to lowest):
```
(UHD) BluRay > HDDVD/DTheater > higher-res WEBRip > WEB-DL > HDTV
```

- WEBRip recompression at lower resolution is forbidden
- UHD sources can only be used for SDR content
- HDR to SDR tonemapping is forbidden

---

## Section 5: Video

- Re-encoding lower-resolution releases from existing files is strictly forbidden
- Only one video track permitted
- 2D releases cannot use 3D film images except when no 2D version exists
- Multi-disc content with credits must be split into separate files
- Opening credits, intros, and credits must be preserved at full length
- Distracting cuts (ads, FBI warnings) should be removed when practical
- Burned-in subtitles should be avoided unless significantly better quality
- Hybrid encodes are permitted if they improve quality
- Container must not include extra resolution/crop metadata
- Language tag is optional (Hungarian or original language)

---

## Section 6: Resolution

- 720p maximum: 1280x720
- 1080p maximum: 1920x1080
- Resolution must be mod2
- Upscaling is strictly forbidden
- Upscaled sources can be re-encoded at original resolution or lower
- Different aspect ratios don't constitute DUPEs
- Black borders must be cropped to maximum 1px
- Dirty pixels/lines removal is forbidden
- 1px black borders (widow lines) can be removed at 1080p; mandatory removal at 720p

---

## Section 7: Filters

- Only progressive video is permitted (deinterlacing/IVTC required if necessary)
- Recommended resizers: z_Spline36Resize, Spline36ResizeMod, z_Spline64Resize, BlackmanResize
- Weak resizers (Nearest Neighbor, Bilinear, Bicubic) are forbidden
- Only frame-accurate source filters (FFMS2, LSMASH, DGDecNV, DGIndex) permitted
- Significant quality-affecting filters are forbidden except grain removal when necessary
- DeBlocking and DeBanding are permitted when zone-limited
- Original FPS must be maintained; interlaced content requires deinterlacing
- Constant framerate (CFR) mode is mandatory
- Duplicate frames must be removed

---

## Section 8: Video Encoding

- Only x264 is permitted
- Minimum x264 r3000 required
- Certain buggy x264 commits (r2969-r2979) are forbidden
- Accepted variants: vanilla, tMod, kMod, aMod, Patman
- Only 8-bit YUV420 (YV12) video permitted
- Only 2pass and CRF encoding allowed
- Segmented encoding is forbidden
- Level 4.1 for content under 1080p/30fps; Level 4.2 for higher
- High Profile required
- GPU encoding is strictly forbidden
- 1:1 pixel aspect ratio required
- ColorMatrix flagging mandatory if source provides it (typically BT.709)
- Maximum reference frames required for compatibility
- Minimum 5 B-frames required
- DXVA compatibility required
- CABAC mandatory
- 8x8dct mandatory
- Required partitions: i4x4, i8x8, p8x8, b8x8
- Motion estimation: umh, esa, or tesa only
- merange minimum 24
- subme minimum 8
- rc-lookahead minimum FPS*2
- Limited TV range (16-235) only
- VBV constraints: maxrate <=62500, bufsize <=78125, both >=50000
- Deblocking mandatory (recommended -3:-3 for films)
- Adaptive quantization mandatory (--aq-mode 1/2/3, mode 3 recommended)
- Release bitrate cannot exceed source
- Recommended frameservers: AviSynth+ and VapourSynth
- HDTV logo masking permitted
- Credits can be encoded at lower bitrate
- WEB-DL sources exempt from most section 8 rules except 8.8

---

## Section 9: Audio

- Hungarian audio requires HUN tag
- Audio language must be tagged
- Original language audio is mandatory
- Non-English original audio can optionally include English
- Other languages forbidden

### Permitted Audio Formats

| Format | Channels | Use |
|--------|----------|-----|
| AAC | 1.0 (mono) | Mono content |
| AAC / AC3 / E-AC3 | 2.0 (stereo) | Stereo content |
| AC3 / E-AC3 | 5.1 | Surround content |
| E-AC3 | 7.1 | 1080p only |

- Only studio-created surround; home-made surround forbidden
- Original channel count must be preserved
- Maximum audio delay: 100ms
- Audio commentary optional (AC3/AAC, max 2.0)
- Source audio must not be re-encoded if compatible format exists
- Audio track order: Hungarian, original, English, commentaries

---

## Section 10: Audio Encoding

- AC3/E-AC3: Dolby Certified encoder recommended (Dolby Encoding Engine, FFmpeg 4.1+)
- AAC: qaac, FDK, or Nero acceptable (stereo/mono only)
- Sampling rate must not be changed
- Bit depth and sampling rate must be preserved or improved
- Segmented encoding forbidden
- dialnorm values must be measured or sourced
- E-AC3 to AC3 conversion bitrate formula: 1.7x multiplier

---

## Section 11: Subtitles

- Only SRT (SubRip) and SSA/ASS formats permitted
- SSA/ASS requires accompanying SRT (except anime)
- SSA/ASS requires embedded fonts
- 3D encodes can use PGS/SUP format
- OCR must be as accurate as possible
- Subtitles must be embedded in mkv; SRT optionally external
- Mandatory subtitle tracks: Hungarian forced/full, original forced/full
- Retail subtitles mandatory if available
- Fansub can accompany Retail with track naming
- Machine translation (Google Translate) forbidden
- Maximum subtitle delay: 300ms
- Hardcoding forbidden
- Language tagging mandatory
- Forced flag and hearing-impaired flag recommended where applicable
