---
title: Moving & relinking media
part: Your library
slug: moving-and-relinking-media
order: 7
---
Library entries are linked to files on disk. Move those files and that link would normally
break — leaving the old entry orphaned and the moved file re-imported as something new.
Media Centaur tries to avoid that: when it sees a file appear where one disappeared, it
re-attaches it to the existing entry instead of starting over.

## How a move is recognised

The match is made on two signals together: the file's **path relative to its media
directory** and its **size in bytes**. If a file shows up whose relative path and size match
one that's gone from disk, it's treated as the same file moved, and the entry — with its
metadata, artwork, and watch progress — is re-pointed at the new location.

Because the path is measured *relative to the media directory*, the absolute path can change
completely. That's what makes the next part work.

## Moving to a new drive

Moving your whole library to a new drive keeps every entry intact, as long as you preserve
the folder structure underneath the media directory. The media directory's own path changes
(say `/mnt/old/media` becomes `/mnt/new/media`), but `movies/Some Film (2024).mkv` is still
`movies/Some Film (2024).mkv` underneath it, and the sizes are unchanged — so the next scan
re-links everything rather than re-importing it.

## What breaks the link

Relinking is deliberately conservative — it only fires when it's sure. These changes look
like a *new* file, not a move, and will be imported fresh:

- **Renaming** a file or a folder — the relative path no longer matches.
- **Re-encoding** a file — the size changes, so it's treated as genuinely different.
- **Restructuring** the folders under the media directory — same reason as a rename.

This is a safety trade: matching on path-and-size never mistakes two different files for the
same one. Renames and re-encodes are out of scope by design, not by oversight.

## Offline drives are safe

A disconnected drive does not wipe its titles. The library tracks when each file was last
seen and only cleans up entries after a configurable grace period — and only once the drive
is confirmed back and available, never while it's merely unmounted. Unplug a drive, take
your time, plug it back in, and its titles are still there.

> [!TIP]
> The safe way to reorganise a library: move whole folders with their structure intact, and
> let the next scan re-link them. The unsafe ways all change one of the two signals — rename
> the files, flatten the folders, or re-encode in place — so do those *before* a title is in
> the library, not after.

In short: moves re-link by relative path plus size, a whole-drive move survives if you keep
the structure, renames/re-encodes count as new files, and an offline drive is held — not
deleted — until it's back.
