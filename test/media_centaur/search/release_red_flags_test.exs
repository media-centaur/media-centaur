defmodule MediaCentaur.Search.ReleaseRedFlagsTest do
  # Suspicious-release classification is parser-class: append-only per
  # ADR-027. Shapes here are the classic fake-release malware patterns
  # observed in the wild, with generic placeholder titles.
  use ExUnit.Case, async: true

  alias MediaCentaur.Search.ReleaseRedFlags

  describe "suspicious?/1 — executable bait" do
    test "an exe token anywhere in a video release title" do
      assert ReleaseRedFlags.suspicious?("Sample.Movie.2026.1080p.HD.X264.1080p.exe")
      assert ReleaseRedFlags.suspicious?("Sample Movie 2026 1080p HD X264 1080p exe")
      assert ReleaseRedFlags.suspicious?("Sample.Movie.2026.EXE")
    end

    test "other executable / installer tokens" do
      assert ReleaseRedFlags.suspicious?("Sample.Movie.2026.1080p.scr")
      assert ReleaseRedFlags.suspicious?("Sample.Movie.2026.setup.msi")
      assert ReleaseRedFlags.suspicious?("Sample.Movie.2026.1080p.bat")
      assert ReleaseRedFlags.suspicious?("Sample.Show.S01E01.installer.cmd")
      assert ReleaseRedFlags.suspicious?("Sample.Movie.2026.apk")
    end

    test "password-protected archive bait" do
      assert ReleaseRedFlags.suspicious?("Sample.Movie.2026.1080p [password protected]")
      assert ReleaseRedFlags.suspicious?("Sample.Movie.2026.password.txt.rar")
    end
  end

  describe "suspicious?/2 — the size floor" do
    test "a video release under 25MB is bait regardless of its name" do
      assert ReleaseRedFlags.suspicious?("Sample.Movie.2026.1080p.BluRay.x264", 4 * 1024 * 1024)
      assert ReleaseRedFlags.suspicious?("Sample.Show.S01E01.720p.WEB-DL", 24 * 1024 * 1024)
    end

    test "plausible sizes pass; unknown size falls back to the title check" do
      refute ReleaseRedFlags.suspicious?("Sample.Movie.2026.1080p.BluRay.x264", 8_000_000_000)
      refute ReleaseRedFlags.suspicious?("Sample.Show.S01E01.480p", 90 * 1024 * 1024)
      refute ReleaseRedFlags.suspicious?("Sample.Movie.2026.1080p.BluRay.x264", nil)
      assert ReleaseRedFlags.suspicious?("Sample.Movie.2026.exe", nil)
      assert ReleaseRedFlags.suspicious?("Sample.Movie.2026.exe", 8_000_000_000)
    end
  end

  describe "suspicious?/1 — legitimate releases pass" do
    test "ordinary video releases" do
      refute ReleaseRedFlags.suspicious?("Sample.Movie.2026.1080p.BluRay.x264-GROUP")
      refute ReleaseRedFlags.suspicious?("Sample.Show.S01E01.2160p.WEB-DL.x265.10bit")
      refute ReleaseRedFlags.suspicious?("Sample Show S01-S05 COMPLETE 1080p")
    end

    test "tokens that merely contain the letters don't trip it" do
      # "executive" contains exe; "scrabble" contains scr.
      refute ReleaseRedFlags.suspicious?("The.Executive.2020.1080p.WEB-DL")
      refute ReleaseRedFlags.suspicious?("Scrabble.Masters.S01E01.720p")
    end
  end
end
