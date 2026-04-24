defmodule MediaCentarr.ErrorReports.RedactorTest do
  use ExUnit.Case, async: false

  alias MediaCentarr.ErrorReports.Redactor

  describe "normalize/1 regex rules" do
    test "redacts absolute paths" do
      assert Redactor.normalize("file not found: /data/media/shows/Show (2020).mkv") =~
               "<path>"

      refute Redactor.normalize("file not found: /data/media/shows/Show (2020).mkv") =~
               "/data"
    end

    test "redacts UUIDs" do
      input = "entity 3f9c1a2b-4e5d-6f70-aaaa-bbbbccccdddd failed"
      assert Redactor.normalize(input) =~ "<uuid>"
      refute Redactor.normalize(input) =~ "3f9c1a2b"
    end

    test "redacts UUIDs case-insensitively" do
      input = "ID 3F9C1A2B-4E5D-6F70-AAAA-BBBBCCCCDDDD"
      assert Redactor.normalize(input) =~ "<uuid>"
    end

    test "redacts IPv4 addresses" do
      assert Redactor.normalize("connecting to 192.168.1.42") =~ "<ip>"
      refute Redactor.normalize("connecting to 192.168.1.42") =~ "192.168"
    end

    test "redacts emails" do
      assert Redactor.normalize("user shawn@example.com failed") =~ "<email>"
      refute Redactor.normalize("user shawn@example.com failed") =~ "shawn@"
    end

    test "redacts long digit runs (>=3)" do
      assert Redactor.normalize("returned 429 after 12345 ms") =~ "<N>"
    end

    test "preserves 1-2 digit numbers" do
      # Version numbers, small counts remain legible
      assert Redactor.normalize("retry 1 of 5 failed") =~ "retry 1 of 5"
    end

    test "collapses whitespace and trims" do
      assert Redactor.normalize("  foo   bar  \n baz  ") == "foo bar baz"
    end

    test "applies NFC normalization" do
      nfd = "café"
      nfc = "café"
      assert Redactor.normalize(nfd) == nfc
    end
  end

  describe "normalize/1 active-config strip" do
    setup do
      # Stub Config values. The real Config is `:persistent_term`-backed,
      # so we overwrite the key for the test and restore it after.
      original = :persistent_term.get({MediaCentarr.Config, :config})

      patched =
        original
        |> Map.put(:tmdb_api_key, MediaCentarr.Secret.wrap("super_secret_abcdef_1234"))
        |> Map.put(:prowlarr_url, "http://prowlarr.local:9696")
        |> Map.put(:download_client_url, "http://qbit.local:8080")

      :persistent_term.put({MediaCentarr.Config, :config}, patched)

      on_exit(fn ->
        :persistent_term.put({MediaCentarr.Config, :config}, original)
      end)

      :ok
    end

    test "redacts the active TMDB API key" do
      input = "TMDB request failed with key=super_secret_abcdef_1234 at endpoint"
      assert Redactor.normalize(input) =~ "<redacted:api_key>"
      refute Redactor.normalize(input) =~ "super_secret_abcdef_1234"
    end

    test "redacts configured Prowlarr URL" do
      input = "GET http://prowlarr.local:9696/api/v1/foo returned 500"
      assert Redactor.normalize(input) =~ "<redacted:url>"
      refute Redactor.normalize(input) =~ "prowlarr.local"
    end

    test "redacts configured download-client URL" do
      input = "POST http://qbit.local:8080/api/v2/torrents/add failed"
      assert Redactor.normalize(input) =~ "<redacted:url>"
    end

    test "no-op on short/missing API key" do
      original = :persistent_term.get({MediaCentarr.Config, :config})
      patched = Map.put(original, :tmdb_api_key, MediaCentarr.Secret.wrap(""))
      :persistent_term.put({MediaCentarr.Config, :config}, patched)

      on_exit(fn -> :persistent_term.put({MediaCentarr.Config, :config}, original) end)

      input = "error contains the literal string a"
      # empty key must not replace every 'a' in the input
      assert Redactor.normalize(input) == "error contains the literal string a"
    end
  end

  describe "configured_urls/0" do
    test "returns the set of non-nil configured external URLs" do
      original = :persistent_term.get({MediaCentarr.Config, :config})

      patched =
        original
        |> Map.put(:prowlarr_url, "http://p")
        |> Map.put(:download_client_url, nil)

      :persistent_term.put({MediaCentarr.Config, :config}, patched)
      on_exit(fn -> :persistent_term.put({MediaCentarr.Config, :config}, original) end)

      urls = Redactor.configured_urls()
      assert "http://p" in urls
      refute Enum.any?(urls, &is_nil/1)
    end
  end
end
