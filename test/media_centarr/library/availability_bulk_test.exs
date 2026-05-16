defmodule MediaCentarr.Library.AvailabilityBulkTest do
  @moduledoc """
  Spec for `Library.Availability.available_for_ids/1` — the bulk variant
  used by projection consumers (Phase 3.1). Resolves availability for
  many container UUIDs without preloading `entity.watched_files` per
  entity; one DB roundtrip pulls every file row in one shot.

  Sibling to `MediaCentarr.Library.AvailabilityTest` which covers the
  preloaded-entity `available?/1` path. Split into a separate file so
  the DB-backed tests (`use DataCase`) don't share a setup block with
  the pure persistent-term tests (`use ExUnit.Case`).
  """
  use MediaCentarr.DataCase, async: false

  import MediaCentarr.TestFactory

  alias MediaCentarr.Library.Availability
  alias MediaCentarr.Library.FilePresence

  setup do
    original = :persistent_term.get({Availability, :state}, :__unset__)

    :persistent_term.put({Availability, :state}, %{
      "/media/test" => :watching,
      "/mnt/offline" => :unavailable
    })

    on_exit(fn ->
      case original do
        :__unset__ -> :persistent_term.erase({Availability, :state})
        m -> :persistent_term.put({Availability, :state}, m)
      end
    end)

    :ok
  end

  describe "available_for_ids/1" do
    test "returns empty map for empty id list" do
      assert Availability.available_for_ids([]) == %{}
    end

    test "movie under a :watching dir is available" do
      movie = create_standalone_movie(%{name: "Visible Movie"})

      file =
        create_linked_file(%{
          movie_id: movie.id,
          file_path: "/media/test/visible.mkv",
          watch_dir: "/media/test"
        })

      FilePresence.stamp(file.file_path, file.watch_dir)

      assert Availability.available_for_ids([movie.id]) == %{movie.id => true}
    end

    test "movie under an :unavailable dir is reported unavailable" do
      movie = create_standalone_movie(%{name: "Offline Movie"})

      file =
        create_linked_file(%{
          movie_id: movie.id,
          file_path: "/mnt/offline/m.mkv",
          watch_dir: "/mnt/offline"
        })

      FilePresence.stamp(file.file_path, file.watch_dir)

      assert Availability.available_for_ids([movie.id]) == %{movie.id => false}
    end

    test "tv series under a :watching dir is available" do
      tv = create_tv_series(%{name: "Visible Show"})

      file =
        create_linked_file(%{
          tv_series_id: tv.id,
          file_path: "/media/test/show-s01e01.mkv",
          watch_dir: "/media/test"
        })

      FilePresence.stamp(file.file_path, file.watch_dir)

      assert Availability.available_for_ids([tv.id]) == %{tv.id => true}
    end

    test "movie series and video object containers are resolved" do
      ms = create_movie_series(%{name: "Visible Series"})

      msf =
        create_linked_file(%{
          movie_series_id: ms.id,
          file_path: "/media/test/series.mkv",
          watch_dir: "/media/test"
        })

      FilePresence.stamp(msf.file_path, msf.watch_dir)

      vo = create_video_object(%{name: "Visible VO"})

      vof =
        create_linked_file(%{
          video_object_id: vo.id,
          file_path: "/mnt/offline/vo.mkv",
          watch_dir: "/mnt/offline"
        })

      FilePresence.stamp(vof.file_path, vof.watch_dir)

      assert Availability.available_for_ids([ms.id, vo.id]) == %{
               ms.id => true,
               vo.id => false
             }
    end

    test "entity not in DB resolves as available (optimistic, matches available?/1)" do
      missing = Ecto.UUID.generate()
      assert Availability.available_for_ids([missing]) == %{missing => true}
    end

    test "mixed online + offline batch resolves each id independently" do
      online = create_standalone_movie(%{name: "Online"})

      onf =
        create_linked_file(%{
          movie_id: online.id,
          file_path: "/media/test/online.mkv",
          watch_dir: "/media/test"
        })

      FilePresence.stamp(onf.file_path, onf.watch_dir)

      offline = create_standalone_movie(%{name: "Offline"})

      offf =
        create_linked_file(%{
          movie_id: offline.id,
          file_path: "/mnt/offline/offline.mkv",
          watch_dir: "/mnt/offline"
        })

      FilePresence.stamp(offf.file_path, offf.watch_dir)

      result = Availability.available_for_ids([online.id, offline.id])

      assert result[online.id] == true
      assert result[offline.id] == false
    end
  end
end
