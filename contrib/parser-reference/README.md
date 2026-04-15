# Parser Reference

Reference documents gathered during development of the Media Centaur filename parser (`lib/media_centaur/parser.ex`). They cover the naming conventions, tag vocabularies, and scene standards that real-world video filenames follow, as well as notes on how existing open-source parsers handle these patterns.

## Contents

| File | What it covers |
|------|----------------|
| `filename-structure-conventions.md` | General release filename anatomy — field order, separators, and conventions across media types |
| `tv-episode-naming-patterns.md` | Season/episode numbering patterns (SxxExx, date-based, multi-episode, etc.) |
| `scene-rules-naming-reference.md` | Consolidated quick-reference extracted from all scenerules.org standards |
| `scene-rules-bluray-2014.md` | Complete Blu-ray releasing standards (2014) |
| `scene-rules-hd-tv-x264-2016.md` | 720p TV x264 releasing standards (2016) |
| `scene-rules-sd-tv-x264-2016.md` | SD TV x264 releasing standards (2016) |
| `scene-rules-sd-x264-movies-2013.md` | SD x264 movie releasing standards v1.1 (2013) |
| `scene-rules-hd-uhd-x264-x265-rev5.md` | HD/UHD x264/x265 releasing standards rev 5.0 (2020) |
| `scene-rules-web-webrip-2020.md` | WEB and WEBRip releasing standards v2.0 (2020) |
| `encoding-standards-x264-hd-hungarian.md` | Hungarian HD x264 release rules (non-English scene variant) |
| `codec-quality-tags.md` | Video/audio codec tags, HDR formats, resolution tags, and source types |
| `release-edition-tags.md` | Edition tags (Director's Cut, Extended, IMAX, etc.) and release quality tags (PROPER, REPACK, etc.) |
| `streaming-service-tags.md` | Streaming service abbreviation tags (AMZN, NF, DSNP, etc.) for WEB-DL releases |
| `parser-reference-guessit.md` | How guessit (Python) parses video filenames — patterns and field definitions |
| `parser-reference-sonarr-radarr.md` | How Sonarr and Radarr (C#) parse quality, tags, and language from filenames |
| `parser-reference-other.md` | PTN and parse-torrent-title — lightweight parsers and their pattern sets |

## Notes

The `scene-rules-*.md` and `encoding-standards-*.md` files are reference copies of publicly available scene standards documents. Each file includes a source URL. These are provided as-is for research purposes — the actual parser logic in `parser.ex` is original code informed by (but not derived from) these documents.
