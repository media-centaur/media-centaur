
# TV and Series Episode Naming Patterns

This document catalogs every episode identification pattern found in video
release filenames — the formats used by scene groups, P2P releasers, anime
fansubbers, and media server conventions.

## 1. Standard Season+Episode Format (S##E##)

The dominant and most universally recognized pattern. Case-insensitive.

### 1.1 Basic Patterns

| Pattern | Example | Notes |
|---------|---------|-------|
| `S01E01` | `Sample.Show.Eight.S01E01.Pilot.720p.BluRay.x264-GROUP` | Canonical scene format |
| `s01e01` | `breaking.bad.s01e01.pilot.720p.bluray.x264-group` | Lowercase variant |
| `S1E1` | `Show.Name.S1E1.Episode.Title` | No zero-padding (less common) |
| `S01E001` | `Anime.Name.S01E001.Title` | 3-digit episode (long-running shows) |

### 1.2 Delimiter Variations

All of these are equivalent and recognized by major parsers:

```
Show.Name.S01E01           # dots (scene standard)
Show Name S01E01           # spaces (P2P / media server)
Show_Name_S01E01           # underscores (legacy / some P2P)
Show.Name.s01e01           # lowercase
Show.Name.S01.E01          # dot between S and E
Show.Name.s01_e01          # underscore between S and E
show name - s01e01         # dash-separated (Plex recommended)
Show.Name.-.S01E01         # dot-dash-dot
```

### 1.3 With Episode Title

The episode title appears after the episode number and before technical tags:

```
Sample.Show.Eight.S01E01.Pilot.720p.BluRay.x264-GROUP
Sample.Show.S01E01.The.Target.1080p.AMZN.WEB-DL.DD5.1.H.264-GROUP
```

## 2. Multi-Episode Patterns

When a single file contains multiple consecutive episodes.

### 2.1 Hyphen Range

```
S01E01-E03             # episodes 1 through 3
S01E01-E02             # two-parter
s01e09-e10             # lowercase
```

Full filename: `Game.of.Thrones.S04E09-E10.1080p.BluRay.x264-GROUP`

### 2.2 Concatenated Episode Numbers

```
S01E01E02              # no separator
S01E01E02E03           # triple episode
s01e01e02              # lowercase
```

Full filename: `Show.Name.S01E01E02.Episode.Title.720p.HDTV.x264-GROUP`

### 2.3 Cross-Season Multi-Episode (Rare)

```
S01E10-S02E01          # season finale + premiere in one file
```

This is uncommon and poorly supported by most parsers.

## 3. Alternative Season+Episode Formats

### 3.1 The 1x01 Format

An older convention still common in some communities:

| Pattern | Example |
|---------|---------|
| `1x01` | `Show.Name.1x01.Episode.Title.avi` |
| `01x01` | `Show.Name.01x01.Episode.Title.avi` |
| `1x001` | `Anime.Name.1x001.avi` |

Multi-episode: `1x01-1x02`, `1x01x02`

### 3.2 Bare Season and Episode Numbers

Sometimes found in poorly named files or user-organized libraries:

```
Show Name 101              # season 1, episode 01 (ambiguous)
Show Name 0101             # season 01, episode 01
Show Name Season 1 Episode 1
```

These are highly ambiguous and unreliable for parsing. A number like `101`
could mean S01E01, S10E01, or episode 101 (absolute). Parsers should treat
these as low-confidence matches.

### 3.3 "Episode" / "Ep" Prefix

```
Show.Name.Episode.01       # no season
Show.Name.Ep01             # abbreviated
Show.Name.Ep.01            # with dot
Show.Name.E01              # bare E prefix (ambiguous)
```

When no season is specified, parsers typically assume Season 1.

## 4. Date-Based Episodes

Used for daily shows, talk shows, news programs, and sports. The date
replaces the season+episode identifier entirely.

### 4.1 Patterns

| Pattern | Example |
|---------|---------|
| `YYYY-MM-DD` | `The.Daily.Show.2024-03-15.720p.WEB.h264-GROUP` |
| `YYYY.MM.DD` | `The.Daily.Show.2024.03.15.720p.WEB.h264-GROUP` |
| `YYYY MM DD` | `The Daily Show 2024 03 15 720p` |
| `DD.MM.YYYY` | `Show.Name.15.03.2024.720p` (European) |
| `DD-MM-YYYY` | `Show.Name.15-03-2024.720p` |

### 4.2 Scene Standard for Daily Shows

Scene releases use the same dot-delimited structure but with the date
replacing S##E##:

```
Show.Name.2024.03.15.720p.HDTV.x264-GROUP
The.Late.Show.with.Stephen.Colbert.2024.03.15.John.Oliver.1080p.WEB.h264-GROUP
```

The guest name or episode topic sometimes appears after the date, functioning
as an episode title.

### 4.3 Ambiguity with Movie Year

A date-based episode like `Show.Name.2024.03.15` can conflict with a movie
title containing a year: `Movie.Name.2024`. Parsers resolve this by:

- Checking if three number groups follow the potential year (YYYY.MM.DD)
- Validating that the numbers form a plausible date (month 01-12, day 01-31)
- Using context: known show names, presence of season folders

## 5. Absolute Episode Numbering

Used primarily for anime and long-running series that do not reset episode
counts per season.

### 5.1 Patterns

```
Show.Name.001.720p.BluRay.x264-GROUP       # zero-padded 3 digits
Show.Name.01.720p.BluRay.x264-GROUP        # zero-padded 2 digits
Show.Name.-.001.720p                        # dash-separated
[Group] Show Name - 001 [720p].mkv         # anime fansub style
[Group] Show Name - 001v2 [720p].mkv       # with version tag
```

### 5.2 Mapping to Season+Episode

Media servers (Plex, Kodi, Emby) can map absolute numbers to season+episode
using TVDB or AniDB ordering. For example, absolute episode 150 of Naruto
maps to a specific season and episode in the TVDB scheme.

### 5.3 Dual Numbering

Some releases include both absolute and season-based numbers:

```
Show.Name.S03E04.054.720p.BluRay.x264-GROUP
[Group] Show Name - S03E04 (54) [720p].mkv
```

## 6. Anime-Specific Patterns

Anime releases have distinctive naming conventions that differ significantly
from Western scene releases. See `filename-structure-conventions.md` section
11 for the full structural format.

### 6.1 Fansub Format

```
[Group] Anime Name - 01 [Quality].mkv
[Group] Anime Name - 01 (BD 1080p HEVC FLAC) [CRC32].mkv
[Group] Anime Name - S01E01 - Episode Title (BD 1080p HEVC Opus) [Dual Audio] [CRC32].mkv
```

Key characteristics:

- **Group tag at the beginning** in square brackets
- **Absolute episode numbering** is the default (not S##E##)
- **CRC32 checksum** in square brackets at the end (8-character hex, e.g., `[CF1029D9]`)
- **Quality/codec info** in parentheses
- **Spaces** as word delimiters, not dots
- **Hyphens** separate the title from the episode number

### 6.2 Version Tags

When a release is revised (fixing errors, improving quality), anime groups
append a version number:

```
[Group] Anime Name - 01v2 [720p].mkv       # version 2
[Group] Anime Name - 01v3 [720p].mkv       # version 3
Show.Name.S01E01v2.720p.BluRay.x264-GROUP   # scene-style with version
```

Version 1 is implied and never written. `v2` indicates a corrected release.

### 6.3 Specials and OVAs

Specials, OVAs (Original Video Animations), ONAs (Original Net Animations),
and other non-episode content are numbered under Season 0:

```
[Group] Anime Name - S00E01 - OVA Title [1080p].mkv
[Group] Anime Name - S00E04 - Special Title [720p].mkv
Anime.Name.S00E01.OVA.1080p.BluRay.x264-GROUP
```

`S00` is the universal convention for specials across all media servers.

### 6.4 Batch/Volume Releases

Anime groups sometimes release episodes in batches:

```
[Group] Anime Name - 01-12 (BD 1080p) [CRC32].mkv     # batch file
[Group] Anime Name (Season 1) [BD 1080p]                # season folder
```

### 6.5 Decimal Episodes (Rare)

Some anime have ".5" episodes (recap or interlude episodes):

```
[Group] Anime Name - 18.5 [720p].mkv
```

This is discouraged by modern naming guides in favor of S00EXX notation, but
it exists in the wild.

## 7. Season Packs and Complete Series

### 7.1 Full Season

When an entire season is released as a single directory:

```
Show.Name.S01.720p.BluRay.x264-GROUP/
Show.Name.S01.COMPLETE.720p.BluRay.x264-GROUP/
Show.Name.Season.1.1080p.WEB-DL-GROUP/
```

Individual files within the directory use standard S##E## naming.

### 7.2 Complete Series

```
Show.Name.COMPLETE.SERIES.720p.BluRay.x264-GROUP/
Show.Name.S01-S05.1080p.BluRay.x264-GROUP/
```

### 7.3 Season-Only Marker (No Episode)

A filename with only a season number and no episode:

```
Show.Name.S01.720p.BluRay.x264-GROUP.mkv
```

This typically indicates a season pack directory name, not a single-file
release. A single file with only `S01` and no episode is unusual.

## 8. Miniseries and Part Numbering

### 8.1 Part Numbers

Used for miniseries that are not divided into traditional seasons:

```
Show.Name.Part.1.720p.HDTV.x264-GROUP
Show.Name.Part1.720p.HDTV.x264-GROUP
Show.Name.Part.One.720p.HDTV.x264-GROUP
Show.Name.Pt.1.720p.HDTV.x264-GROUP
```

### 8.2 Parts within Episodes

A single episode split across multiple files:

```
Show.Name.S01E01.Part1.720p.HDTV.x264-GROUP
Show.Name.S01E01.pt1.mkv
Show.Name.S01E01.cd1.avi
Show.Name.S01E01.disc1.mkv
```

Recognized split identifiers: `cd`, `disc`, `disk`, `dvd`, `part`, `pt`
(each followed by a number).

## 9. Special Episode Markers

GuessIt and media servers recognize these episode detail markers:

| Marker | Meaning |
|--------|---------|
| `Pilot` | Pilot episode |
| `Final` | Series finale |
| `Special` | Special episode |
| `Unaired` | Unaired episode |
| `Minisode` | Minisode format |

These typically appear in the episode title position:

```
Show.Name.S01E00.Pilot.720p.HDTV.x264-GROUP
Show.Name.S05E16.Final.Episode.720p.BluRay.x264-GROUP
```

## 10. Edge Cases and Ambiguities

### 10.1 Year in Show Title

Shows with years in their title create ambiguity:

```
2001.A.Space.Odyssey.1968.1080p.BluRay.x264-GROUP    # movie (year is 1968)
The.100.S01E01.720p.WEB-DL-GROUP                     # "100" is part of the title
24.S01E01.720p.HDTV.x264-GROUP                       # "24" is the title
1883.S01E01.1080p.WEB.H264-GROUP                     # "1883" is the show title
```

Parsers handle this by checking whether a 4-digit number followed by
season/episode markers is more likely a year or a title.

### 10.2 Shows with Numbers

```
9-1-1.S01E01.720p.FOX.WEB-DL-GROUP
30.Rock.S01E01.720p.HDTV.x264-GROUP
90210.S01E01.720p.CW.WEB-DL-GROUP
```

### 10.3 Multi-Season Episode (Very Rare)

Some releases span season boundaries:

```
Show.Name.S01E10-S02E01.720p.WEB-DL-GROUP
```

This is poorly supported and rarely encountered.

### 10.4 Absent Season

When no season information is present:

```
Show.Name.E01.720p.WEB-DL-GROUP
Show.Name.Episode.1.720p.WEB-DL-GROUP
```

Most parsers default to Season 1 when only an episode number is found.

### 10.5 Episode Titles Containing Numbers

```
Sample.Show.Eight.S02E10.Over.720p.BluRay.x264-GROUP         # "Over" is the title
The.100.S03E07.Thirteen.720p.WEB-DL-GROUP                # "Thirteen" is the title
Lost.S04E05.The.Constant.720p.BluRay.x264-GROUP          # no number confusion
Stranger.Things.S04E04.Chapter.Four.720p.NF.WEB-DL-GROUP # "Chapter Four" in title
```

### 10.6 Disc-Based Numbering

DVD and Blu-ray rips sometimes use disc numbering:

```
Show.Name.D01.720p.BluRay.x264-GROUP      # Disc 1
Show.Name.Disc.1.720p.BluRay-GROUP
```

This does not map to episode numbers — a disc may contain multiple episodes.

## 11. Parser Priority Order

When multiple patterns could match, parsers should evaluate in this order
(highest confidence first):

1. **S##E##** — standard season+episode (`S01E01`, `S01E01E02`, `S01E01-E03`)
2. **Date** — `YYYY.MM.DD` or `DD.MM.YYYY` (3 number groups forming valid date)
3. **##x##** — alternative season+episode (`1x01`, `01x01`)
4. **Absolute number** — bare episode number with no season context
5. **Part** — `Part.1`, `Part.One`
6. **Episode keyword** — `Episode.1`, `Ep.1`, `E01`
7. **Bare number** — `101` (lowest confidence, highly ambiguous)

Higher-numbered patterns should only be used when no higher-priority pattern
matches. If both S##E## and a date are present, S##E## takes precedence for
the episode identification.

## 12. Regex Reference

Common regex patterns for matching episode identifiers:

```
# S01E01 (with optional multi-episode)
[Ss](\d{1,2})\s*[Ee](\d{1,3})(?:\s*-?\s*[Ee](\d{1,3}))*

# 1x01
(\d{1,2})[xX](\d{2,3})

# Date YYYY-MM-DD (any separator)
(\d{4})[\.\-\s](\d{2})[\.\-\s](\d{2})

# Absolute episode (anime, preceded by dash or space)
(?:^|[\s\-])(\d{2,4})(?:v\d)?(?:\s|$|\[|\()

# Version tag (anime)
[Vv](\d)

# CRC32 (anime)
\[([0-9A-Fa-f]{8})\]

# Season pack (no episode)
[Ss](\d{1,2})(?:\s*[-\.]\s*[Ss](\d{1,2}))?(?!.*[Ee]\d)

# Part number
[Pp](?:ar)?t\s*\.?\s*(\d{1,2}|[Oo]ne|[Tt]wo|[Tt]hree|[Ff]our|[Ff]ive|[Ss]ix)
```

These are simplified reference patterns. Production parsers need additional
context handling (e.g., ensuring a date pattern is not preceded by `S` which
would indicate S##E## instead).
