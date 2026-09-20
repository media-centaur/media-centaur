defmodule MediaCentaur.TMDB.RetentionPoliciesTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Retention.Policy
  alias MediaCentaur.TMDB.RetentionPolicies

  test "declares the store's sweep on the Metadata subsystem" do
    assert [%Policy{key: :tmdb_store, subsystem: :tmdb, mode: :sweep, run: run}] =
             RetentionPolicies.policies()

    assert run == (&MediaCentaur.TMDB.Store.sweep/0)
  end

  test "the store's policy is registered beside the artwork cache's" do
    keys = Enum.map(MediaCentaur.Retention.policies(), & &1.key)
    assert :tmdb_store in keys
    assert :tmdb_artwork in keys
  end
end
