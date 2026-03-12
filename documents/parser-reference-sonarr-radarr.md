---
title: "Parser Reference: Sonarr & Radarr"
sources:
  - https://github.com/Sonarr/Sonarr/blob/develop/src/NzbDrone.Core/Parser/Parser.cs
  - https://github.com/Sonarr/Sonarr/blob/develop/src/NzbDrone.Core/Parser/QualityParser.cs
  - https://github.com/Radarr/Radarr/blob/develop/src/NzbDrone.Core/Parser/Parser.cs
  - https://github.com/Radarr/Radarr/blob/develop/src/NzbDrone.Core/Parser/QualityParser.cs
  - https://github.com/Radarr/Radarr/blob/develop/src/NzbDrone.Core/Qualities/Quality.cs
  - https://github.com/Radarr/Radarr/blob/develop/src/NzbDrone.Core/Parser/LanguageParser.cs
date_accessed: 2026-03-12
category: parser-reference
---

# Sonarr & Radarr - Quality / Tag Parsing (C#)

Both projects share the same NzbDrone parser codebase. Radarr focuses on movies,
Sonarr on TV series. Their quality parser is the industry standard for release
name classification.

## Quality Definitions (30 Levels)

| Quality Name | ID | Source | Resolution | Modifier |
|---|---|---|---|---|
| Unknown | 0 | UNKNOWN | 0 | NONE |
| WORKPRINT | 24 | WORKPRINT | 0 | NONE |
| CAM | 25 | CAM | 0 | NONE |
| TELESYNC | 26 | TELESYNC | 0 | NONE |
| TELECINE | 27 | TELECINE | 0 | NONE |
| DVDSCR | 28 | DVD | 480 | SCREENER |
| REGIONAL | 29 | DVD | 480 | REGIONAL |
| SDTV | 1 | TV | 480 | NONE |
| DVD | 2 | DVD | 0 | NONE |
| DVDR | 23 | DVD | 480 | REMUX |
| HDTV720p | 4 | TV | 720 | NONE |
| HDTV1080p | 9 | TV | 1080 | NONE |
| HDTV2160p | 16 | TV | 2160 | NONE |
| WEBDL480p | 8 | WEBDL | 480 | NONE |
| WEBDL720p | 5 | WEBDL | 720 | NONE |
| WEBDL1080p | 3 | WEBDL | 1080 | NONE |
| WEBDL2160p | 18 | WEBDL | 2160 | NONE |
| WEBRip480p | 12 | WEBRIP | 480 | NONE |
| WEBRip720p | 14 | WEBRIP | 720 | NONE |
| WEBRip1080p | 15 | WEBRIP | 1080 | NONE |
| WEBRip2160p | 17 | WEBRIP | 2160 | NONE |
| Bluray480p | 20 | BLURAY | 480 | NONE |
| Bluray576p | 21 | BLURAY | 576 | NONE |
| Bluray720p | 6 | BLURAY | 720 | NONE |
| Bluray1080p | 7 | BLURAY | 1080 | NONE |
| Bluray2160p | 19 | BLURAY | 2160 | NONE |
| Remux1080p | 30 | BLURAY | 1080 | REMUX |
| Remux2160p | 31 | BLURAY | 2160 | REMUX |
| BRDISK | 22 | BLURAY | 1080 | BRDISK |
| RAWHD | 10 | TV | 1080 | RAWHD |

## Source Detection Regex (SourceRegex)

Patterns matched (case-insensitive, word-boundary aware):

### Blu-ray
`M?Blu[-_. ]?Ray|HD[-_. ]?DVD|BD(?!$)|UHD|BDISO|BDMux|BD25|BD50`

### Web-DL
`WEB[-_. ]?DL|AmazonHD|AmazonSD|iTunesHD|NetflixHD|NetflixUHD|HBOMaxHD|DisneyHD|WebHD`

### WEBRip
`WebRip|Web-Rip|WEBMux`

### HDTV
`HDTV`

### BDRip
`BDRip|BDLight|HD[-_. ]?DVDRip|UHDBDRip`

### BRRip
`BRRip`

### DVD-R
`DVD-R|DVDR|DVD-Full|Full-Rip`

### DVD
`DVD(?:Rip|Mux)?|DVDScr`

### DSR
`WS[-_. ]?DSR|DSR`

### Regional
`Regional`

### Screener
`SCR|Screener`

### Telesync
`CAM[-_. ]?TS|TS[-_. ]?CAM|HDTS|HD-?TS|TELESYNC|PDVD|PreDVD`

### Telecine
`TC|TELECINE`

### CAM
`CAMRip|CAM|HD-?CAM`

### Workprint
`WORKPRINT|WP`

### PDTV / SDTV / TVRip
`PDTV|SDTV|TVRip`

## Resolution Detection Regex (ResolutionRegex)

| Pattern | Resolution |
|---------|-----------|
| `(?:(?:\d{3,4}(?:x\|curved))?360(?:p\|i)?)` | 360p |
| `(?:(?:\d{3,4}(?:x\|curved))?480(?:p\|i)?)` | 480p |
| `(?:(?:\d{3,4}(?:x\|curved))?540(?:p\|i)?)` | 540p |
| `(?:(?:\d{3,4}(?:x\|curved))?576(?:p\|i)?)` | 576p |
| `(?:1280x)?720(?:p\|i)?`, `960p` | 720p |
| `(?:1920x)?1080(?:p\|i)?`, `FHD`, `4kto1080p` | 1080p |
| `(?:3840x)?2160(?:p\|i)?`, `4k`, `UHD` | 2160p |

Alternative: `\[4K\]` also maps to 2160p.

## Codec Detection Regex (CodecRegex)

| Pattern | Codec |
|---------|-------|
| `x264` | x264 |
| `h264`, `h.264` | h264 |
| `XvidHD` | XvidHD |
| `X-?vid` | Xvid |
| `DivX` | DivX |
| `MPEG[-_. ]?2` | MPEG-2 |

## Edition Detection Regex (EditionRegex, Radarr only)

Matches these edition keywords (case-insensitive):

### Cut Variants
- `Director's? Cut`, `Director Cut`
- `Collector's? Cut`, `Collector Cut`
- `Theatrical`, `Theatrical Cut`
- `Extended`, `Extended Cut`
- `Assembly Cut`
- `Final Cut`
- `Alternative Cut`

### Named Editions
- `Criterion`, `Criterion Collection`
- `IMAX`
- `Despecialized`
- `Diamond`
- `Signature`
- `Imperial`
- `Hunter`
- `Rekall`
- `Rouge`

### Modifications
- `Uncensored`
- `Remastered`, `4K Remastered`
- `Unrated`
- `Uncut`
- `Open Matte`
- `Fan Edit`
- `Restored`
- `Anniversary` (with optional numeric prefix like "25th")

### Compilations
- `2in1`, `3in1`, `4in1`

## Modifier Detection Regexes

| Pattern | Detection |
|---------|-----------|
| `\b(?:proper)\b` | PROPER release |
| `\b(?:repack\d?\|rerip\d?)\b` | REPACK / RERIP |
| `\b(?:REAL)\b` | REAL (case-sensitive) |
| `v\d+`, `[v\d+]` | Version number |
| `RawHD`, `Raw[-_. ]HD` | Raw HD source |
| `Remux` | Remux |

## Anime-Specific Patterns

| Pattern | Detection |
|---------|-----------|
| `bd(?:720\|1080\|2160)` | Anime Blu-ray (e.g. `bd1080`) |
| `(?<=[-_. (\[])bd(?=[-_. )\]])` | Anime BD marker in brackets |
| `\[WEB\]`, `[\[(]WEB[ .]` | Anime Web-DL |

## Hardcoded Subtitle Detection

`\b(?:HC\|SUBBED\|SUBS)\b`

## Sonarr: TV Episode Title Patterns

Sonarr has 85+ regex patterns for episode detection. Key formats:

### Standard Formats
- `S01E05` - Season + Episode
- `1x05` - Compact
- `S01E05E06` or `S01E05-E06` - Multi-episode
- `S01E05a`, `S01E05b` - Split episodes

### Daily Show Formats
- `2024-01-15` (YYYY-MM-DD)
- `20240115` (YYYYMMDD)
- `01-15-2024` (MM-DD-YYYY)
- `15-01-2024` (DD-MM-YYYY)

### Absolute Episode Numbers (Anime)
- `[SubGroup] Title - 05`
- `[SubGroup] Title - S2 - 05`
- Bare number with context

### International Formats
- Turkish: `BLM` / `Bolum` episode markers
- Spanish: `Temporada X` / `Cap.XXX`
- Korean: `.E05.YYMMDD.` date-embedded

### Season Folder Detection
`S\d+`, `Season \d+`, `Saison \d+`, `Temporada \d+`, `Series \d+`

### Special/Bonus Detection
- `E00` = special episode
- `Special.` prefix
- `Extras` marker

## Radarr: Movie Title Patterns

### Standard: `Title.Year.Tags`
`(?<title>.+?)(?:[-_\W])*(?<year>(1(8|9)|20)\d{2})`

### Anime: `[SubGroup] Title (Year) [hash]`
`\[(?<subgroup>.+?)\][-_. ]?(?<title>.+?)(?:\((?<year>\d{4})\))`

### Edition-aware
Title + Edition + Year pattern

### IMDb/TMDb ID extraction
- `tt\d{7,8}` (IMDb)
- `tmdb(id)?-(?<tmdbid>\d+)` (TMDb)

## Language Detection (Radarr LanguageParser)

### Case-Insensitive Patterns
| Pattern | Language |
|---------|----------|
| `\beng\b` | English |
| `\b(?:ita\|italian)\b` | Italian |
| `(?:swiss)?german\|videomann\|ger[. ]dub\|\bger\b` | German |
| `flemish` | Flemish |
| `bgaudio` | Bulgarian |
| `rodubbed` | Romanian |
| `\b(dublado\|pt-BR)\b` | Portuguese (Brazilian) |
| `greek` | Greek |
| `\b(?:FR\|VO\|VF\|VFF\|VFQ\|VFI\|VF2\|TRUEFRENCH\|FRENCH\|FRE\|FRA)\b` | French |
| `\b(?:rus\|ru)\b` | Russian |
| `\b(?:HUNDUB\|HUN)\b` | Hungarian |
| `\b(?:HebDub\|HebDubbed)\b` | Hebrew |
| `\b(?:PL\W?DUB\|DUB\W?PL\|LEK\W?PL\|PL\W?LEK)\b` | Polish |
| `\[(?:CH[ST]\|BIG5\|GB)\]\|simplified\|traditional` | Chinese |
| `(?:(?:\dx)?UKR)` | Ukrainian |
| `\b(?:espanol\|castellano)\b` | Spanish |
| `\b(?:catalan?\|catalan\|catala)\b` | Catalan |
| `\b(?:lat\|lav\|lv)\b` | Latvian |
| `\btel\b` | Telugu |
| `\bVIE\b` | Vietnamese |
| `\bJAP\b` | Japanese |
| `\bKOR\b` | Korean |
| `\burdu\b` | Urdu |
| `\b(?:mongolian\|khalkha)\b` | Mongolian |
| `\b(?:georgian\|geo\|ka\|kat)\b` | Georgian |
| `\b(?:orig\|original)\b` | Original |

### Case-Sensitive Patterns
| Pattern | Language |
|---------|----------|
| `\bEN\b` | English |
| `\bLT\b` | Lithuanian |
| `\bCZ\b` | Czech |
| `\bPL\b` | Polish |
| `\bBG\b` | Bulgarian |
| `\bSK\b` | Slovak |
| `\bDE\b` | German |
| `\bES\b` (not after DTS) | Spanish |

### String Match (40+ languages)
english, spanish, danish, dutch, japanese, icelandic, mandarin, cantonese, chinese,
korean, russian, romanian, hindi, arabic, thai, bulgarian, polish, vietnamese,
swedish, norwegian, finnish, turkish, portuguese, brazilian, hungarian, hebrew,
ukrainian, persian, bengali, slovak, latvian, latino, tamil, telugu, malayalam,
kannada, albanian, afrikaans, marathi, tagalog

## SimpleTitleRegex (Tags Stripped for Matching)

These tokens are stripped from titles when doing fuzzy matching:

**Resolutions:** 480p, 540p, 576p, 720p, 1080p, 2160p (and `i` variants)
**Codecs:** x264, x265, h264, h265
**Audio:** DD 5.1, DD5.1
**Bit depth:** 8bit, 10bit, 10-bit
**Dimensions:** 848x480, 1280x720, 1920x1080, 3840x2160, 4096x2160

## Hash/Junk Release Rejection Patterns

Releases matching these are rejected as invalid:
- 32-char alphanumeric (MD5 hash)
- 24-char lowercase alphanumeric
- `[A-Z]{11}\d{3}` (NZBGeek)
- `[a-z]{12}\d{3}`
- Known junk: `123`, `abc`, `b00bs`, `abc[-_.]xyz`
