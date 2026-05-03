defmodule MediaCentarrWeb.Components.UpcomingCardsTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.Acquisition.{Grab, QueueItem}
  alias MediaCentarrWeb.Components.UpcomingCards
  alias MediaCentarrWeb.Components.UpcomingCards.TrackedItem

  defp grab(status, overrides \\ %{}) do
    Map.merge(%Grab{status: status}, overrides)
  end

  defp queue(state, overrides \\ %{}) do
    Map.merge(%QueueItem{id: "q-1", title: "Q", state: state}, overrides)
  end

  describe "release_status/3 — completion takes precedence" do
    test ":completed when in_library, regardless of grab/queue" do
      assert UpcomingCards.release_status(true, nil, nil) == :completed

      assert UpcomingCards.release_status(true, grab("searching"), queue(:downloading)) ==
               :completed
    end
  end

  describe "release_status/3 — grabbed + queue state" do
    test ":downloading when grab is grabbed and queue item is :downloading" do
      assert UpcomingCards.release_status(false, grab("grabbed"), queue(:downloading)) ==
               :downloading
    end

    test ":downloading when grab is grabbed and queue item is :stalled (treat as live)" do
      assert UpcomingCards.release_status(false, grab("grabbed"), queue(:stalled)) ==
               :downloading
    end

    test ":paused when grab is grabbed and queue item is :paused" do
      assert UpcomingCards.release_status(false, grab("grabbed"), queue(:paused)) == :paused
    end

    test ":errored when grab is grabbed and queue item is :error" do
      assert UpcomingCards.release_status(false, grab("grabbed"), queue(:error)) == :errored
    end

    test ":downloading when grab is grabbed but no matching queue item (queued or imported)" do
      assert UpcomingCards.release_status(false, grab("grabbed"), nil) == :downloading
    end
  end

  describe "release_status/3 — searching states" do
    test ":searching when grab status is searching" do
      assert UpcomingCards.release_status(false, grab("searching"), nil) == :searching
    end

    test ":searching when grab status is snoozed" do
      assert UpcomingCards.release_status(false, grab("snoozed"), nil) == :searching
    end
  end

  describe "release_status/3 — terminal non-success states" do
    test ":abandoned when grab status is abandoned" do
      assert UpcomingCards.release_status(false, grab("abandoned"), nil) == :abandoned
    end

    test ":cancelled when grab status is cancelled (treated visually as no-op)" do
      assert UpcomingCards.release_status(false, grab("cancelled"), nil) == :cancelled
    end
  end

  describe "release_status/3 — no acquisition" do
    test ":none when there's no grab and not in library" do
      assert UpcomingCards.release_status(false, nil, nil) == :none
    end
  end

  # ---------------------------------------------------------------------------
  # group_releases_by_item/1
  # ---------------------------------------------------------------------------

  alias MediaCentarr.ReleaseTracking.{Item, Release}

  defp tv_item(id, name) do
    %Item{id: id, name: name, media_type: :tv_series, tmdb_id: String.to_integer("1#{id}")}
  end

  defp movie_item(id, name) do
    %Item{id: id, name: name, media_type: :movie, tmdb_id: String.to_integer("9#{id}")}
  end

  defp release_for(item, season, episode, air_date) do
    %Release{
      id: "r-#{item.id}-#{season}-#{episode}",
      item: item,
      item_id: item.id,
      season_number: season,
      episode_number: episode,
      air_date: air_date
    }
  end

  describe "group_releases_by_item/1" do
    test "empty input returns empty list" do
      assert UpcomingCards.group_releases_by_item([]) == []
    end

    test "single release → single group" do
      show_a = tv_item("1", "Sample Show")
      r = release_for(show_a, 5, 1, ~D[2026-04-09])

      assert [%{item: ^show_a, releases: [^r]}] = UpcomingCards.group_releases_by_item([r])
    end

    test "two episodes of the same show → single group, sorted by (season, episode)" do
      show_a = tv_item("1", "Sample Show")
      e1 = release_for(show_a, 5, 1, ~D[2026-04-09])
      e2 = release_for(show_a, 5, 2, ~D[2026-04-16])

      # Pass them out of order to verify within-group sort.
      assert [%{item: ^show_a, releases: [^e1, ^e2]}] =
               UpcomingCards.group_releases_by_item([e2, e1])
    end

    test "two shows → two groups, freshest air_date first" do
      show_a = tv_item("1", "Sample Show")
      show_b = tv_item("2", "Other Sample Show")

      show_a_old = release_for(show_a, 5, 1, ~D[2026-04-09])
      show_b_new = release_for(show_b, 2, 8, ~D[2026-04-25])

      groups = UpcomingCards.group_releases_by_item([show_a_old, show_b_new])

      assert [%{item: ^show_b}, %{item: ^show_a}] = groups
    end

    test "mixed TV + movie → both groups present" do
      show_a = tv_item("1", "Sample Show")
      movie_a = movie_item("3", "Sample Movie")

      tv_release = release_for(show_a, 5, 1, ~D[2026-04-09])
      movie_release = release_for(movie_a, nil, nil, ~D[2026-04-01])

      groups = UpcomingCards.group_releases_by_item([tv_release, movie_release])
      assert length(groups) == 2
      assert Enum.find(groups, &(&1.item == show_a))
      assert Enum.find(groups, &(&1.item == movie_a))
    end

    test "groups with nil air_date sort to the end" do
      show_a = tv_item("1", "Sample Show")
      mystery = tv_item("2", "Unknown Date")

      dated = release_for(show_a, 1, 1, ~D[2026-04-09])
      undated = release_for(mystery, 1, 1, nil)

      assert [%{item: ^show_a}, %{item: ^mystery}] =
               UpcomingCards.group_releases_by_item([undated, dated])
    end
  end

  describe "build_home_release_summary/1" do
    defp movie_release(release_type, date) do
      %Release{
        id: "r-#{release_type}",
        release_type: release_type,
        air_date: date
      }
    end

    test "empty list → all nil" do
      assert UpcomingCards.build_home_release_summary([]) == %{
               theatrical: nil,
               digital: nil,
               physical: nil
             }
    end

    test "theatrical only" do
      releases = [movie_release("theatrical", ~D[2026-04-04])]

      assert UpcomingCards.build_home_release_summary(releases) == %{
               theatrical: ~D[2026-04-04],
               digital: nil,
               physical: nil
             }
    end

    test "theatrical + digital + physical" do
      releases = [
        movie_release("theatrical", ~D[2026-04-04]),
        movie_release("digital", ~D[2026-07-12]),
        movie_release("physical", ~D[2026-09-03])
      ]

      assert UpcomingCards.build_home_release_summary(releases) == %{
               theatrical: ~D[2026-04-04],
               digital: ~D[2026-07-12],
               physical: ~D[2026-09-03]
             }
    end

    test "duplicate type rows pick the earliest air_date" do
      releases = [
        movie_release("digital", ~D[2026-08-01]),
        movie_release("digital", ~D[2026-07-12])
      ]

      assert UpcomingCards.build_home_release_summary(releases).digital == ~D[2026-07-12]
    end

    test "ignores nil air_dates within a type" do
      releases = [
        movie_release("digital", nil),
        movie_release("digital", ~D[2026-07-12])
      ]

      assert UpcomingCards.build_home_release_summary(releases).digital == ~D[2026-07-12]
    end

    test "ignores unknown release_type values" do
      releases = [movie_release("streaming", ~D[2026-04-04])]

      assert UpcomingCards.build_home_release_summary(releases) == %{
               theatrical: nil,
               digital: nil,
               physical: nil
             }
    end
  end

  describe "home_release_lines/1" do
    test "no theatrical context → empty list (don't pollute non-theatrical cards)" do
      assert UpcomingCards.home_release_lines(%{
               theatrical: nil,
               digital: ~D[2026-07-12],
               physical: nil
             }) == []
    end

    test "theatrical with digital known" do
      assert UpcomingCards.home_release_lines(%{
               theatrical: ~D[2026-04-04],
               digital: ~D[2026-07-12],
               physical: nil
             }) == ["Digital: Jul 12, 2026"]
    end

    test "theatrical with physical known" do
      assert UpcomingCards.home_release_lines(%{
               theatrical: ~D[2026-04-04],
               digital: nil,
               physical: ~D[2026-09-03]
             }) == ["Physical: Sep 3, 2026"]
    end

    test "theatrical with digital and physical → digital first" do
      assert UpcomingCards.home_release_lines(%{
               theatrical: ~D[2026-04-04],
               digital: ~D[2026-07-12],
               physical: ~D[2026-09-03]
             }) == ["Digital: Jul 12, 2026", "Physical: Sep 3, 2026"]
    end

    test "theatrical with neither digital nor physical → 'not yet announced'" do
      assert UpcomingCards.home_release_lines(%{
               theatrical: ~D[2026-04-04],
               digital: nil,
               physical: nil
             }) == ["Home release: not yet announced"]
    end
  end

  describe "pending_grab_count/2" do
    defp pending_release(season, episode, opts \\ []) do
      item = Keyword.get(opts, :item, tv_item("1", "Show"))

      %Release{
        id: "r-#{season}-#{episode}",
        item: item,
        item_id: item.id,
        season_number: season,
        episode_number: episode,
        in_library: Keyword.get(opts, :in_library, false),
        air_date: ~D[2026-04-09]
      }
    end

    test "counts released-not-in-library releases with no matching grab" do
      releases = [
        pending_release(1, 1),
        pending_release(1, 2),
        pending_release(1, 3)
      ]

      assert UpcomingCards.pending_grab_count(releases, %{}) == 3
    end

    test "excludes in-library releases" do
      releases = [
        pending_release(1, 1, in_library: true),
        pending_release(1, 2),
        pending_release(1, 3)
      ]

      assert UpcomingCards.pending_grab_count(releases, %{}) == 2
    end

    test "excludes releases that already have a grab row" do
      item = tv_item("1", "Show")
      r1 = pending_release(1, 1, item: item)
      r2 = pending_release(1, 2, item: item)

      grab_map = %{
        {to_string(item.tmdb_id), MediaCentarr.ReleaseTracking.tmdb_type_for(item.media_type), 1, 1} =>
          grab("searching")
      }

      assert UpcomingCards.pending_grab_count([r1, r2], grab_map) == 1
    end

    test "empty list → 0" do
      assert UpcomingCards.pending_grab_count([], %{}) == 0
    end
  end

  describe "merge_active_groups/2 — released + upcoming per show" do
    # merge_active_groups is private — exercise via the helper-aliased
    # alias to test the cap behavior at the public surface.
    test "groups with both released and upcoming, capped at 3 visible upcoming" do
      show_a = tv_item("1", "Sample Show")

      r1 = release_for(show_a, 5, 1, ~D[2026-04-09])
      u1 = release_for(show_a, 5, 4, ~D[2026-04-30])
      u2 = release_for(show_a, 5, 5, ~D[2026-05-07])
      u3 = release_for(show_a, 5, 6, ~D[2026-05-14])
      u4 = release_for(show_a, 5, 7, ~D[2026-05-21])
      u5 = release_for(show_a, 5, 8, ~D[2026-05-28])

      [group] = UpcomingCards.merge_active_groups([r1], [u1, u2, u3, u4, u5])

      assert group.released == [r1]
      assert length(group.upcoming) == 3
      assert Enum.map(group.upcoming, & &1.episode_number) == [4, 5, 6]
      assert group.upcoming_overflow == 2
    end

    test "shows with only upcoming releases still get a card" do
      show_b = tv_item("2", "Other Sample Show")
      u1 = release_for(show_b, 2, 1, ~D[2026-05-01])

      [group] = UpcomingCards.merge_active_groups([], [u1])
      assert group.released == []
      assert group.upcoming == [u1]
      assert group.upcoming_overflow == 0
    end

    test "shows with only released releases still get a card" do
      show_a = tv_item("1", "Sample Show")
      r1 = release_for(show_a, 5, 1, ~D[2026-04-09])

      [group] = UpcomingCards.merge_active_groups([r1], [])
      assert group.released == [r1]
      assert group.upcoming == []
    end

    test "freshest released-air-date sorts above older released" do
      show_a = tv_item("1", "Sample Show")
      show_b = tv_item("2", "Other Sample Show")

      old = release_for(show_a, 5, 1, ~D[2026-04-09])
      newer = release_for(show_b, 2, 1, ~D[2026-04-25])

      assert [%{item: ^show_b}, %{item: ^show_a}] =
               UpcomingCards.merge_active_groups([old, newer], [])
    end

    test "soonest-upcoming sorts above later-upcoming for upcoming-only groups" do
      far = tv_item("1", "Far Future")
      soon = tv_item("2", "Soon")

      far_release = release_for(far, 1, 1, ~D[2026-12-01])
      soon_release = release_for(soon, 1, 1, ~D[2026-05-01])

      assert [%{item: ^soon}, %{item: ^far}] =
               UpcomingCards.merge_active_groups([], [far_release, soon_release])
    end
  end

  describe "TrackedItem struct" do
    test "constructs with all enforced keys" do
      item =
        struct!(TrackedItem, %{
          item_id: "00000000-0000-0000-0000-000000000001",
          name: "Sample Show",
          media_type: :tv_series,
          status_text: "2 upcoming"
        })

      assert %TrackedItem{} = item
      assert item.media_type == :tv_series
    end

    test "raises ArgumentError when item_id missing" do
      assert_raise ArgumentError, fn ->
        struct!(TrackedItem, %{
          name: "Sample Show",
          media_type: :tv_series,
          status_text: "tracking"
        })
      end
    end

    test "raises ArgumentError when status_text missing" do
      assert_raise ArgumentError, fn ->
        struct!(TrackedItem, %{
          item_id: "00000000-0000-0000-0000-000000000001",
          name: "Sample Show",
          media_type: :movie
        })
      end
    end
  end
end
