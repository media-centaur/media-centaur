---
title: Video Release Filename Structure Conventions
category: naming-conventions
date_accessed: 2026-03-12
sources:
  - url: https://scenerules.org/t.html?id=2020_X265.nfo
    title: "Scene Rules — X265 Standard (Revision 5.0)"
  - url: https://guessit.readthedocs.io/en/latest/properties.html
    title: "GuessIt Properties Documentation"
  - url: https://ripped.guide/Scene/Scene-Glossary/
    title: "Scene Glossary — Ripped Guide"
  - url: https://thewiki.moe/advanced/naming/
    title: "Anime Naming — TheWiki.moe"
  - url: https://github.com/guessit-io/guessit
    title: "GuessIt GitHub Repository"
  - url: https://support.plex.tv/articles/naming-and-organizing-your-movie-media-files/
    title: "Plex Movie Naming Guide"
  - url: https://dimitris.tech/tutorials/453/
    title: "Torrent Types & Scene Releases Explained"
---

# Video Release Filename Structure Conventions

This document describes the structural rules governing how video release
filenames are assembled — the canonical ordering of tags, character encoding
rules, and the differences between scene, P2P, and anime conventions.

## 1. Canonical Scene Format

Scene releases follow a strict, standardized naming format defined by
community rule documents (NFOs published at scenerules.org). The format is a
period-delimited sequence of fields ending with a hyphen and the release group
name.

### 1.1 Movies

```
Title.Year.TAGS.LANGUAGE.Resolution.Source.Codec-GROUP
```

Examples:

```
The.Shawshank.Redemption.1994.REMASTERED.1080p.BluRay.x264-GROUP
Citizenfour.2014.720p.WEB-DL.AAC2.0.H.264-NOGRP
Sample Movie Thirteen.Part.Two.2024.2160p.UHD.BluRay.HDR.DTS-HD.MA.7.1.x265-GROUP
```

The **year** is mandatory for non-series releases. It appears immediately after
the title and serves as the boundary marker between the title and the
technical tags.

### 1.2 TV Series (Weekly)

```
Show.Name.COUNTRY.YEAR.SXXEXX.Episode.Title.TAGS.LANGUAGE.Resolution.Source.Codec-GROUP
```

Examples:

```
Sample.Show.Eight.S05E16.Felina.720p.BluRay.x264-DEMAND
The.Office.US.S02E06.1080p.WEB-DL.DD5.1.H.264-GROUP
```

Country code and year are optional — included only when needed to
disambiguate (e.g., `The.Office.US` vs `The.Office.UK`).

### 1.3 TV Series (Multi-Episode)

```
Show.Name.SXXEXX-EXX.Episode.Title.TAGS.Resolution.Source.Codec-GROUP
```

Example:

```
Game.of.Thrones.S04E09-E10.1080p.BluRay.x264-GROUP
```

### 1.4 Miniseries

```
Show.Name.PartX.Episode.Title.TAGS.Resolution.Source.Codec-GROUP
```

Uses `PartX` instead of `SXXEXX`. Part numbers are at least 1 digit wide.

### 1.5 Music/Performance

```
Performance.Name.PERFORMANCE_YEAR.TAGS.Resolution.Source.Codec-GROUP
```

## 2. Field Ordering

The canonical ordering of fields, from left to right:

| Position | Field | Required | Examples |
|----------|-------|----------|---------|
| 1 | **Title** | Yes | `The.Matrix`, `Sample.Show.Eight` |
| 2 | **Country code** | If ambiguous | `US`, `UK`, `NZ` |
| 3 | **Year** | Movies: yes; TV: if ambiguous | `2024`, `1994` |
| 4 | **Season/Episode** | TV only | `S01E01`, `S01E01-E03` |
| 5 | **Episode title** | Optional | `Pilot`, `The.Rains.of.Castamere` |
| 6 | **Edition/release tags** | If applicable | `REMASTERED`, `EXTENDED`, `DIRECTORS.CUT` |
| 7 | **Fix tags** | If applicable | `PROPER`, `REPACK`, `RERIP` |
| 8 | **Language** | Non-English only | `FRENCH`, `GERMAN`, `RUSSIAN` |
| 9 | **Resolution** | Yes | `720p`, `1080p`, `2160p` |
| 10 | **HDR format** | If applicable | `HDR`, `HDR10`, `DV` (Dolby Vision) |
| 11 | **Source** | Yes | `BluRay`, `WEB-DL`, `HDTV` |
| 12 | **Audio format** | Common but not always present | `DTS-HD.MA.5.1`, `DD5.1`, `AAC2.0` |
| 13 | **Video codec** | Yes | `x264`, `x265`, `H.264`, `XviD` |
| 14 | **-GROUP** | Yes (after final hyphen) | `-SPARKS`, `-YIFY`, `-FGT` |

Tags at positions 6-7 are "grouped together, period-delimited" and their
internal order is at the group's discretion, but they always appear between
the episode identifier and the technical specs. Examples: `EXTENDED.RERIP`,
`REMASTERED.REPACK`.

## 3. Character Encoding Rules

### 3.1 Allowed Characters

Scene standards restrict filenames to:

```
A-Z a-z 0-9 . _ -
```

No other characters are permitted. No consecutive punctuation marks.

### 3.2 Spaces to Dots

Spaces in titles are replaced with periods:

```
The Lord of the Rings  →  The.Lord.of.the.Rings
```

### 3.3 Special Characters in Titles

Characters that cannot appear in filenames are handled by removal or
substitution:

| Character | Handling | Example |
|-----------|----------|---------|
| `:` (colon) | Omitted or replaced with `.` | `Spider-Man: No Way Home` → `Spider-Man.No.Way.Home` |
| `'` (apostrophe) | Omitted | `Schindler's List` → `Schindlers.List` |
| `&` | Replaced with `and` | `Fast & Furious` → `Fast.and.Furious` |
| `,` (comma) | Omitted | `The Good, the Bad...` → `The.Good.the.Bad...` |
| `!` `?` `#` | Omitted | |
| `(` `)` | Omitted (content kept) | `Spider-Man (2002)` — but year parens are standard |

Hyphens in titles are preserved literally: `Spider-Man` stays `Spider-Man`.
The parser must distinguish title-internal hyphens from the group-tag hyphen
(the final hyphen in the filename).

### 3.4 Underscores

Some P2P releases and older scene releases use underscores instead of dots as
the delimiter. Less common today but still encountered:

```
The_Shawshank_Redemption_1994_1080p_BluRay_x264-GROUP
```

## 4. The Group Tag

The release group name **always** appears after the final hyphen in the
filename. This is the single most consistent rule across all conventions.

```
Movie.Name.2024.1080p.BluRay.x264-SPARKS
                                   ^^^^^^ group tag
```

This creates an ambiguity with hyphenated source tags like `WEB-DL` and
`DTS-HD`. Parsers must recognize these as compound tags rather than treating
`DL` or `HD` as the group name. The group tag is specifically the text after
the **last** hyphen.

Known compound tags containing hyphens:

- `WEB-DL`, `WEB-Rip`
- `DTS-HD`, `DTS-HD.MA`
- `Blu-ray`
- `H.264`, `H.265` (dot-separated, no hyphen issue)
- `DD+` / `DDP` (Dolby Digital Plus)

## 5. Source Tags

| Tag | Meaning |
|-----|---------|
| `CAM` / `CAMRip` | Camera recording from theater |
| `TS` / `TELESYNC` | Audio from direct source, video from cam |
| `TC` / `TELECINE` | Film-to-digital transfer |
| `SCR` / `DVDSCR` | From promotional DVD screener |
| `R5` | Region 5 retail DVD (early release region) |
| `DVDRip` | Ripped from retail DVD |
| `BDRip` / `BRRip` | Re-encoded from Blu-ray source |
| `BluRay` / `Blu-ray` | Direct Blu-ray disc rip |
| `UHD.BluRay` | 4K Ultra HD Blu-ray |
| `Remux` | Blu-ray remux (no re-encoding) |
| `HDTV` | Captured from HD broadcast |
| `PDTV` | Pure Digital TV capture |
| `DSR` / `DSRip` | Digital satellite rip |
| `WEB-DL` | Downloaded from streaming service (no re-encode) |
| `WEBRip` | Screen-captured from streaming service |
| `WEB` | Generic web source (ambiguous between WEB-DL and WEBRip) |

Streaming service tags appear before `WEB-DL` or `WEBRip`:

```
Show.Name.S01E01.1080p.AMZN.WEB-DL.DDP5.1.H.264-GROUP
```

Common streaming service abbreviations:

| Abbreviation | Service |
|-------------|---------|
| `AMZN` | Amazon Prime Video |
| `NF` | Netflix |
| `DSNP` | Disney+ |
| `HULU` | Hulu |
| `ATVP` | Apple TV+ |
| `HMAX` / `MAX` | HBO Max / Max |
| `PCOK` | Peacock |
| `PMTP` | Paramount+ |
| `CR` | Crunchyroll |
| `FUNI` | Funimation |
| `iT` | iTunes |

## 6. Resolution Tags

| Tag | Meaning |
|-----|---------|
| `480p` | Standard definition |
| `576p` | PAL standard definition |
| `720p` | HD |
| `1080p` | Full HD progressive |
| `1080i` | Full HD interlaced |
| `2160p` | 4K Ultra HD |
| `4320p` | 8K (rare) |

## 7. Video Codec Tags

| Tag | Codec |
|-----|-------|
| `x264` / `H.264` / `AVC` | H.264 (scene uses `x264` for software encode) |
| `x265` / `H.265` / `HEVC` | H.265 |
| `XviD` / `DivX` | MPEG-4 Part 2 (legacy) |
| `VP9` | Google VP9 |
| `AV1` | AOMedia Video 1 |

## 8. Audio Codec Tags

| Tag | Codec |
|-----|-------|
| `AAC` / `AAC2.0` | Advanced Audio Coding |
| `AC3` / `DD5.1` | Dolby Digital |
| `DDP` / `DDP5.1` / `DD+` | Dolby Digital Plus |
| `EAC3` | Enhanced AC-3 (Dolby Digital Plus alternate tag) |
| `DTS` | DTS core |
| `DTS-HD` / `DTS-HD.MA` | DTS-HD Master Audio |
| `TrueHD` | Dolby TrueHD |
| `Atmos` | Dolby Atmos (often alongside TrueHD) |
| `FLAC` | Free Lossless Audio Codec |
| `Opus` | Opus codec |
| `MP3` | MPEG Layer 3 |
| `LPCM` | Linear PCM |

Channel layout appears as a suffix: `5.1`, `7.1`, `2.0`, `1.0`.

## 9. Edition and Release Tags

### 9.1 Edition Tags

| Tag | Meaning |
|-----|---------|
| `EXTENDED` | Extended cut |
| `DIRECTORS.CUT` / `DC` | Director's cut |
| `UNRATED` | Unrated version |
| `THEATRICAL` | Theatrical release (when multiple cuts exist) |
| `REMASTERED` | Digitally remastered |
| `CRITERION` | Criterion Collection release |
| `IMAX` | IMAX version |
| `SPECIAL.EDITION` / `SE` | Special edition |
| `ANNIVERSARY.EDITION` | Anniversary edition |
| `COLLECTORS.EDITION` | Collector's edition |
| `FINAL.CUT` | Final cut (e.g., Sample Movie) |
| `OPEN.MATTE` | Full-frame version of a matted film |

### 9.2 Fix/Revision Tags

| Tag | Meaning |
|-----|---------|
| `PROPER` | Replacement by a different group (previous release had issues) |
| `REPACK` | Fixed re-release by the **same** group |
| `RERIP` | Re-ripped from source (previous rip was bad) |
| `REAL.PROPER` | Improvement upon an existing PROPER |
| `INTERNAL` / `iNTERNAL` | Limited distribution; avoids nuke for duplicates |
| `DIRFIX` | Fixed directory naming |
| `NFOFIX` | Fixed NFO file |
| `SAMPLEFIX` | Fixed sample file |
| `PROOFFIX` | Fixed proof |
| `CONVERT` | Converted from another format |
| `READNFO` | NFO contains important info about the release |

### 9.3 Content Tags

| Tag | Meaning |
|-----|---------|
| `DUBBED` | Audio dubbed to a different language |
| `SUBBED` | Hardcoded subtitles |
| `DUAL.AUDIO` | Two audio tracks |
| `MULTI` | Multiple languages |
| `HARDCODED` / `HC` | Hardcoded subtitles (cannot be removed) |
| `SDR` | Standard Dynamic Range |
| `HDR` / `HDR10` / `HDR10+` | High Dynamic Range |
| `DV` / `DoVi` | Dolby Vision |
| `3D` | Stereoscopic 3D |
| `HYBRID` | Combined from multiple sources |
| `Remux` | Lossless copy from disc |
| `COMPLETE` | Complete series/season pack |
| `RETAIL` | From retail source (not screener) |

## 10. P2P vs Scene Differences

### 10.1 Scene Releases

- Follow strict, published rule documents (NFOs at scenerules.org)
- Violations result in "nukes" (release is flagged as bad)
- Dots as delimiters (mandatory)
- Group tag after final hyphen (mandatory)
- Consistent tag ordering
- Must include NFO file with technical details
- English releases omit language tag; non-English must include it

### 10.2 P2P Releases

- No enforced rules — naming is by convention, not requirement
- May use spaces, underscores, or dots as delimiters
- May include additional information (encoder settings, source details)
- Group tag still typically after final hyphen but not guaranteed
- More likely to include streaming service tags
- May omit group tag entirely
- Quality varies — no nuke system for enforcement

### 10.3 Common P2P Variations

```
# Spaces instead of dots
Movie Name 2024 1080p BluRay x264-GROUP

# Extra detail in brackets
Movie.Name.2024.1080p.BluRay.x264-GROUP [1337x]

# No group tag
Movie.Name.2024.1080p.BluRay.x264

# Streaming service emphasis
Movie.Name.2024.1080p.NF.WEB-DL.DDP5.1.Atmos.H.265-GROUP

# Website tag at start
www.Torrents.com - Movie.Name.2024.1080p.BluRay.x264-GROUP
```

## 11. Anime Conventions (Fansub Style)

Anime releases follow a different structure from scene releases. See
`tv-episode-naming-patterns.md` for episode numbering details.

### 11.1 Fansub Format

```
[Group] Anime Name - SXXEYY - Episode Title (Source Resolution Codec Audio) [Tags] [CRC32].mkv
```

Example:

```
[SubsPlease] Jujutsu Kaisen - S02E04 (BD 1080p HEVC Opus) [Dual Audio] [CF1029D9].mkv
```

Key differences from scene:

- **Group tag at the start** in square brackets (not at end after hyphen)
- **Spaces** as delimiters instead of dots
- **Square brackets** around metadata and CRC32
- **CRC32 checksum** (8-character hex) for integrity verification
- **Parentheses** around technical specs

### 11.2 Scene-Style Anime

Some anime releases use standard scene naming:

```
Anime.Name.S01E01.1080p.BluRay.x264-GROUP
```

## 12. Complete Field Reference (GuessIt)

The GuessIt library (the most mature open-source filename parser) recognizes
these property categories:

| Category | Properties |
|----------|------------|
| **Identity** | `title`, `alternative_title`, `type` (movie/episode) |
| **Episode** | `season`, `episode`, `episode_count`, `season_count`, `disc`, `part`, `version`, `episode_details` (Final/Pilot/Special/Unaired), `episode_format` (Minisode) |
| **Date** | `date`, `year` |
| **Video** | `source`, `screen_size`, `aspect_ratio`, `video_codec`, `video_profile`, `color_depth` (8/10/12-bit), `frame_rate`, `video_bit_rate` |
| **Audio** | `audio_codec`, `audio_channels`, `audio_profile`, `audio_bit_rate` |
| **Localization** | `language`, `subtitle_language`, `country` |
| **Release** | `release_group`, `website`, `streaming_service` (70+ services), `edition`, `other` (3D/HDR10/DV/Proper/Retail/etc.) |
| **File** | `container`, `mimetype`, `crc32`, `uuid`, `size`, `cd`, `cd_count` |
| **Bonus** | `bonus`, `bonus_title`, `film`, `film_title`, `film_series` |

## 13. Parsing Priorities

When parsing a filename, the structural cues that anchor the parse are:

1. **Year** — a 4-digit number (1920-2029) marks the boundary between title
   and tags for movies
2. **Season/Episode** — `S01E01` marks the boundary for TV episodes
3. **Final hyphen** — everything after it is the group tag
4. **Known tag vocabulary** — resolution, source, codec tokens are recognized
   from a fixed vocabulary and removed; what remains is the title
5. **Container extension** — `.mkv`, `.mp4`, `.avi` at the end is stripped
   first

The title is effectively "everything before the first recognized structural
marker (year or season/episode) that is not part of the title itself." This
makes title extraction the hardest parsing problem — it requires knowing the
tag vocabulary to identify where the title ends.
