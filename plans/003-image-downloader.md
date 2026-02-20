# 003 — Image Downloader

## Goal

Build a module that downloads images from remote TMDB URLs to the local data directory, updates each `Image` record's `content_url` with the local relative path, and transitions `WatchedFile` from `:fetching_images` → `:complete`.

## Current State

- `FetchMetadata` creates `Image` records with `url` (remote TMDB URL) and `content_url: nil`.
- Image roles: `"poster"`, `"backdrop"`, `"logo"` — created from TMDB API data.
- Extension is stored on each `Image` record (always `"jpg"` currently).
- After metadata fetch, `WatchedFile` lands in `:fetching_images` state. Nothing happens next.
- The `IMAGE-CACHING.md` spec defines the local path format: `{entity-uuid}/{role}.{ext}` relative to `media_images_dir`.
- The project uses `Req` for all HTTP requests (architecture principle).

## Design

### New module: `MediaManager.ImageDownloader`

A simple functional module (not a GenServer) that:

1. Takes an entity (with loaded images).
2. For each image with a `url` and no `content_url`, downloads the file.
3. Writes to `{media_images_dir}/{entity.id}/{role}.{ext}`.
4. Updates the `Image` record's `content_url` with the relative path `{entity.id}/{role}.{ext}`.

### New Ash action: `:download_images` on `WatchedFile`

An update action that:

1. Loads the associated entity with images.
2. Calls `ImageDownloader.download_all/1`.
3. Transitions state to `:complete` on success, `:error` on failure.

### Wiring via `after_action` on `:fetch_metadata`

Following the pattern from plan 002, add an `after_action` hook on `:fetch_metadata` to trigger `:download_images` automatically.

## Implementation Steps

### Step 1: Create `MediaManager.ImageDownloader`

**File:** `lib/media_manager/image_downloader.ex`

```elixir
defmodule MediaManager.ImageDownloader do
  require Logger

  @doc """
  Downloads all pending images for an entity.
  Returns :ok if all downloads succeed, {:error, reason} on first failure.
  """
  def download_all(entity) do
    images_dir = MediaManager.Config.get(:media_images_dir)

    entity.images
    |> Enum.filter(fn image -> image.url && !image.content_url end)
    |> Enum.reduce_while(:ok, fn image, :ok ->
      case download_image(image, entity.id, images_dir) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp download_image(image, entity_id, images_dir) do
    relative_path = "#{entity_id}/#{image.role}.#{image.extension}"
    absolute_path = Path.join(images_dir, relative_path)

    # Create directory
    absolute_path |> Path.dirname() |> File.mkdir_p!()

    # Download
    case Req.get(image.url) do
      {:ok, %{status: 200, body: body}} ->
        case File.write(absolute_path, body) do
          :ok ->
            # Update Image record with local path
            image
            |> Ash.Changeset.for_update(:update, %{content_url: relative_path})
            |> Ash.update!()

            Logger.info("ImageDownloader: saved #{relative_path}")
            :ok

          {:error, reason} ->
            Logger.error("ImageDownloader: write failed for #{relative_path}: #{inspect(reason)}")
            {:error, {:write_failed, relative_path, reason}}
        end

      {:ok, %{status: status}} ->
        Logger.warning("ImageDownloader: HTTP #{status} for #{image.url}")
        {:error, {:http_error, status, image.url}}

      {:error, reason} ->
        Logger.error("ImageDownloader: request failed for #{image.url}: #{inspect(reason)}")
        {:error, {:download_failed, image.url, reason}}
    end
  end
end
```

### Step 2: Add `:download_images` action to `WatchedFile`

**File:** `lib/media_manager/library/watched_file.ex`

Add a new update action and a corresponding change module:

```elixir
update :download_images do
  require_atomic? false
  change MediaManager.Library.WatchedFile.Changes.DownloadImages
end
```

### Step 3: Create `DownloadImages` change module

**File:** `lib/media_manager/library/watched_file/changes/download_images.ex`

```elixir
defmodule MediaManager.Library.WatchedFile.Changes.DownloadImages do
  use Ash.Resource.Change
  alias MediaManager.Library.Entity

  def change(changeset, _opts, _context) do
    entity_id = Ash.Changeset.get_attribute(changeset, :entity_id)

    entity =
      Entity
      |> Ash.get!(entity_id, action: :with_associations)

    case MediaManager.ImageDownloader.download_all(entity) do
      :ok ->
        Ash.Changeset.change_attribute(changeset, :state, :complete)

      {:error, reason} ->
        changeset
        |> Ash.Changeset.change_attribute(:state, :error)
        |> Ash.Changeset.change_attribute(:error_message, "Image download failed: #{inspect(reason)}")
    end
  end
end
```

### Step 4: Wire `:fetch_metadata` → `:download_images` via `after_action`

**File:** `lib/media_manager/library/watched_file.ex`

Add `after_action` hook to the `:fetch_metadata` action (following plan 002 pattern):

```elixir
update :fetch_metadata do
  require_atomic? false
  change set_attribute(:state, :fetching_metadata)
  change MediaManager.Library.WatchedFile.Changes.FetchMetadata

  change after_action(fn _changeset, file, _context ->
    if file.state == :fetching_images do
      case file |> Ash.Changeset.for_update(:download_images, %{}) |> Ash.update() do
        {:ok, updated} -> {:ok, updated}
        {:error, reason} ->
          Logger.warning("Pipeline: image download failed for #{file.id}: #{inspect(reason)}")
          {:ok, file}
      end
    else
      {:ok, file}
    end
  end)
end
```

### Step 5: Ensure `Image` `:update` action accepts `content_url`

**File:** `lib/media_manager/library/image.ex`

The default `:update` action already exists via `defaults [:read, :update, :destroy]`. Verify it accepts `content_url`. Since `defaults` generates a default update that accepts all attributes, this should work. If not, add an explicit update action:

```elixir
update :update do
  primary? true
  accept [:content_url]
end
```

## Files Changed

| File | Change |
|------|--------|
| `lib/media_manager/image_downloader.ex` | **New** — functional module for downloading images |
| `lib/media_manager/library/watched_file/changes/download_images.ex` | **New** — Ash change for `:download_images` action |
| `lib/media_manager/library/watched_file.ex` | Add `:download_images` action, add `after_action` to `:fetch_metadata` |
| `lib/media_manager/library/image.ex` | Possibly add explicit `:update` action if default doesn't accept `content_url` |

## Testing

No new tests per testing strategy — image downloading is I/O-heavy and the pipeline is volatile. Verify manually by running a file through the full pipeline and confirming:
- Images appear at `{media_images_dir}/images/{entity-id}/poster.jpg` etc.
- `Image` records have `content_url` populated.
- `WatchedFile` reaches `:complete` state.

## Notes

- `Req.get/1` is used with a bare URL (not the TMDB client, since image URLs are direct CDN links).
- The download is synchronous within the Ash action. If this becomes a bottleneck for entities with many images, it can be made async later, but for v1 (max 3 images per entity) this is fine.
- Per IMAGE-CACHING.md: "Never overwrite a locally modified image without user confirmation." For v1, we only download when `content_url` is nil, which handles this.
