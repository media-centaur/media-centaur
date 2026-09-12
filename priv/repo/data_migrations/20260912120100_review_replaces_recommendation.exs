defmodule MediaCentaur.Repo.DataMigrations.ReviewReplacesRecommendation do
  @moduledoc """
  [ADR-068]: the recommendation activity kind (32160) is retired and a
  review (32164) takes its place on the wire. Stored recommendation
  rows — sent and received — are removed rather than kept as a parallel
  shelf: the app no longer reads the kind, `Activity.kind` no longer
  admits the value, so a row left behind would fail to load; and a
  friend's signed recommendation cannot be re-signed as a review by
  anyone but that friend. People review again.

  This file is **append-only**. Never edit a shipped data migration.

  Raw SQL, snapshot-style: no live schema aliases. Idempotent — a second
  run finds nothing to delete.

  [ADR-068]: `decisions/architecture/2026-09-12-068-review-replaces-recommendation-on-the-wire.md`
  """
  use Ecto.Migration

  @drop_recommendations "DELETE FROM activities WHERE kind = 'recommendation'"

  def up, do: sweep(repo())

  def down, do: :ok

  @doc "Deletes every stored recommendation activity, sent or received. Returns `:ok`."
  def sweep(repo) do
    repo.query!(@drop_recommendations, [])
    :ok
  end
end
