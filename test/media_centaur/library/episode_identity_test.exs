defmodule MediaCentaur.Library.EpisodeIdentityTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Library.EpisodeIdentity

  describe "to_key/1" do
    test "matches the ReleaseTracking want TV key form (s{season}e{episode})" do
      assert EpisodeIdentity.to_key(EpisodeIdentity.new("209867", 1, 29)) == "s1e29"
      assert EpisodeIdentity.to_key(EpisodeIdentity.new("1", 12, 7)) == "s12e7"
    end
  end

  describe "label/1" do
    test "zero-pads to the SxxExx display form (matches Format.episode_label/2)" do
      assert EpisodeIdentity.label(EpisodeIdentity.new("209867", 1, 29)) == "S01E29"
      assert EpisodeIdentity.label(EpisodeIdentity.new("1", 12, 7)) == "S12E07"
    end
  end

  describe "absolute_ordinal/2" do
    test "is the episode number for a single continuous season (the Frieren case)" do
      # TMDB models Frieren as one 38-episode Season 1, so S01E29 == absolute 29.
      id = EpisodeIdentity.new("209867", 1, 29)
      assert EpisodeIdentity.absolute_ordinal(id, %{0 => 26, 1 => 38}) == 29
    end

    test "sums prior non-special seasons for a split-season show" do
      # A show TMDB splits S1(28) + S2(10): S02E01 is absolute 29.
      id = EpisodeIdentity.new("x", 2, 1)
      assert EpisodeIdentity.absolute_ordinal(id, %{0 => 5, 1 => 28, 2 => 10}) == 29
    end

    test "excludes season 0 (Specials) from the ordinal" do
      id = EpisodeIdentity.new("x", 1, 1)
      assert EpisodeIdentity.absolute_ordinal(id, %{0 => 99, 1 => 12}) == 1
    end

    test "tolerates missing season counts (best-effort: counts only what it knows)" do
      id = EpisodeIdentity.new("x", 3, 4)
      # Only S1's count is known; S2 unknown contributes nothing.
      assert EpisodeIdentity.absolute_ordinal(id, %{1 => 10}) == 14
    end
  end
end
