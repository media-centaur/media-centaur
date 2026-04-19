defmodule MediaCentarrWeb.LibraryLiveFirstRunTest do
  @moduledoc """
  Pure function tests for the Library page's first-run empty-state logic
  ([ADR-030] LiveView logic extraction).
  """
  use ExUnit.Case, async: true

  alias MediaCentarrWeb.LibraryLive

  describe "watch_dirs_configured?/1" do
    test "returns true when at least one watch_dir is set" do
      assert LibraryLive.watch_dirs_configured?(["/mnt/movies"])
      assert LibraryLive.watch_dirs_configured?(["/a", "/b"])
    end

    test "returns false for an empty list, nil, or non-list values" do
      refute LibraryLive.watch_dirs_configured?([])
      refute LibraryLive.watch_dirs_configured?(nil)
      refute LibraryLive.watch_dirs_configured?(%{})
      refute LibraryLive.watch_dirs_configured?("single-string")
    end
  end
end
