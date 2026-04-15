
# Scene Release Naming Convention Quick Reference

> Source: https://scenerules.org/


A consolidated reference of naming patterns, tags, and format tokens extracted from all
scene standards documents for use in building a filename parser.

---

## Release Name Structure

### Movies (Retail/Encoded)
```
Movie.Title.YEAR.TAGS.LANGUAGE.RESOLUTION.SOURCE.CODEC-GROUP
```
Examples:
- `Inception.2010.1080p.BluRay.x264-GROUP`
- `Inception.2010.REMASTERED.1080p.BluRay.x265-GROUP`
- `Inception.2010.2160p.UHD.BluRay.x265-GROUP`
- `Movie.Name.2020.720p.WEB.H264-GROUP`
- `Movie.Name.2020.1080p.WEBRip.x264-GROUP`
- `Movie.2015.BDRip.x264-GROUP`
- `Movie.2015.DVDRip.x264-GROUP`
- `Movie.2020.HDR.2160p.WEB.H265-GROUP`

### TV Series (Weekly)
```
Show.Name.SXXEXX.Episode.Title.TAGS.LANGUAGE.RESOLUTION.SOURCE.CODEC-GROUP
```
Examples:
- `Sample.Show.Eight.S05E16.720p.HDTV.x264-GROUP`
- `The.Office.US.S01E01.1080p.BluRay.x264-GROUP`
- `Game.of.Thrones.S08E06.1080p.WEB.H264-GROUP`
- `Show.Name.S01E01.FRENCH.720p.HDTV.x264-GROUP`

### TV Series (Daily)
```
Show.Name.YYYY.MM.DD.Guest.Name.TAGS.RESOLUTION.SOURCE.CODEC-GROUP
```
Examples:
- `Jimmy.Kimmel.2020.01.15.720p.HDTV.x264-GROUP`
- `Conan.2020.01.15.Guest.Name.720p.WEB.x264-GROUP`

### TV Series (Multiple Episodes)
```
Show.Name.SXXEXX-EXX.TAGS.RESOLUTION.SOURCE.CODEC-GROUP
```
Examples:
- `Show.Name.S01E01-E02.720p.HDTV.x264-GROUP`

### Miniseries
```
Show.Name.Part.X.TAGS.RESOLUTION.SOURCE.CODEC-GROUP
```

### TV Special
```
Show.Name.Special.SXXE00.Special.Title.TAGS.RESOLUTION.SOURCE.CODEC-GROUP
```

### Sports
```
League.YYYY.MM.DD.Event.TAGS.RESOLUTION.SOURCE.CODEC-GROUP
```

### Complete Blu-ray
```
Movie.Title.YEAR.COMPLETE.BLURAY-GROUP
```

---

## Source Tags

### Retail Sources (Encoded)
| Tag | Meaning |
|-----|---------|
| `BluRay` | Encoded from Blu-ray disc |
| `UHD.BluRay` | Encoded from Ultra HD Blu-ray disc |
| `HDDVD` | Encoded from HD DVD disc |
| `BDRip` | SD encode from Blu-ray source |
| `DVDRip` | SD encode from DVD source |
| `MBluRay` | Music Blu-ray |
| `UHD.MBluRay` | Music Ultra HD Blu-ray |

### TV Broadcast Sources
| Tag | Meaning |
|-----|---------|
| `HDTV` | HD natively recorded transport stream |
| `AHDTV` | Analog capture of HD broadcast |
| `PDTV` | 576i/576p natively recorded transport stream |
| `APDTV` | Analog capture of PDTV broadcast |
| `DSR` | 480i/480p natively recorded transport stream |
| `ADSR` | Analog capture of DSR broadcast |
| `HR.PDTV` | High-resolution PDTV (upscaled SD on HD channel) |

### Web Sources
| Tag | Meaning |
|-----|---------|
| `WEB` / `WEB-DL` | Losslessly downloaded from web service (untouched) |
| `WEBRip` | Captured/transcoded from web source (lossy) |
| `WEB.H264` | Untouched web download, H.264 codec |
| `WEB.H265` | Untouched web download, H.265 codec |
| `WEBRip.x264` | Transcoded web capture, x264 encoder |
| `WEBRip.x265` | Transcoded web capture, x265 encoder |

### Non-Retail Sources
| Tag | Meaning |
|-----|---------|
| `CAM` | Camera recording in theater |
| `TELESYNC` / `TS` | Audio from direct source, video from cam |
| `TELECINE` / `TC` | Film reel transferred to digital |
| `SCREENER` / `SCR` | Pre-release review copy |
| `WORKPRINT` | Pre-final version |
| `DCP` | Digital Cinema Package |
| `D-THEATER` | D-Theater source |
| `MUSE-LD` | MUSE LaserDisc |

---

## Video Codec Tags

| Tag | Meaning |
|-----|---------|
| `x264` | Encoded with x264 (H.264/AVC) encoder |
| `x265` | Encoded with x265 (H.265/HEVC) encoder |
| `H264` | H.264 codec (untouched/remux) |
| `H265` | H.265 codec (untouched/remux) |
| `XviD` | Legacy XviD encoder (defunct for new releases) |
| `VP9` | VP9 codec (web sources only, when no H.264/H.265 available) |
| `AV1` | AV1 codec (web sources only, when no H.264/H.265 available) |

### Distinction: x264/x265 vs H264/H265
- `x264`/`x265` = encoded (transcoded) content
- `H264`/`H265` = untouched/remuxed content (original codec preserved)

---

## Resolution Tags

| Tag | Max Resolution | Notes |
|-----|---------------|-------|
| (none/SD) | 720px wide | No resolution tag for SD |
| `720p` | 1280x720 | |
| `1080p` | 1920x1080 | |
| `2160p` | 3840x2160 | |

---

## Audio Format Tags (commonly in filename or NFO)

| Tag | Meaning |
|-----|---------|
| `DTS-HD.MA` | DTS-HD Master Audio (lossless) |
| `DTS-HD.HR` | DTS-HD High Resolution |
| `DTS` | DTS core |
| `DTS-ES` | DTS Extended Surround |
| `DTS.X` / `DTS-X` | DTS:X (object-based) |
| `TrueHD` | Dolby TrueHD (lossless) |
| `TrueHD.Atmos` | Dolby TrueHD with Atmos (lossless + object) |
| `DD5.1` / `AC3` | Dolby Digital 5.1 |
| `DD2.0` | Dolby Digital 2.0 |
| `EAC3` / `DD+` / `DDP` | Enhanced AC-3 / Dolby Digital Plus |
| `AAC` | Advanced Audio Coding |
| `FLAC` | Free Lossless Audio Codec |
| `LPCM` | Linear PCM (uncompressed) |
| `MP2` | MPEG Audio Layer 2 |

---

## Version/Edition Tags

| Tag | Meaning |
|-----|---------|
| `DC` | Director's Cut |
| `EXTENDED` | Extended version |
| `UNCUT` | Uncut version |
| `UNRATED` | Unrated version |
| `RATED` | Rated version |
| `THEATRICAL` | Theatrical release |
| `REMASTERED` | Remastered version |
| `RESTORED` | Restored version |
| `CHRONO` | Chronological edit |
| `OAR` | Original Aspect Ratio |
| `ALTERNATIVE.CUT` | Alternative cut |
| `SE` | Special Edition |

---

## Quality/Status Tags

| Tag | Meaning |
|-----|---------|
| `PROPER` | Re-release fixing technical flaw in previous release |
| `REPACK` | Fix by same group (packing/muxing issue) |
| `RERIP` | Fix by same group (ripping/encoding issue) |
| `REAL` | Clarifies which PROPER is the valid one |
| `INTERNAL` | Not intended for wide distribution (dupes, experiments, quality variants) |
| `READNFO` | NFO contains important information |
| `FINAL` | Final version |

---

## Fix Tags

| Tag | Meaning |
|-----|---------|
| `DIRFIX` | Directory name correction |
| `NFOFIX` | NFO file correction |
| `SAMPLEFIX` | Sample file correction |
| `PROOFFIX` | Proof image correction |
| `SOURCE.SAMPLE` | Source verification sample |

---

## Format/Display Tags

| Tag | Meaning |
|-----|---------|
| `WS` | Widescreen (when different-AR release exists) |
| `FS` | Fullscreen (when different-AR release exists) |
| `OM` | Open Matte (when different-AR release exists) |
| `BW` | Black and White |
| `COLORIZED` | Colorized version of B&W content |
| `CONVERT` | Framerate conversion artifacts present |

---

## HDR Tags

| Tag | Meaning |
|-----|---------|
| `HDR` | High Dynamic Range (HDR10) |
| `HDR10Plus` | HDR10+ (dynamic metadata) |
| `DV` | Dolby Vision |
| `SDR` | Standard Dynamic Range (used when distinguishing from HDR) |

---

## Audio/Subtitle Tags

| Tag | Meaning |
|-----|---------|
| `DUBBED` | Non-original language audio dub (no original audio) |
| `SUBBED` | Hardcoded subtitles throughout feature |
| `LINE` | Line audio (non-studio audio source) |
| `MULTi` | 2+ audio languages (Blu-ray) |
| `MULTiSUBS` | 6+ subtitle languages (Blu-ray) |

---

## TV-Specific Tags

| Tag | Meaning |
|-----|---------|
| `WEST.FEED` | West coast broadcast version |
| `PPV` | Pay-per-view source |

---

## Distribution Tags (SD movies)

| Tag | Meaning |
|-----|---------|
| `LIMITED` | Limited theatrical release |
| `STV` | Straight-to-video |
| `FESTIVAL` | Film festival source |

---

## Special Tags

| Tag | Meaning |
|-----|---------|
| `EXTRAS` | Bonus content release |
| `PURE` | Audio-only release from video disc |
| `UNCENSORED` | Uncensored version |
| `HR` | High-resolution (WEB source below minimum) |

---

## Season/Episode Numbering

| Pattern | Description | Example |
|---------|-------------|---------|
| `SXXEXX` | Season XX Episode XX | `S01E01`, `S01E12` |
| `SXXEXX-EXX` | Multi-episode | `S01E01-E02` |
| `SXXE00` | Special (episode 0) | `S01E00` |
| `EXX` | Episode only (no seasons) | `E01`, `E128` |
| `Part.X` | Miniseries part | `Part.1`, `Part.10` |
| `SXXEXXXX` | Episode part suffix | `S02E01A`, `S02E01B` |
| `YYYY.MM.DD` | Daily show date | `2020.01.15` |
| `YYYY` | Production year (movies) | `2020` |

---

## Language Tags

Non-English releases use full language name (not ISO codes):
`FRENCH`, `GERMAN`, `RUSSIAN`, `SPANISH`, `ITALIAN`, `DUTCH`, `SWEDISH`, `POLISH`, `JAPANESE`, `KOREAN`, `CHINESE`, etc.

Established compact tags: `PLDUB`, `SWESUB`, `SUBFRENCH`, `NLSUBBED`

UK shows use `UK` country code (not `GB`).

---

## Character Rules

- Allowed characters in directory names: `A-Z`, `a-z`, `0-9`, `.`, `_`, `-`
- Period (`.`) replaces spaces
- No consecutive punctuation
- Group name follows final hyphen (`-GROUP`)
- No typos/spelling mistakes allowed

---

## Dupe Hierarchy (Source Priority)

### HD Sources
All HD retail formats dupe each other (BluRay = HDDVD = UHD.BluRay within same resolution).

### TV Sources (720p)
- AHDTV dupes HDTV
- HDTV does NOT dupe AHDTV
- HR.PDTV dupes HDTV and AHDTV
- All broadcast sources dupe equivalent Retail

### TV Sources (SD)
- AHDTV dupes HDTV
- HDTV does NOT dupe AHDTV
- PDTV/APDTV dupe HDTV/AHDTV
- DSR/ADSR dupe all above
- All broadcast sources dupe equivalent Retail

### Web Sources
- WEB (untouched) and WEBRip (transcoded) are distinct source types
- WEBRip.x264/x265 for transcoded; WEB.H264/H265 for untouched

### General Dupe Rules
- Hardcoded subs (SUBBED) dupes muxed subs
- Muxed subs does NOT dupe hardcoded
- Native FPS does NOT dupe converted FPS
- Converted FPS dupes native FPS
- HDR and SDR are NOT dupes of each other
- Non-retail dupes retail
- Retail does NOT dupe non-retail
- Different version tags (DC, EXTENDED, etc.) are NOT dupes except censored-after-uncensored

---

## Available Standards Documents (scenerules.org)

| Document | Year | Covers |
|----------|------|--------|
| SD TV x264 | 2016 | SD television x264 releases |
| 720p TV x264 | 2016 | 720p television x264 releases |
| SD x264 Movies | 2013 | SD movie x264 releases (BDRip/DVDRip) |
| HD/UHD x264/x265 | 2020 | HD/UHD retail (BluRay) x264/x265 releases |
| WEB/WEBRip | 2020 | WEB and WEBRip x264/x265 releases |
| Blu-ray | 2014 | Complete Blu-ray disc releases |
| FLAC | 2016 | Music FLAC releases |
| WEBFLAC | 2023 | Web music FLAC releases |
| MP3 | 2021 | Music MP3 releases |
| eBook | 2022 | eBook releases |
| MViD | v6 | Music video releases |
