defmodule MediaCentarr.ErrorReports.RedactorTest do
  use ExUnit.Case, async: true

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
end
