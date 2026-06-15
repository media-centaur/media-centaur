---
title: How identification works
part: Your library
slug: how-identification-works
order: 4
---
When a new file is detected in a watched directory, it's processed automatically through
the ingestion pipeline. The pipeline reads the file and folder names, searches TMDB for a
match, and — if it's confident enough — adds the file to your library as a new entry. The
artwork is fetched separately, just after. Three stages run in order: parse, match, then
ingest.

Understanding those stages is most of what you need when a title shows up in the wrong
place, or doesn't show up at all.

## Parsing the filename

Parsing reads a title, a year, and — for episodes — a season and episode number out of the
file and folder names. It's a series of string-matching algorithms against known release
formats, so the more standard the name, the better it does:

- Movies: `Movie Name (2024).mkv` or `Movie.Name.2024.1080p.BluRay.x264-GROUP.mkv`
- Episodes: `Show.Name.S01E05.Title.1080p.mkv`, and the alternates `Show 7x02 - Title` and `Show Season 5 Episode 1 - Title`
- Quality tags, release-group suffixes, bracketed junk, and `www.` URL prefixes are stripped before matching

It also reads folder context: a year on the parent folder fills in a missing episode year,
and files under an `Extras` or `Featurettes` folder are tied to their parent title rather
than imported as separate entries. Parsing is deliberately conservative — faced with an
ambiguous name, it would rather hand TMDB a clean partial guess than a confident wrong one.

The [parser source is here](https://github.com/media-centaur/media-centaur/blob/main/lib/media_centaur/parser.ex).
If you have a filename that wasn't parsed correctly,
[open an issue](https://github.com/media-centaur/media-centaur/issues/new) with the name so
the parser can be improved.

## Matching against TMDB

The parsed title and year are searched against TMDB, and each candidate is scored for
confidence — how closely the titles match, whether the years agree, and where the result
ranked in the search. A file is added to your library automatically only when the best
candidate scores above the auto-approve threshold. When several candidates tie, the match
is auto-approved only if the parsed year picks a clear winner.

> [!TIP]
> Files whose names the parser can't classify aren't dropped — they're searched against
> both movies *and* TV at once, and the higher-scoring result wins. An oddly-named file can
> still identify itself as long as it exists in TMDB.

The [scoring and threshold live here](https://github.com/media-centaur/media-centaur/blob/main/lib/media_centaur/tmdb/confidence.ex).

## When a match isn't confident

Anything that doesn't clear the threshold — a low score, no TMDB results, or an unresolved
tie — lands in the Review queue instead of being guessed at. There you can accept one of the
suggested matches, or search TMDB yourself and pick the right title by hand. A file already
in your library can be sent back for re-matching from its detail page if it was identified
wrongly.

## What you get once a file is identified

Identification is also when Media Centaur learns about the *inside* of the file. If
[ffprobe](https://github.com/media-centaur/media-centaur/blob/main/lib/media_centaur/subtitles/detector/ffprobe.ex)
is configured, it reads the embedded subtitle tracks and their languages at import time, on
top of any sidecar `.srt` / `.ass` files sitting next to the video. That's what lets track
selection show each subtitle's language and pick one for you during playback. Without
ffprobe nothing breaks — you just get sidecar subtitles only. If you've never set up
ffprobe, this is the most common capability people are leaving on the table.

In short: name your files in a standard way and they identify themselves, with their tracks
read in; anything ambiguous waits for you in the Review queue rather than being guessed at;
and configuring ffprobe unlocks language-aware track selection you may not be getting today.
