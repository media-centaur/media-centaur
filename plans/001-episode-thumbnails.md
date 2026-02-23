# 001 — Episode Thumbnails

> **Status: Completed.** All four components are implemented. Episode thumbnails
> flow end-to-end through the pipeline and are pushed to the UI via Phoenix
> Channels.

## Context

The user interface's TV Series detail view supports displaying episode thumbnail
images when they are present in the `image` array on each episode. This plan
tracked the work to populate those thumbnails end-to-end.

## What Was Implemented

1. **Episode image storage** — `Episode` has a `has_many :images, Image`
   relationship. Images are preloaded via `Entity`'s `:with_associations` action.
2. **TMDB episode still fetching** — `TMDB.Mapper` creates `"thumb"` role
   images for each episode from TMDB's `still_path` field.
3. **Image downloading** — `Pipeline.ImageDownloader.download_all/1` iterates
   over episode images and downloads them to the local cache.
4. **Serialization** — `Serializer.serialize_episode/1` includes the `image`
   array in the same `ImageObject` format used elsewhere.
