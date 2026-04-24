defmodule MediaCentarr.ErrorReports.FingerprintTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.ErrorReports.Fingerprint

  describe "fingerprint/2" do
    test "returns a 16-char lowercase hex key" do
      %{key: key} = Fingerprint.fingerprint(:tmdb, "request failed")
      assert String.length(key) == 16
      assert key =~ ~r/^[0-9a-f]{16}$/
    end

    test "same component + same normalized message produces the same key" do
      a = Fingerprint.fingerprint(:tmdb, "TMDB returned 429: rate limited (retry after 200)")
      b = Fingerprint.fingerprint(:tmdb, "TMDB returned 500: rate limited (retry after 750)")
      # Both normalize to "TMDB returned <N>: rate limited (retry after <N>)" → same key
      assert a.key == b.key
    end

    test "different error class produces a different key" do
      a = Fingerprint.fingerprint(:tmdb, "TMDB returned 429: rate limited")
      b = Fingerprint.fingerprint(:tmdb, "TMDB returned 500: upstream error")
      refute a.key == b.key
    end

    test "different component produces a different key" do
      a = Fingerprint.fingerprint(:tmdb, "connection refused")
      b = Fingerprint.fingerprint(:watcher, "connection refused")
      refute a.key == b.key
    end

    test "display_title prefixes the component label" do
      %{display_title: title} =
        Fingerprint.fingerprint(:tmdb, "TMDB returned 429: rate limited")

      assert title =~ ~r/^\[TMDB\] /
    end

    test "display_title uses known labels for known components" do
      assert Fingerprint.fingerprint(:library, "foo").display_title =~ ~r/^\[Library\]/
      assert Fingerprint.fingerprint(:pipeline, "foo").display_title =~ ~r/^\[Pipeline\]/
      assert Fingerprint.fingerprint(:watcher, "foo").display_title =~ ~r/^\[Watcher\]/
      assert Fingerprint.fingerprint(:playback, "foo").display_title =~ ~r/^\[Playback\]/
      assert Fingerprint.fingerprint(:phoenix, "foo").display_title =~ ~r/^\[Phoenix\]/
      assert Fingerprint.fingerprint(:ecto, "foo").display_title =~ ~r/^\[Ecto\]/
      assert Fingerprint.fingerprint(:live_view, "foo").display_title =~ ~r/^\[LiveView\]/
      assert Fingerprint.fingerprint(:system, "foo").display_title =~ ~r/^\[System\]/
    end

    test "display_title falls back to capitalized atom for unknown components" do
      assert Fingerprint.fingerprint(:some_new_thing, "foo").display_title =~
               ~r/^\[Some_new_thing\]/
    end

    test "normalized_message reflects Redactor output" do
      %{normalized_message: normalized} =
        Fingerprint.fingerprint(:tmdb, "failed at /data/media/foo.mkv")

      assert normalized =~ "<path>"
    end

    test "display_title truncated to 200 chars" do
      long = String.duplicate("a", 500)
      %{display_title: title} = Fingerprint.fingerprint(:system, long)
      assert String.length(title) <= 200
    end
  end
end
