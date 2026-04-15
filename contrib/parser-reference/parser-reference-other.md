
# Other Video Filename Parsers

> Source: https://github.com/divijbindlish/parse-torrent-name (PTN, Python)
> Source: https://github.com/TheBeastLT/parse-torrent-title (parse-torrent-title, JavaScript)


## PTN - Parse Torrent Name (Python)

Original lightweight torrent name parser. 23 pattern fields.

### Pattern Definitions

| Field | Regex | Type |
|-------|-------|------|
| season | `s?([0-9]{1,2})[ex]` | integer |
| episode | `[ex]([0-9]{2})(?:[^0-9]\|$)` | integer |
| year | `[\[\(]?((?:19[0-9]\|20[01])[0-9])[\]\)]?` | integer |
| resolution | `[0-9]{3,4}p` | string |
| quality | see below | string |
| codec | `xvid\|[hx]\.?26[45]` | string |
| audio | see below | string |
| group | `- ?([^-]+(?:-={[^-]+-?$)?)$` | string |
| region | `R[0-9]` | string |
| extended | `EXTENDED(:?.CUT)?` | boolean |
| hardcoded | `HC` | boolean |
| proper | `PROPER` | boolean |
| repack | `REPACK` | boolean |
| container | `MKV\|AVI\|MP4` | string |
| widescreen | `WS` | boolean |
| website | `^\[ ?([^\]]+?) ?\]` | string |
| language | `rus\.eng\|ita\.eng` | string |
| sbs | `(?:Half-)?SBS` | string |
| unrated | `UNRATED` | boolean |
| size | `\d+(?:\.\d+)?(?:GB\|MB)` | string |
| 3d | `3D` | boolean |

### Quality Values (PTN)

Matched by a single alternation regex:
- `HDTV`
- `CAM`, `HDCAM`
- `TS`, `TELESYNC`
- `TC`, `TELECINE`
- `PPVRip`
- `R5`
- `SCR`, `SCREENER`, `DVDSCR`
- `BluRay`, `Blu-Ray`
- `BDRip`, `BRRip`
- `DVDRip`
- `DVDR`
- `DVD`
- `HDRip`
- `WEB-DL`, `WEBDL`, `WEBRip`, `WEB`
- `PDTV`, `SDTV`

### Audio Values (PTN)

- `MP3`
- `DD5.1`, `DD 5.1`
- `Dual Audio`, `Dual-Audio`
- `DTS`
- `AAC`, `AAC2.0`, `AAC 2.0`
- `AC3`, `AC-3`

---

## parse-torrent-title (JavaScript)

More comprehensive JavaScript parser by TheBeastLT. Handles 50+ fields with
extensive pattern matching.

### Resolution Detection

| Pattern | Value |
|---------|-------|
| `4k`, `2160p`, `3840x####` | 2160p |
| `1920x####`, `1080p` | 1080p |
| `1280x####`, `720p` | 720p |
| `480p` | 480p |
| `576p` | 576p |

### Source / Quality Detection

| Pattern | Value |
|---------|-------|
| `camera`, `HD-CAM`, `HDCAM` | CAM |
| `TS`, `TELE-SYNC`, `TELESYNC`, `PDVD`, `PreDVD` | TeleSync |
| `TC`, `TELE-CINE`, `TELECINE` | TeleCine |
| BD/BR + REMUX combinations | BluRay REMUX |
| `Blu-Ray`, `BluRay`, `BDR`, `BD` | BluRay |
| `UHDRip` | UHDRip |
| `HDRip` | HDRip |
| `BRRip` | BRRip |
| `BDRip` | BDRip |
| `DVDRip` | DVDRip |
| `SCR`, `SCREENER`, `DVDSCR` | SCR |
| `DVD`, `DVD-R`, `DVDR` | DVD |
| `PPVRip` | PPVRip |
| `HDTV` | HDTV |
| `SATRip` | SATRip |
| `TVRip` | TVRip |
| `R5` | R5 |
| `WEB-DL`, `WEBDL`, `WEB DL` | WEB-DL |
| `WEBRip`, `WEB-Rip` | WEBRip |
| `PDTV` | PDTV |
| `SDTV` | SDTV |

### Video Codec Detection

| Pattern | Value |
|---------|-------|
| `x264`, `x.264` | x264 |
| `h264`, `h.264` | h264 |
| `x265`, `x.265` | x265 |
| `h265`, `h.265` | h265 |
| `hevc` | hevc |
| `divx` | divx |
| `xvid` | xvid |
| `mpeg2`, `mpeg-2` | mpeg2 |
| `avc` | avc |

### Bit Depth

| Pattern | Value |
|---------|-------|
| `8bit`, `8-bit` | 8bit |
| `10bit`, `10-bit`, `hi10`, `hi10p` | 10bit |
| `12bit`, `12-bit` | 12bit |
| `hevc 10` (combined) | 10bit |
| `hdr10` (also extracts HDR) | 10bit |

### HDR Detection

| Pattern | Value |
|---------|-------|
| `Dolby Vision`, `DV`, `DoVi` | Dolby Vision |
| `HDR10+`, `HDR10Plus` | HDR10+ |
| `HDR`, `HDR10` | HDR |

### 3D Formats

| Pattern | Value |
|---------|-------|
| `Half-SBS`, `HSBS` | 3D HSBS |
| `SBS`, `Full-SBS` | 3D SBS |
| `Half-OU`, `HOU` | 3D HOU |
| `OU`, `Over-Under` | 3D OU |
| `3D` | 3D |

### Audio Detection

| Pattern | Value |
|---------|-------|
| `7.1 Atmos`, `Atmos 7.1` | Dolby Atmos 7.1 |
| `Atmos` | Dolby Atmos |
| `flac` | FLAC |
| `eac3`, `e-ac3`, `e-ac-3` | EAC3 |
| `ac3`, `ac-3` | AC3 |
| `dd5.1`, `dd 5.1` | DD5.1 |
| `aac2.0`, `aac 2.0` | AAC |
| `aac` | AAC |
| `mp3` | MP3 |
| `dts-hd`, `dts hd` | DTS-HD |
| `dts-hdma`, `dts hd ma` | DTS-HD MA |
| `truehd`, `true-hd` | TrueHD |
| `dts` | DTS |
| `dual audio`, `dual-audio` | Dual Audio |

### Quality Flags (Boolean)

| Pattern | Field |
|---------|-------|
| `EXTENDED`, `- Extended` | extended |
| `CONVERT` | convert |
| `HC`, `HARDCODED` | hardcoded |
| `PROPER`, `REAL.PROPER` | proper |
| `REPACK`, `RERIP` | repack |
| `Retail` | retail |
| `Remaster`, `REKONSTRUKCJA` | remastered |
| `unrated`, `uncensored` | unrated |

### Language Detection (50+ languages)

Detected languages with their patterns:
- **English:** `english`, `eng`, `en`
- **Japanese:** `japanese`, `jpn`, `jp`
- **Korean:** `korean`, `kor`, `kr`
- **Chinese:** `chinese`, `mandarin`, `taiwanese`, `cantonese`, `chi`, `cn`
- **French:** `french`, `fra`, `fre`, `fr`, `vf`, `vff`, `truefrench`
- **Spanish:** `spanish`, `espanol`, `castellano`, `spa`, `es`, `latino`
- **German:** `german`, `deutsch`, `ger`, `de`
- **Italian:** `italian`, `ita`, `it`
- **Portuguese:** `portuguese`, `por`, `pt`, `pt-br`, `brazilian`
- **Russian:** `russian`, `rus`, `ru`
- **Dutch:** `dutch`, `nld`, `nl`, `flemish`
- **Polish:** `polish`, `pol`, `pl`, `pldub`, `dubpl`
- **Hindi:** `hindi`, `hin`, `hi`
- **Arabic:** `arabic`, `ara`, `ar`
- **Turkish:** `turkish`, `tur`, `tr`
- **Swedish:** `swedish`, `swe`, `sv`
- **Norwegian:** `norwegian`, `nor`, `no`
- **Danish:** `danish`, `dan`, `da`
- **Finnish:** `finnish`, `fin`, `fi`
- **Thai:** `thai`, `tha`, `th`
- **Vietnamese:** `vietnamese`, `vie`, `vi`
- **Romanian:** `romanian`, `ron`, `ro`
- **Hungarian:** `hungarian`, `hun`, `hu`
- **Czech:** `czech`, `ces`, `cz`
- **Greek:** `greek`, `ell`, `el`
- **Hebrew:** `hebrew`, `heb`, `he`
- **Ukrainian:** `ukrainian`, `ukr`, `uk`
- **Bulgarian:** `bulgarian`, `bul`, `bg`
- **Slovak:** `slovak`, `slk`, `sk`
- **Croatian:** `croatian`, `hrv`, `hr`
- **Serbian:** `serbian`, `srp`, `sr`
- **Slovenian:** `slovenian`, `slv`, `sl`
- **Estonian:** `estonian`, `est`, `et`
- **Latvian:** `latvian`, `lav`, `lv`
- **Lithuanian:** `lithuanian`, `lit`, `lt`
- **Tamil:** `tamil`, `tam`, `ta`
- **Telugu:** `telugu`, `tel`, `te`
- **Malayalam:** `malayalam`, `mal`, `ml`
- **Kannada:** `kannada`, `kan`, `kn`
- **Bengali:** `bengali`, `ben`, `bn`
- **Malay:** `malay`, `msa`, `ms`
- **Indonesian:** `indonesian`, `ind`, `id`
- **Persian/Farsi:** `persian`, `farsi`, `fas`, `fa`
- **Catalan:** `catalan`, `cat`, `ca`
- **Tagalog/Filipino:** `tagalog`, `filipino`, `tgl`, `fil`
- Special: `multi audio`, `multi-audio`, `dual audio`, `dual-audio`, `multi subs`

### Container Detection

Recognized: `mkv`, `avi`, `mp4`, `wmv`, `mpg`, `mpeg`

### Complete Collection Detection

Patterns matched:
- `complete series`, `complete collection`
- `box set`, `boxset`
- `collection`
- `trilogy`
- `anthology`
- `complete`

### Season/Episode Formats

- `S01E05` (standard)
- `1x05` (compact)
- `S01E05E06` (multi-episode)
- `S01E05-E08` (range)
- `S01` (season only)
- Cyrillic season markers (Russian releases)
- Spanish ordinal season markers

### Release Group Extraction

- Prefix: `[GROUP]` at start
- Suffix: `-GROUP` at end or `(GROUP)` at end

---

## Cross-Parser Tag Consensus

Tags recognized by ALL major parsers (highest confidence for stripping):

### Universal Resolution Tags
`360p`, `480p`, `540p`, `576p`, `720p`, `1080p`, `2160p`, `4K`

### Universal Source Tags
`CAM`, `TS`/`TELESYNC`, `TC`/`TELECINE`, `SCR`/`SCREENER`, `DVDSCR`,
`DVD`, `DVDRip`, `DVDR`, `BDRip`, `BRRip`, `BluRay`/`Blu-Ray`,
`HDTV`, `PDTV`, `SDTV`, `WEB-DL`/`WEBDL`, `WEBRip`, `HDRip`

### Universal Codec Tags
`x264`, `x265`, `h264`, `h265`, `HEVC`, `XviD`, `DivX`

### Universal Audio Tags
`AC3`, `AAC`, `DTS`, `DD5.1`, `MP3`, `FLAC`, `TrueHD`

### Universal Modifier Tags
`PROPER`, `REPACK`, `RERIP`, `EXTENDED`, `UNRATED`, `REMUX`,
`3D`, `HC` (hardcoded subs), `INTERNAL`

### Universal Container Formats
`mkv`, `avi`, `mp4`, `wmv`, `mpg`/`mpeg`
