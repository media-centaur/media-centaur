defmodule MediaCentaur.Repo.DataMigrations.ListingReplacesTracking do
  @moduledoc """
  [ADR-067]: the tracking activity kind (32162) is retired and a listing
  (32163) takes its place on the wire. Stored tracking rows are removed
  rather than kept as a parallel shelf — the app no longer reads the
  kind, and `Activity.kind` no longer admits the value, so a row left
  behind would fail to load. The `share_tracking` preference row goes
  with it: *Share your watchlist* shares more than *Share what you
  track* did, so it is a fresh, default-off consent, not an inherited
  one.

  This file is **append-only**. Never edit a shipped data migration.

  Raw SQL, snapshot-style: no live schema aliases. Idempotent — a second
  run finds nothing to delete.

  [ADR-067]: `decisions/architecture/2026-09-11-067-listing-replaces-tracking-on-the-wire.md`
  """
  use Ecto.Migration

  @drop_tracking_activities "DELETE FROM activities WHERE kind = 'tracking'"
  @drop_share_tracking_setting "DELETE FROM settings_entries WHERE key = 'share_tracking'"

  def up, do: sweep(repo())

  def down, do: :ok

  @doc "Deletes every stored tracking activity and the retired sharing toggle's row. Returns `:ok`."
  def sweep(repo) do
    repo.query!(@drop_tracking_activities, [])
    repo.query!(@drop_share_tracking_setting, [])
    :ok
  end
end
