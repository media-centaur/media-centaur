# Drive-Grouped, Auto-Refreshing Storage View

## Problem Statement

The current storage metrics section on the Operations page lists every configured path independently. When multiple watch directories or the image cache share a physical drive, the same drive capacity appears multiple times with no indication they're the same filesystem. There's also no auto-refresh — the data is stale until a full page reload.

## User-Facing Behavior

The "Storage" section on `/operations` shows one entry per physical drive instead of one per path. Each drive entry displays:

- **Drive label:** mount point + device name, e.g. `/mnt/media-1 (sda1)`
- **Capacity bar:** progress bar colored green (< 75%), yellow (75–89%), red (90%+)
- **Used / total:** formatted byte values and percentage
- **Path list underneath:** watch dirs paired with their image cache dir, plus the database path if it lives on this drive

Example rendering:

```
/mnt/media-1 (sda1)                    1.2 TB / 4 TB  ████████░░ 30%

  Watch dir     /mnt/media-1/Videos
  Image cache   /mnt/media-1/.media-centaur/images

  Watch dir     /mnt/media-1/Documentaries
  Image cache   /mnt/media-1/.media-centaur/images

/mnt/ssd (nvme0n1p2)                   42 GB / 500 GB  █░░░░░░░░░ 8%

  Database      /home/user/.local/share/media-centaur/media_library.db
```

Long paths truncate from the left with `…` and show the full path in a native browser tooltip on hover.

The section auto-refreshes every 5 minutes without user interaction.

## Design

### Data Model Changes

`Storage.measure_all/0` changes its return type.

**Before:** flat list of `%{path, label, used_bytes, total_bytes, usage_percent}`

**After:** list of drive maps:

```elixir
%{
  mount_point: "/mnt/media-1",
  device: "sda1",
  used_bytes: 1_200_000_000_000,
  total_bytes: 4_000_000_000_000,
  usage_percent: 30,
  roles: [
    %{label: "Watch dir", path: "/mnt/media-1/Videos"},
    %{label: "Image cache", path: "/mnt/media-1/.media-centaur/images"},
    %{label: "Watch dir", path: "/mnt/media-1/Documentaries"},
    %{label: "Image cache", path: "/mnt/media-1/.media-centaur/images"},
  ]
}
```

Roles are ordered: watch dir / image cache pairs first (in config order), then database last. Each watch dir is immediately followed by its image cache path.

**Implementation approach for `measure_all/0`:**

1. Collect all paths to measure: each watch dir, its `images_dir_for`, and the database path from `Config.get(:database_path)`.
2. For each path, run `df --output=source,target,used,avail -B1 <path>` to get device, mount point, and capacity in one call.
3. Group by mount point. Each group shares one set of capacity numbers (used/total/percent). Attach the role list.
4. Extract device basename from the `source` column (e.g. `/dev/sda1` → `sda1`).

This means one `df` call per configured path (same as today), but the results are grouped.

### LiveView Changes

**Timer:** On mount, schedule `Process.send_after(self(), :refresh_storage, @storage_refresh_ms)` with `@storage_refresh_ms` set to `5 * 60 * 1_000` (5 minutes). The `handle_info(:refresh_storage, socket)` callback re-measures and re-schedules.

**Template:** Replace the flat list rendering with a nested structure — outer loop per drive, inner loop per role. The progress bar keeps the existing daisyUI `progress` element and the existing `usage_progress_class/1` / `usage_text_class/1` helpers (thresholds at 75% and 90%).

**CSS truncation:** Path values rendered in a container with:

```css
.truncate-left {
  direction: rtl;
  text-overflow: ellipsis;
  overflow: hidden;
  white-space: nowrap;
}
```

With a `title` attribute on the element for the native browser tooltip. No JavaScript needed.

### Integration Points

None — this is entirely within the backend LiveView. No channel messages, no cross-component contracts.

### Constraints

- `df` is the only mechanism for filesystem info (no Elixir stdlib equivalent). Already used by the current implementation.
- SQLite database path comes from `Config.get(:database_path)`.
- Watch dir → image cache binding comes from `Config.images_dir_for/1`.

## Acceptance Criteria

- [ ] Each physical drive (unique mount point) appears exactly once in the storage section
- [ ] Drive label shows mount point and device name
- [ ] Progress bar uses existing green/yellow/red color thresholds (75%, 90%)
- [ ] Watch directories listed paired with their image cache path, in config order
- [ ] Database path shown on whichever drive it resides on
- [ ] Long paths truncate from the left with `…` prefix
- [ ] Truncated paths show full value in native tooltip on hover
- [ ] Storage section auto-refreshes every 5 minutes
- [ ] Non-existent paths are silently excluded (existing behavior preserved)

## Decisions

No new ADRs needed — this is a UI/data-reshaping change within existing architectural boundaries. The color thresholds (75%/90%) are existing hardcoded constants and remain so.

## Smoke Tests

No testable cross-component contracts introduced. `Storage.measure_all/0` is an internal module whose return shape is consumed only by the Operations LiveView. The existing `test/media_centaur/storage_test.exs` should be updated to reflect the new return structure if tests exist for `measure_all/0`.
