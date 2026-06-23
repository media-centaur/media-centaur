defmodule MediaCentaur.Reconciliation do
  use Boundary,
    deps: [],
    exports: [Artifact, Interpretation, Model, Placement, SpineNode, Models.GapFill]

  @moduledoc """
  Reconciles **artifacts** (files, and later release candidates) against a
  show's **canonical episode spine** (TMDB numbering) — the engine behind
  cour-aware ingest (see `campaigns/reconciliation-engine.md`).

  The system must never fabricate canonical structure to fit an artifact's
  self-description (a file labelled `S02E01` for a single-season show must
  not mint a phantom Season 2). Instead, plural **interpretation models**
  (`Reconciliation.Model`) propose how a batch maps onto the spine —
  `Models.GapFill` is the reliable floor; title/absolute/offset models
  corroborate — each yielding `Interpretation`s with a confidence and a
  human-readable rationale. Agreement collapses to a high-confidence
  proposal; disagreement surfaces as alternatives the user arbitrates.

  ## Vocabulary

  - `SpineNode` — one canonical `{season, episode}` position; `present?`
    marks what the library already has, so the *gap* is what a batch
    reconciles against.
  - `Artifact` — a file with **claims** (`claimed_season/episode/title`):
    evidence, not truth.
  - `Placement` — a proposed `artifact → {season, episode}` link.
  - `Interpretation` — one model's full proposal: placements + confidence
    + rationale.

  Currently pure (`deps: []`) — models read an assembled spine + artifacts.
  The impure caller (a pipeline stage assembling the spine from a TMDB
  season fetch + the library present-set, mirroring `Acquisition.Cours`)
  and the persistence of confirmed/pinned placements are the next phases.
  """
end
