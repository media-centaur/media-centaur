defmodule MediaCentaur.Playback.MpvUserConfigTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Playback.MpvUserConfig

  describe "dir/1 — mpv's own lookup order" do
    test "MPV_HOME wins" do
      assert MpvUserConfig.dir(%{
               "MPV_HOME" => "/custom/mpv",
               "XDG_CONFIG_HOME" => "/xdg",
               "HOME" => "/home/viewer"
             }) ==
               "/custom/mpv"
    end

    test "then XDG_CONFIG_HOME/mpv" do
      assert MpvUserConfig.dir(%{"XDG_CONFIG_HOME" => "/xdg", "HOME" => "/home/viewer"}) == "/xdg/mpv"
    end

    test "then ~/.config/mpv" do
      assert MpvUserConfig.dir(%{"HOME" => "/home/viewer"}) == "/home/viewer/.config/mpv"
    end
  end

  describe "stale_bundled_copies/1" do
    @tag :tmp_dir
    test "an empty or absent scripts directory reports nothing", %{tmp_dir: tmp_dir} do
      assert MpvUserConfig.stale_bundled_copies(tmp_dir) == []

      File.mkdir_p!(Path.join(tmp_dir, "scripts"))
      assert MpvUserConfig.stale_bundled_copies(tmp_dir) == []
    end

    @tag :tmp_dir
    test "names each old single-file copy of a bundled script, and nothing else", %{tmp_dir: tmp_dir} do
      scripts = Path.join(tmp_dir, "scripts")
      File.mkdir_p!(scripts)
      File.write!(Path.join(scripts, "skip-intro.lua"), "")
      File.write!(Path.join(scripts, "track-menu.lua"), "")
      File.write!(Path.join(scripts, "hdr-display.lua"), "")

      assert MpvUserConfig.stale_bundled_copies(tmp_dir) ==
               [Path.join(scripts, "skip-intro.lua"), Path.join(scripts, "track-menu.lua")]
    end
  end
end
