defmodule MediaCentarr.Platform.DefaultsTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.Platform.Defaults

  # Linux defaults are exercised here. macOS variants
  # (/opt/homebrew/bin/...) land in Phase 5.

  describe "mpv_path/0" do
    test "returns /usr/bin/mpv on Linux" do
      assert Defaults.mpv_path() == "/usr/bin/mpv"
    end
  end

  describe "ffprobe_path/0" do
    test "returns /usr/bin/ffprobe on Linux" do
      assert Defaults.ffprobe_path() == "/usr/bin/ffprobe"
    end
  end
end
