defmodule MediaCentaur.Library.OwnerRefTest do
  @moduledoc """
  The per-type-key → `(owner_type, owner_id)` translation every sidecar
  write goes through (Library Schema v2 Phase 2 Task D). The behaviour
  worth pinning is the asymmetry between kinds — only images hang off an
  episode, only extras hang off a season — because a silently-accepted
  wrong key would write a sidecar row pointing at nothing.
  """
  use ExUnit.Case, async: true

  alias MediaCentaur.Library.OwnerRef

  describe "kinds/0 and owner_types/1" do
    test "declares the three sidecar kinds" do
      assert Enum.sort(OwnerRef.kinds()) == [:external_id, :extra, :image]
    end

    test "only images can hang off an episode" do
      assert :episode in OwnerRef.owner_types(:image)
      refute :episode in OwnerRef.owner_types(:extra)
      refute :episode in OwnerRef.owner_types(:external_id)
    end

    test "only extras can hang off a season" do
      assert :season in OwnerRef.owner_types(:extra)
      refute :season in OwnerRef.owner_types(:image)
      refute :season in OwnerRef.owner_types(:external_id)
    end

    test "every kind covers the three container types" do
      for kind <- OwnerRef.kinds() do
        types = OwnerRef.owner_types(kind)

        assert :movie in types
        assert :tv_series in types
        assert :movie_series in types
      end
    end

    test "raises for an unknown kind rather than returning an empty list" do
      assert_raise KeyError, fn -> OwnerRef.owner_types(:not_a_sidecar) end
    end
  end

  describe "normalise/2" do
    test "rewrites a per-type key into the discriminator pair" do
      assert OwnerRef.normalise(%{movie_id: "m-1", role: "poster"}, :image) ==
               %{owner_type: :movie, owner_id: "m-1", role: "poster"}
    end

    test "maps each per-type key to its own owner type" do
      assert %{owner_type: :tv_series, owner_id: "s-1"} =
               OwnerRef.normalise(%{tv_series_id: "s-1"}, :image)

      assert %{owner_type: :episode, owner_id: "e-1"} =
               OwnerRef.normalise(%{episode_id: "e-1"}, :image)

      assert %{owner_type: :season, owner_id: "sea-1"} =
               OwnerRef.normalise(%{season_id: "sea-1"}, :extra)

      assert %{owner_type: :video_object, owner_id: "v-1"} =
               OwnerRef.normalise(%{video_object_id: "v-1"}, :external_id)
    end

    test "leaves attrs already carrying the pair untouched" do
      attrs = %{owner_type: :movie, owner_id: "m-1", role: "backdrop"}

      assert OwnerRef.normalise(attrs, :image) == attrs
    end

    test "leaves attrs with no owner key at all untouched" do
      assert OwnerRef.normalise(%{role: "poster"}, :image) == %{role: "poster"}
    end

    test "a nil per-type key does not count as present" do
      attrs = %{movie_id: nil, role: "poster"}

      assert OwnerRef.normalise(attrs, :image) == attrs
    end

    test "drops every per-type key for the kind, so two keys are never half-applied" do
      result = OwnerRef.normalise(%{movie_id: "m-1", tv_series_id: "s-1"}, :image)

      refute Map.has_key?(result, :movie_id)
      refute Map.has_key?(result, :tv_series_id)
      assert result.owner_type == :movie
      assert result.owner_id == "m-1"
    end

    test "a key the kind does not accept is left alone" do
      # `:season_id` is an extras-only key — an image carrying one is a
      # caller bug, and silently rewriting it would bury that.
      attrs = %{season_id: "sea-1", role: "poster"}

      assert OwnerRef.normalise(attrs, :image) == attrs
    end

    test "raises for an unknown kind" do
      assert_raise KeyError, fn -> OwnerRef.normalise(%{movie_id: "m-1"}, :not_a_sidecar) end
    end
  end
end
