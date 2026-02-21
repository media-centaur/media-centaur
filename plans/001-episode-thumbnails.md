# 001 — Episode Thumbnails

## Context

The user interface's TV Series detail view supports displaying episode thumbnail
images when they are present in the `image` array on each episode in
`media.json`. Currently, episodes are serialized without any `image` field — the
Episode resource has no image relationship, the TMDB integration does not fetch
episode stills, the image downloader does not process episode-level images, and
the serializer omits the field entirely.

The result is that every episode in the UI falls back to a plain number badge
instead of showing a visual thumbnail.

## Goal

Populate episode thumbnail images end-to-end: fetch episode still images from
TMDB, download them to the local image cache, and include them in `media.json`
so the user interface can display them.

## What's Needed

### 1. Episode image storage

Episodes need a way to store image references (at minimum a "thumb" role) the
same way entities and movies already store poster/backdrop/logo images.

### 2. TMDB episode still fetching

TMDB provides episode still images via the TV Episode endpoint. When scraping a
TV series, episode stills should be fetched for each episode and associated with
the episode record.

### 3. Image downloading for episodes

The image download pipeline currently handles entity-level and movie-level
images. It needs to also iterate over episode images and download them to the
local cache, following the same conventions (relative `contentUrl` path, file
on disk).

### 4. Serialization

The episode serializer needs to include the `image` field in the same
`ImageObject` format used elsewhere (`name`, `url`, `contentUrl`), so the user
interface can resolve and display the thumbnails.

## Expected Output

Each episode in `media.json` should include an `image` array when a thumbnail
is available:

```json
{
  "episodeNumber": 1,
  "name": "Good News About Hell",
  "duration": "PT55M",
  "image": [
    {
      "@type": "ImageObject",
      "name": "thumb",
      "url": "https://image.tmdb.org/t/p/...",
      "contentUrl": "images/<entity-id>/s01e01-thumb.jpg"
    }
  ]
}
```

The user interface already handles this format — no UI changes are required.
