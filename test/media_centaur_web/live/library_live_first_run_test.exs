defmodule MediaCentaurWeb.LibraryLiveFirstRunTest do
  @moduledoc """
  Pure function tests for the Library page's first-run empty-state logic
  ([ADR-030] LiveView logic extraction).
  """
  use ExUnit.Case, async: true

  alias MediaCentaurWeb.LiveHelpers

  describe "media_dirs_configured?/1" do
    test "returns true when at least one media_dir is set" do
      assert LiveHelpers.media_dirs_configured?(["/mnt/movies"])
      assert LiveHelpers.media_dirs_configured?(["/a", "/b"])
    end

    test "returns false for an empty list, nil, or non-list values" do
      refute LiveHelpers.media_dirs_configured?([])
      refute LiveHelpers.media_dirs_configured?(nil)
      refute LiveHelpers.media_dirs_configured?(%{})
      refute LiveHelpers.media_dirs_configured?("single-string")
    end
  end
end
