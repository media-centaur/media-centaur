---
title: Video Release Filename Tags Reference
sources:
  - https://en.wikipedia.org/wiki/Pirated_movie_release_types
  - https://en.wikipedia.org/wiki/Standard_(warez)
  - https://scenerules.org/rules.html
  - https://ripped.guide/Scene/Scene-Glossary/
  - https://scenelingo.wordpress.com/
  - https://sites.google.com/site/aiodvdripping/understanding-scene-release-tags
  - https://torrentinvites.org/f96/guide-understanding-scene-release-tags-84278/
  - https://trash-guides.info/Radarr/Radarr-collection-of-custom-formats/
  - https://emby.media/support/articles/3D-Videos.html
  - https://en.wikipedia.org/wiki/DVD_region_code
  - https://en.wikipedia.org/wiki/High-dynamic-range_video
  - https://en.wikipedia.org/wiki/High_Efficiency_Video_Coding
  - https://en.wikipedia.org/wiki/Dolby_TrueHD
  - https://en.wikipedia.org/wiki/Dolby_Digital
  - https://beathau5com.wordpress.com/2016/07/29/scene-tags-information/
  - https://dimitris.tech/tutorials/453/
  - https://www.skidrowcodex.net/scene-tags/
  - https://badazzeasyguidestech.wordpress.com/2020/03/09/some-of-the-most-common-piracy-related-tv-movie-terms/
  - https://support.plex.tv/articles/multiple-editions/
  - https://jellyfin.org/docs/general/server/media/movies/
date_accessed: 2026-03-12
category: tag-reference
---

# Video Release Filename Tags Reference

Comprehensive reference for metadata tags found in video release filenames. Tags appear
dot-separated, hyphen-separated, or underscore-separated in release names. They are
case-insensitive by convention.

**Filename anatomy:**

```
Title.Year.Edition.Source.Resolution.VideoCodec.AudioCodec.HDR.ReleaseType-GROUP
```

Example:

```
Sample.Movie.1982.Final.Cut.Remastered.BluRay.2160p.HEVC.DTS-HD.MA.HDR10-GROUP
```

---

## 1. Release Type Tags

Tags indicating the release's status relative to other releases of the same content.

### PROPER

A replacement release from a **different** group, issued because an earlier release from
another group had quality or standards issues. The NFO typically explains what was wrong
with the original release.

Variations: `PROPER`, `REAL.PROPER`

### REPACK

A replacement release from the **same** group that originally released it. Issued to fix
a problem discovered after the initial release (bad encode, wrong audio, sync issues).

Variations: `REPACK`, `REPACK2` (second fix attempt)

### RERIP

The source material was re-ripped from the original disc or media. Similar to REPACK but
emphasizes that the source capture was redone, not just the encode.

Variations: `RERIP`, `RERiP`

### REAL

Used when a previous release was tagged PROPER but was itself flawed or illegitimate.
The REAL tag asserts that this release is the genuinely corrected version. Often combined
as `REAL.PROPER`.

### INTERNAL

The release was intended for internal use within the releasing group's topsites, not for
wide distribution. Often used to avoid dupe rules (when another group already released
the same content). Internal releases may have lower standards or be niche content.

Variations: `iNTERNAL`, `INTERNAL`, `INT`

### READNFO

Directs attention to the NFO file, which contains important information about the
release. Often used alongside PROPER or REPACK to explain why the re-release was
necessary, or to note something unusual about the content.

Variations: `READNFO`, `READ.NFO`, `READNFo`

### NUKED

A release that has been marked as invalid by nukers (scene quality-control). Reasons
include: rule violations, bad quality, wrong labeling, incomplete content, or being a
duplicate. Nuked releases should be avoided. A nuke reason is typically provided (e.g.,
`NUKED_bad.ivtc`, `NUKED_dupe`).

Variations: `NUKED`, `UNNUKED` (nuke was reversed)

### NFOFIX

A re-release that only corrects errors in the NFO file. The media content is identical.

### SAMPLEFIX

A re-release that provides a corrected sample file. The main media content is unchanged.

### DIRFIX

A re-release that corrects errors in the release directory name (e.g., wrong year,
misspelled title, incorrect tags). The media content is identical.

Variations: `DIRFIX`, `DiRFiX`

### SUBFIX

A re-release that provides corrected subtitle files. The video and audio are unchanged.
Note: Some scene rule sets do not allow SUBFIX as a valid fix type.

### SYNCFIX

A re-release that corrects audio/video synchronization issues. The content is
re-muxed with corrected timing.

### PROOFFIX

A re-release providing corrected proof (screenshot/sample proving authenticity).

---

## 2. Edition and Cut Tags

Tags indicating which version or cut of the content is included.

### REMASTERED

The content has been digitally remastered from the original source material, typically
with improved color grading, resolution, or audio. Common for classic films given
modern transfers.

Variations: `REMASTERED`, `Remastered`, `RESTORED`

### EXTENDED

An extended version with additional scenes not in the theatrical release. Runtime is
longer than the theatrical cut.

Variations: `EXTENDED`, `EXTENDED.CUT`, `EXTENDED.EDITION`, `Extended.Cut`

### UNCUT

A version with no content removed by censors or editors. May contain violence, nudity, or
other material cut from other releases for ratings purposes.

### UNRATED

Released without an official rating board classification. Often contains material that
would have resulted in a restrictive rating. Common for horror and comedy films.

Variations: `UNRATED`, `UNRATED.CUT`

### DIRECTORS.CUT

The director's preferred version of the film, which may differ significantly from the
theatrical release. May be longer or shorter, with different scenes, pacing, or endings.

Variations: `DIRECTORS.CUT`, `Directors.Cut`, `DC` (abbreviation, less common)

### THEATRICAL

The version shown in cinemas. Used to distinguish from director's cuts, extended
editions, or other alternate versions.

Variations: `THEATRICAL`, `THEATRICAL.CUT`, `Theatrical.Cut`

### CRITERION

Released by The Criterion Collection, known for high-quality transfers and extensive
supplemental material. Often indicates a premium master.

Variations: `CRITERION`, `Criterion`, `CC` (abbreviation)

### SPECIAL.EDITION

A release with special features, bonus content, or enhanced presentation. May include
alternate cuts, commentary tracks, or documentaries.

Variations: `SPECIAL.EDITION`, `SE`, `Special.Edition`

### COLLECTORS.EDITION

A premium release aimed at collectors, often with exclusive packaging or bonus material
in the physical release. The video content may be identical to other editions.

Variations: `COLLECTORS.EDITION`, `CE`, `Collectors.Edition`

### ANNIVERSARY.EDITION

A commemorative release for a film's milestone anniversary (10th, 25th, 50th, etc.).
Often includes a new transfer and bonus material.

Variations: `ANNIVERSARY.EDITION`, `25TH.ANNIVERSARY.EDITION`, `10TH.ANNIVERSARY`

### IMAX

Content mastered for or captured in the IMAX format. May have a different aspect ratio
(taller frame, often 1.43:1 or 1.90:1) compared to the standard widescreen release.

Variations: `IMAX`, `IMAX.EDITION`

### OPEN.MATTE

The full-frame version of a film originally shot in a wider aspect ratio but with
additional vertical image area visible. Shows more picture at the top and bottom but
may also reveal equipment or set edges. Aspect ratio is typically 16:9 or 4:3 instead
of the intended 2.39:1 or 2.35:1.

Variations: `OPEN.MATTE`, `OPEN.MATTE.EDITION`, `OM`

### FINAL.CUT

The definitive version of a film as determined by the director or studio. Most famously
associated with Sample Movie.

Variations: `FINAL.CUT`, `Final.Cut`

### ULTIMATE.CUT

A comprehensive version, often the longest available cut. Used for films with multiple
existing versions.

Variations: `ULTIMATE.CUT`, `ULTIMATE.EDITION`

### REDUX

A re-edited version of a film, sometimes significantly restructured. Most famously
associated with Apocalypse Now Redux.

Variations: `REDUX`

### SUPERBIT

A DVD release format that maximizes video and audio bitrate by omitting extras.
Largely obsolete in the Blu-ray era.

### DESPECIALIZED

Fan-made restorations of films to their original theatrical versions, removing later
alterations. Most commonly associated with the original Star Wars trilogy.

Variations: `DESPECIALIZED`, `Despecialized`

### CHRONOLOGICAL.CUT

A fan edit restructuring the film or series in chronological order.

### WORKPRINT

An early, unfinished version of the film. Usually leaked rather than officially released.
May have incomplete effects, temp music, or different editing.

Variations: `WORKPRINT`, `WP`

---

## 3. Source Tags

Tags indicating the original source media from which the release was created, ordered
roughly from highest to lowest quality.

### REMUX

A lossless copy of the video and audio streams from a disc, re-muxed into a container
(usually MKV) without any re-encoding. Preserves full original quality. Files are large
(typically 20-60 GB for a Blu-ray film).

Variations: `REMUX`, `Remux`, `BDRemux`

### BluRay / BDRip

**BluRay**: Encoded from a Blu-ray disc source. May indicate a full encode or remux
depending on context.

**BDRip**: Encoded (compressed) directly from a Blu-ray disc. Resolution is typically
1080p or 720p. Uses x264 or x265 codec in MKV container.

Variations: `BluRay`, `Bluray`, `BLURAY`, `BDRip`, `BDRiP`, `BD`

### BRRip

A re-encode of an existing BDRip. Lower quality than a direct BDRip because it is a
transcode of a transcode.

Variations: `BRRip`, `BRRiP`

### UHD.BluRay

Source is a 4K Ultra HD Blu-ray disc. Contains 2160p video, often with HDR metadata.

Variations: `UHD.BluRay`, `UHDBluRay`, `UHD`, `COMPLETE.UHD.BLURAY`

### WEB-DL

Losslessly captured from a streaming service (Netflix, Amazon, Disney+, Apple TV+,
Hulu, HBO Max, etc.) or downloaded from a digital distribution platform (iTunes, Vudu).
Not re-encoded. Quality depends on the streaming service's source bitrate.

Variations: `WEB-DL`, `WEBDL`, `WEB.DL`, `AMZN.WEB-DL`, `NF.WEB-DL`, `DSNP.WEB-DL`

Common service prefixes: `AMZN` (Amazon), `NF` (Netflix), `DSNP` (Disney+), `ATVP`
(Apple TV+), `HMAX` (HBO Max), `HULU`, `PCOK` (Peacock), `PMTP` (Paramount+),
`iT` (iTunes), `CRAV` (Crave)

### WEBRip

Screen-captured or recorded from a streaming service using capture software. Quality is
typically slightly lower than WEB-DL due to the capture process. May show re-encoding
artifacts.

Variations: `WEBRip`, `WEB.Rip`, `WEBRIP`, `WEB`

### HDRip

Transcoded from an HD source (HDTV, WEB-DL, or Blu-ray). A general-purpose tag for
HD-sourced encodes.

Variations: `HDRip`, `HDRiP`

### HDTV

Captured from a high-definition television broadcast. Quality varies by broadcaster
and capture method.

Variations: `HDTV`, `PDTV` (Pure Digital TV)

### DVDRip

Encoded from a DVD source. Resolution is typically 480p (NTSC) or 576p (PAL).

Variations: `DVDRip`, `DVDRiP`, `DVDR`

### SDTV

Captured from a standard-definition television broadcast.

Variations: `SDTV`, `DSR` (Digital Satellite Rip), `SATRip`

### R5

A release from a Region 5 (Russia/Eastern Europe) DVD, typically released early to
combat piracy. Quality is variable; video may be a telecine with DVD-quality audio.

Variations: `R5`, `R5.LINE`, `R5.AC3`

### TELECINE (TC)

A copy created by running film through a telecine machine, converting directly from the
film print. Better than a CAM but below DVD quality.

Variations: `TC`, `TELECINE`, `HDTelecine`

### TELESYNC (TS)

A camera recording from a cinema, sometimes with improved audio captured from a direct
source (e.g., headphone jack, FM broadcast). Better audio than a CAM.

Variations: `TS`, `TELESYNC`, `HDTS`, `PDVD`, `PreDVDRip`

### CAM

Recorded directly from a cinema screen using a camera. Lowest quality. Audio is captured
via the camera's microphone. May include audience noise, uneven framing, and theater
artifacts.

Variations: `CAM`, `HDCAM`, `CAMRip`

### SCR / SCREENER

A promotional release sent to critics, awards voters, or industry professionals.
Quality can be DVD or Blu-ray level but may include watermarks, countdown timers, or
black-and-white segments.

Variations: `SCR`, `SCREENER`, `DVDSCR`, `DVDScreener`, `BDSCR`

### VODRip

Ripped from a Video On Demand service. Similar to WEB-DL but from a VOD platform.

Variations: `VODRip`, `VODRiP`

---

## 4. Resolution Tags

Tags indicating the video resolution.

| Tag | Resolution | Common Name |
|-----|-----------|-------------|
| `2160p` | 3840x2160 | 4K / Ultra HD |
| `1080p` | 1920x1080 | Full HD |
| `1080i` | 1920x1080 interlaced | Full HD Interlaced |
| `720p` | 1280x720 | HD |
| `576p` | 720/1024x576 | PAL SD (Enhanced) |
| `480p` | 720x480 | NTSC SD |
| `480i` | 720x480 interlaced | NTSC SD Interlaced |
| `4320p` | 7680x4320 | 8K |

The `p` suffix means progressive scan; `i` means interlaced.

Variations: `4K`, `UHD` are sometimes used instead of `2160p`. `SD` may be used instead
of specific 480p/576p tags.

---

## 5. Video Codec Tags

Tags indicating the video compression codec or encoder used.

### x264

Open-source software encoder for H.264/AVC. The most common encoder tag in releases.
Indicates the content was encoded using the x264 encoder.

Variations: `x264`, `X264`, `H264`, `H.264`, `AVC`

### x265

Open-source software encoder for H.265/HEVC. Produces smaller files than x264 at
comparable quality (25-50% better compression). Requires more CPU to decode.

Variations: `x265`, `X265`, `H265`, `H.265`, `HEVC`

### AV1

Royalty-free codec developed by the Alliance for Open Media. Up to 50% better
compression than H.264. Growing adoption on streaming platforms.

Variations: `AV1`

### XviD

Open-source MPEG-4 Part 2 codec. Common in older DVD-era releases. Largely obsolete
for new releases.

Variations: `XviD`, `XVID`, `Xvid`

### DivX

Proprietary MPEG-4 Part 2 codec. Predecessor to XviD. Very rarely seen in modern
releases.

Variations: `DivX`, `DIVX`, `DiVX`

### MPEG2

MPEG-2 video codec. Used on DVDs and some HDTV broadcasts. Seen in REMUX or
transport stream captures.

Variations: `MPEG2`, `MPEG-2`, `mpeg2video`

### VC-1

Microsoft's video codec, sometimes found on Blu-ray discs (especially older ones).

Variations: `VC-1`, `VC1`, `WMV`

---

## 6. Audio Codec and Format Tags

Tags indicating the audio codec, channel layout, or special audio features.

### Lossless Audio

| Tag | Meaning |
|-----|---------|
| `TrueHD` | Dolby TrueHD - lossless codec used on Blu-ray |
| `TrueHD.Atmos` | Dolby TrueHD with Atmos object-based spatial audio metadata |
| `DTS-HD.MA` | DTS-HD Master Audio - lossless, competing with TrueHD |
| `DTS-HD.HR` | DTS-HD High Resolution - lossy but higher quality than standard DTS |
| `FLAC` | Free Lossless Audio Codec - open-source lossless |
| `PCM` | Uncompressed pulse-code modulation audio |
| `LPCM` | Linear PCM - uncompressed audio found on Blu-rays |

Variations: `DTS-HD.MA` may appear as `DTS-HDMA`, `DTSHD.MA`, `DTS-HD`

### Lossy Audio

| Tag | Meaning |
|-----|---------|
| `DTS` | DTS Digital Surround - standard lossy DTS |
| `DTS-ES` | DTS Extended Surround - 6.1 channel DTS |
| `DTS:X` | DTS object-based spatial audio (DTS equivalent of Atmos) |
| `AC3` | Dolby Digital (AC-3) - standard lossy surround codec |
| `EAC3` | Enhanced AC-3 / Dolby Digital Plus |
| `DD5.1` | Dolby Digital 5.1 surround |
| `DD2.0` | Dolby Digital 2.0 stereo |
| `DDP5.1` | Dolby Digital Plus 5.1 |
| `DDP.Atmos` | Dolby Digital Plus with Atmos (streaming Atmos format) |
| `AAC` | Advanced Audio Coding - common in streaming/web sources |
| `AAC2.0` | AAC stereo |
| `AAC5.1` | AAC 5.1 surround |
| `MP3` | MPEG-1 Audio Layer III - rarely used in modern releases |
| `OGG` / `Vorbis` | Open-source lossy codec, uncommon |
| `Opus` | Modern open-source lossy codec |

### Channel Layout Tags

| Tag | Meaning |
|-----|---------|
| `2.0` | Stereo (2 channels) |
| `5.1` | 5.1 surround (6 channels) |
| `6.1` | 6.1 surround (7 channels) |
| `7.1` | 7.1 surround (8 channels) |
| `7.1.4` | 7.1.4 Atmos layout (12 channels) |
| `Atmos` | Dolby Atmos object-based spatial audio |
| `Mono` | Single channel audio |

---

## 7. HDR Tags

Tags indicating high dynamic range video formats.

### HDR10

The baseline open HDR standard. Uses static metadata (one set of tone-mapping
parameters for the entire film). Most widely supported HDR format.

Variations: `HDR10`, `HDR`

### HDR10+

HDR10 with dynamic metadata developed by Samsung. Adjusts tone mapping scene-by-scene
or frame-by-frame. Less widely adopted than Dolby Vision.

Variations: `HDR10Plus`, `HDR10+`, `HDR10P`

### Dolby Vision (DV)

Dolby's proprietary HDR format with dynamic metadata. Supports 12-bit color depth.
Often includes HDR10 as a backward-compatible base layer.

Variations: `DV`, `DoVi`, `Dolby.Vision`, `DV.HDR10` (dual-layer with HDR10 fallback)

### HLG

Hybrid Log-Gamma. A royalty-free HDR format that does not use metadata. Designed for
broadcast compatibility (displays correctly on both SDR and HDR screens).

Variations: `HLG`

### SDR

Standard Dynamic Range. Explicitly tagged only when needed to distinguish from an HDR
version of the same content.

### Combined HDR Tags

Releases may combine multiple HDR formats: `DV.HDR10`, `DV.HDR10+`, indicating the
file contains both Dolby Vision metadata and HDR10/HDR10+ fallback.

---

## 8. Container Format Tags

Tags indicating the file container format (not the codec).

| Tag | Format | Notes |
|-----|--------|-------|
| `MKV` | Matroska | Most common for scene/P2P releases. Supports all codecs, multiple audio/subtitle tracks |
| `MP4` | MPEG-4 Part 14 | Common for web sources and iTunes downloads. Widely compatible |
| `AVI` | Audio Video Interleave | Legacy format. Common in XviD/DivX era. Limited codec support |
| `WMV` | Windows Media Video | Microsoft format. Rare in modern releases |
| `FLV` | Flash Video | Largely obsolete |
| `TS` | MPEG Transport Stream | Used for broadcast captures and some raw WEB captures |
| `M2TS` | Blu-ray Transport Stream | Native Blu-ray container format |
| `VOB` | DVD Video Object | Native DVD container format |
| `ISO` | Disc Image | Complete disc image including menus and extras |
| `BDMV` | Blu-ray Disc folder | Complete Blu-ray directory structure (not a single file) |
| `WebM` | WebM | Google's open container, typically VP9/AV1 + Opus/Vorbis |

---

## 9. 3D Tags

Tags indicating stereoscopic 3D content and format. A `3D` tag is typically present
alongside the specific format tag.

### SBS / HSBS / FSBS

Side-by-Side format. The left-eye and right-eye views are placed next to each other
horizontally.

| Tag | Meaning |
|-----|---------|
| `SBS` | Side-by-Side (may be half or full, context-dependent) |
| `HSBS` | Half Side-by-Side - each eye's image is half-width (most common) |
| `H-SBS` | Half Side-by-Side (alternate notation) |
| `FSBS` | Full Side-by-Side - each eye's image is full-width (double total width) |
| `F-SBS` | Full Side-by-Side (alternate notation) |

### OU / HOU / TAB

Over-Under (Top-and-Bottom) format. The left-eye and right-eye views are stacked
vertically.

| Tag | Meaning |
|-----|---------|
| `OU` | Over-Under (may be half or full) |
| `HOU` | Half Over-Under - each eye's image is half-height (most common) |
| `H-OU` | Half Over-Under (alternate notation) |
| `FOU` | Full Over-Under - each eye's image is full-height |
| `TAB` | Top-and-Bottom (synonym for OU) |
| `HTAB` | Half Top-and-Bottom |
| `FTAB` | Full Top-and-Bottom |

### MVC

Multi-view Video Coding. The native 3D Blu-ray codec that stores both eye views
efficiently with inter-view prediction. Higher quality than SBS/OU but requires
MVC-capable player.

Variations: `MVC`, `3D.MVC`

### Other 3D Tags

| Tag | Meaning |
|-----|---------|
| `3D` | General 3D indicator, usually combined with a format tag |
| `ANAGLYPH` | Red/cyan anaglyph encoding (low quality, legacy) |
| `2D` | Explicitly 2D, to distinguish from a 3D version |

---

## 10. Language Tags

Tags indicating the audio language(s) included in the release.

### Multi-Language Tags

| Tag | Meaning |
|-----|---------|
| `MULTi` | Multiple language audio tracks included (usually 2+) |
| `DUAL` | Two language audio tracks (typically original + one dub) |
| `DUAL.AUDIO` | Explicit dual audio indicator |
| `TRiLiNGUAL` | Three language audio tracks |

### Dubbing Tags

| Tag | Meaning |
|-----|---------|
| `DUBBED` | Contains a dubbed audio track (foreign language dub) |
| `MiC.DUBBED` | Dubbed using a microphone recording (low quality dub) |
| `LINE.DUBBED` | Dubbed using a line-in audio source |
| `FAN.DUB` | Fan-made dubbing |

### Specific Language Tags

Common language tags that appear in filenames:

| Tag | Language |
|-----|----------|
| `ENGLiSH` / `ENG` | English |
| `FRENCH` / `FRE` | French |
| `GERMAN` / `GER` | German |
| `SPANiSH` / `SPA` | Spanish |
| `iTALiAN` / `ITA` | Italian |
| `JAPANESE` / `JPN` | Japanese |
| `KOREAN` / `KOR` | Korean |
| `CHiNESE` / `CHI` | Chinese |
| `PORTUGUESE` / `POR` | Portuguese |
| `RUSSiAN` / `RUS` | Russian |
| `DUTCH` / `DUT` | Dutch |
| `SWEDiSH` / `SWE` | Swedish |
| `NORWEGiAN` / `NOR` | Norwegian |
| `DANiSH` / `DAN` | Danish |
| `FiNNiSH` / `FIN` | Finnish |
| `POLISH` / `POL` | Polish |
| `CZECH` / `CZE` | Czech |
| `HiNDi` / `HIN` | Hindi |
| `ARABiC` / `ARA` | Arabic |
| `TURKISH` / `TUR` | Turkish |
| `THAI` / `THA` | Thai |
| `GREEK` / `GRE` | Greek |
| `HEBREW` / `HEB` | Hebrew |
| `HUNGARIAN` / `HUN` | Hungarian |
| `ROMANIAN` / `RUM` | Romanian |
| `BULGARIAN` / `BUL` | Bulgarian |
| `CROATiAN` / `HRV` | Croatian |
| `UKRAINIAN` / `UKR` | Ukrainian |
| `VIETNAMese` / `VIE` | Vietnamese |
| `INDONESIAN` / `IND` | Indonesian |
| `MALAY` / `MAY` | Malay |
| `TAGALOg` / `TGL` | Tagalog |
| `TAMIL` / `TAM` | Tamil |
| `TELUGU` / `TEL` | Telugu |
| `BENGALI` / `BEN` | Bengali |

### French-Specific Language Tags

The French scene has its own detailed language conventions:

| Tag | Meaning |
|-----|---------|
| `VFF` | Version Francaise France (French dub from France) |
| `VFQ` | Version Francaise Quebec (French-Canadian dub) |
| `VF` | Version Francaise (generic French dub) |
| `VF2` | Second French audio track variant |
| `VOSTFR` | Version Originale Sous-Titree Francais (original audio, French subs) |
| `TRUEFRENCH` | High-quality French dub considered definitive |
| `MULTI.VFF` | Multi-language with VFF French track |
| `MULTI.VFQ` | Multi-language with VFQ French track |

---

## 11. Subtitle Tags

Tags indicating subtitle presence, type, and language.

### Subtitle Type Tags

| Tag | Meaning |
|-----|---------|
| `SUBBED` | Subtitles are present (may be hardcoded or soft) |
| `HARDSUB` | Subtitles are burned into the video (cannot be disabled) |
| `HARDCODED` | Same as HARDSUB |
| `SOFTSUB` | Subtitles are a separate track (can be toggled on/off) |
| `SUBS` | Subtitles included (general) |
| `MULTISUBS` | Multiple subtitle language tracks included |
| `FORCED` | Contains forced subtitles (for foreign-language dialogue only) |

### Subtitle Language Convention

Subtitle languages often appear as:
- `ENGSUB` / `ENG.SUBS` - English subtitles
- `KORSUB` - Korean subtitles (often hardcoded in Korean releases)
- `CUSTOM.SUBS` - Custom/fan-made subtitles
- `RETAIL.SUBS` - Official retail subtitles

### SRT and Subtitle Formats

External subtitle files may accompany releases:
- `.srt` - SubRip (most common)
- `.ass` / `.ssa` - Advanced SubStation Alpha
- `.sub` / `.idx` - VobSub (bitmap subtitles from DVDs)
- `.sup` - PGS (Presentation Graphic Stream, Blu-ray bitmap subtitles)

---

## 12. Region Tags

DVD and Blu-ray region codes indicating geographic distribution rights.

### DVD Regions

| Tag | Region |
|-----|--------|
| `R0` / `REGION.0` | Region-free (plays in all regions) |
| `R1` / `REGION.1` | USA, Canada, US Territories |
| `R2` / `REGION.2` | Europe, Japan, Middle East, Egypt, South Africa, Greenland |
| `R3` / `REGION.3` | Taiwan, Korea, Philippines, Indonesia, Hong Kong |
| `R4` / `REGION.4` | Mexico, Central/South America, Australia, New Zealand, Pacific Islands |
| `R5` / `REGION.5` | Russia, Eastern Europe, India, Africa (excl. South Africa), Mongolia |
| `R6` / `REGION.6` | China |
| `R7` / `REGION.7` | Reserved for future use |
| `R8` / `REGION.8` | International venues (aircraft, cruise ships) |

### Blu-ray Regions

| Tag | Region |
|-----|--------|
| `REGION.A` | Americas, East Asia (except China), Southeast Asia |
| `REGION.B` | Europe, Africa, Middle East, Australia, New Zealand |
| `REGION.C` | Central Asia, China, Russia, South Asia |

### NTSC and PAL

| Tag | Meaning |
|-----|---------|
| `NTSC` | North American/Japanese TV standard (29.97 fps, 480 lines) |
| `PAL` | European TV standard (25 fps, 576 lines) |

---

## 13. Distribution Tags

Tags indicating how the content was originally distributed or released.

### LIMITED

The film had a limited theatrical run, typically opening in fewer than 250 theaters.
Common for art house and independent films.

### FESTIVAL

The film was shown at a film festival (Cannes, Sundance, TIFF, etc.) but may not have
had a wide theatrical release.

### STV

Straight-to-Video. The film was released directly to home video without a theatrical run.

Variations: `STV`, `STR8.2.VIDEO`

### COMPLETE

Indicates the release contains all episodes of a season, or all discs of a multi-disc
set.

Variations: `COMPLETE`, `COMPLETE.SERIES`, `COMPLETE.SEASON`

### DISC

Indicates which disc from a multi-disc set.

Variations: `DISC1`, `DISC2`, `D1`, `D2`, `DISC.1`

### HYBRID

The release was created from multiple sources. For example, video from a Blu-ray with
audio from a different source, or combining the best elements from different releases.

### RATED

Carries an official rating board classification, used to distinguish from an UNRATED
version.

### COLORIZED

A black-and-white film that has been digitally colorized.

---

## 14. Complete Disc Tags

Tags related to full disc images and structures.

| Tag | Meaning |
|-----|---------|
| `REMUX` | Lossless extraction from disc, re-muxed into MKV |
| `COMPLETE.BLURAY` | Full Blu-ray disc structure (BDMV) |
| `COMPLETE.UHD.BLURAY` | Full 4K UHD Blu-ray disc structure |
| `ISO` | Complete disc image file |
| `BDMV` | Blu-ray disc folder structure |
| `VIDEO_TS` | DVD folder structure |
| `DISC` | General disc indicator |
| `FULL.DISC` | Complete unmodified disc |

---

## 15. TV-Specific Tags

Tags specific to television series releases.

### Episode Identifiers

| Pattern | Meaning |
|---------|---------|
| `S01E01` | Season 1, Episode 1 |
| `S01E01E02` | Season 1, Episodes 1-2 (multi-episode file) |
| `S01E01-E03` | Season 1, Episodes 1 through 3 |
| `S01` | Complete Season 1 |
| `1x01` | Season 1, Episode 1 (alternate notation) |
| `E01` | Episode 1 (no season context) |

### Season Pack Tags

| Tag | Meaning |
|-----|---------|
| `COMPLETE` | Complete season or series |
| `COMPLETE.SERIES` | Entire series run |
| `Season.1` | Alternative season identifier |
| `PACK` | Multiple episodes bundled |

### TV Source Quality Tags

| Tag | Meaning |
|-----|---------|
| `HDTV` | HD television broadcast capture |
| `PDTV` | Pure Digital Television (digital broadcast capture) |
| `DSR` | Digital Satellite Rip |
| `DTH` | Direct-to-Home (satellite) |
| `AHDTV` | Analog HDTV capture |

---

## 16. Miscellaneous Tags

### Quality Indicators

| Tag | Meaning |
|-----|---------|
| `HQ` | High Quality |
| `LQ` | Low Quality |
| `MD` | Mic Dubbed (low quality audio) |
| `LINE` | Line audio (better than mic, direct from audio source) |

### Content Descriptors

| Tag | Meaning |
|-----|---------|
| `DOCU` / `DOCUMENTARY` | Documentary content |
| `ANIME` | Japanese animation |
| `CONCERT` | Live concert recording |
| `MINISERIES` | Limited series / miniseries |

### Technical Tags

| Tag | Meaning |
|-----|---------|
| `10bit` | 10-bit color depth encoding |
| `8bit` | 8-bit color depth encoding |
| `12bit` | 12-bit color depth encoding |
| `BT.2020` | Wide color gamut (typically UHD/HDR content) |
| `BT.709` | Standard HD color gamut |
| `WS` | Widescreen |
| `FS` | Fullscreen |
| `WIDESCREEN` | Widescreen aspect ratio |
| `PS` | Pan-and-Scan (cropped widescreen to 4:3) |
| `LETTERBOX` | Letterboxed (widescreen with black bars in 4:3 frame) |

### Release Group Tag

The final element in a scene release filename, after the last hyphen, is the release
group name:

```
Movie.Title.2024.BluRay.1080p.DTS-HD.MA.x265-GROUPNAME
                                              ^^^^^^^^^
```

The group name has no fixed vocabulary; it is the identifier of the encoding team.

---

## Appendix A: Tag Position in Filenames

Standard scene release naming follows this general order:

```
Title.Year.[Edition].[Source].[Resolution].[VideoCodec].[AudioCodec].[HDR].[Language].[ReleaseType]-GROUP
```

Not all fields are always present. Common minimal examples:

```
Movie.Title.2024.BluRay.1080p.x264.DTS-GROUP
Movie.Title.2024.Remastered.UHD.BluRay.2160p.HEVC.TrueHD.Atmos.HDR10.REMUX-GROUP
Movie.Title.2024.EXTENDED.WEB-DL.1080p.H264.AAC5.1-GROUP
Movie.Title.2024.PROPER.BluRay.720p.x265.DTS-GROUP
Show.Title.S03E05.720p.HDTV.x264-GROUP
Show.Title.S01.COMPLETE.BluRay.1080p.x265.DTS-HD.MA-GROUP
```

## Appendix B: Case Conventions

Scene releases use a mix of case conventions:

- Dots replace spaces in titles: `The.Matrix.1999`
- Tags are typically UPPERCASE: `BluRay`, `PROPER`, `REPACK`
- Some groups use lowercase `i` in words: `iNTERNAL`, `DiRFiX`, `RERiP`
- The `x` in codec names is typically lowercase: `x264`, `x265`
- Group names have their own capitalization preferences

## Appendix C: P2P vs Scene Differences

**Scene releases** follow strict standardized rules published by scene standards groups.
Naming, encoding settings, and packaging must conform to these rules.

**P2P releases** (peer-to-peer, from public trackers and private tracker groups) follow
conventions but have more flexibility. P2P groups may:

- Use higher bitrates than scene standards require
- Include multiple audio tracks where scene rules allow only one
- Use different container formats
- Apply custom encoding settings optimized for quality over compliance
