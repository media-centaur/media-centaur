defmodule MediaCentaur.Acquisition.Pursuits.Identity do
  @moduledoc """
  The single owner of download↔pursuit identity strategy.

  Identity is needed at three lifecycle stages with different inputs;
  each stage has its own consult point, but the *strategies* and their
  precedence are defined here, once:

  | # | Strategy | Key | Stage(s) |
  |---|----------|-----|----------|
  | 1 | **Infohash** | `Target.torrent_hash` ↔ `QueueItem.id` | queue pairing (`QueueMatcher.find_item/4`) |
  | 2 | **Content path** | `Target.content_path` ↔ present file path (exact or under-directory) | library reconciliation |
  | 3 | **TMDB identity** | `(tmdb_id, unit.season_number, unit.episode_number)` | library reconciliation (tmdb recipes) |
  | 4 | **Normalized release name** | `normalize_title/1` of the release ↔ queue title / path segment | queue pairing fallback, library reconciliation fallback |

  Lower numbers are more authoritative: a hash match is never
  second-guessed by a title; a content-path match is decisive over
  fuzzy name matching. Strategy 4 exists for hashless grabs (usenet,
  indexers that omit the hash) and pre-capture pursuits; once
  `Pursuits.DownloadIdentity` captures the envelope, strategies 1–2
  take over.

  **The envelope is captured atomically.** On the first watcher tick
  where the target's download is visible in the queue,
  `DownloadIdentity.capture!/3` writes `torrent_hash` AND
  `content_path` together (write-once), gated on the *goal*
  (`content_path` present) — never on a precondition like "has hash",
  which is how the v0.77.3→.4 regression happened.

  Consult points:

    * `MediaCentaur.Acquisition.QueueMatcher` — live queue pairing
      (strategies 1, 4).
    * `MediaCentaur.Acquisition.Pursuits.DownloadIdentity` — envelope
      capture at first observation.
    * `MediaCentaur.Acquisition.Pursuits.LibraryReconciler` — landed-file
      resolution (strategies 2, 3, 4 in that order).

  `MediaCentaur.Downloads.QueueItem` caches `normalize_title/1`'s
  result at construction (cross-context by design — asserted in sync by
  `QueueItemTest`).
  """

  @doc """
  Normalizes a title for identity matching — lowercased,
  non-alphanumeric stripped. THE shared primitive: queue pairing,
  release-name reconciliation, and `QueueItem.normalized_title` caching
  must all use this exact function so a value normalized at one stage
  matches a value normalized at another.
  """
  @spec normalize_title(String.t() | nil) :: String.t()
  def normalize_title(nil), do: ""

  def normalize_title(title) when is_binary(title) do
    title
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "")
  end
end
