defmodule MediaCentarr.Library.AvailabilityTest do
  # Uses `async: false` because the module writes to a module-global
  # persistent_term key. Tests that share the cache must be serialized.
  use ExUnit.Case, async: false

  alias MediaCentarr.Library.Availability

  # Helpers to poke the cache directly, bypassing the GenServer.
  defp put_cache(map), do: :persistent_term.put({Availability, :state}, map)
  defp clear_cache, do: :persistent_term.erase({Availability, :state})

  setup do
    original = :persistent_term.get({Availability, :state}, :__unset__)

    on_exit(fn ->
      case original do
        :__unset__ -> clear_cache()
        m -> put_cache(m)
      end
    end)

    :ok
  end

  describe "dir_status/0" do
    test "returns empty map when nothing cached" do
      clear_cache()
      assert Availability.dir_status() == %{}
    end

    test "returns the cached map" do
      put_cache(%{"/mnt/a" => :watching, "/mnt/b" => :unavailable})
      assert Availability.dir_status() == %{"/mnt/a" => :watching, "/mnt/b" => :unavailable}
    end
  end

  describe "available?/1 — entity mapping" do
    setup do
      put_cache(%{
        "/mnt/videos" => :watching,
        "/mnt/nas/media" => :unavailable
      })

      :ok
    end

    test "true when entity's file is under a :watching dir" do
      entity = %{files: [%{path: "/mnt/videos/Sample.Movie.mkv"}]}
      assert Availability.available?(entity) == true
    end

    test "false when entity's file is under an :unavailable dir" do
      entity = %{files: [%{path: "/mnt/nas/media/BreakingBad/S01E01.mkv"}]}
      assert Availability.available?(entity) == false
    end

    test "longest prefix wins when dirs nest" do
      put_cache(%{
        "/mnt" => :watching,
        "/mnt/nas/media" => :unavailable
      })

      entity = %{files: [%{path: "/mnt/nas/media/Show.mkv"}]}
      assert Availability.available?(entity) == false
    end

    test "true when no configured dir matches (unknown path — don't gray out)" do
      entity = %{files: [%{path: "/home/other/video.mkv"}]}
      assert Availability.available?(entity) == true
    end

    test "true when entity has no file path" do
      assert Availability.available?(%{}) == true
      assert Availability.available?(%{files: []}) == true
      assert Availability.available?(%{file_path: nil}) == true
    end

    test "falls back to file_path key when files association isn't available" do
      entity = %{file_path: "/mnt/nas/media/Show.mkv"}
      assert Availability.available?(entity) == false
    end

    test "requires a trailing / to match so /mnt/a doesn't match /mnt/ab" do
      put_cache(%{"/mnt/a" => :unavailable})
      entity = %{files: [%{path: "/mnt/ab/file.mkv"}]}
      assert Availability.available?(entity) == true
    end

    test ":initializing is treated as available (optimistic, avoids boot-time flash)" do
      put_cache(%{"/mnt/videos" => :initializing})
      entity = %{files: [%{path: "/mnt/videos/x.mkv"}]}
      assert Availability.available?(entity) == true
    end
  end
end
