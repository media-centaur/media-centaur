defmodule MediaCentaur.SelfUpdate.ChangelogTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.SelfUpdate.Changelog

  @fixture """
  # Changelog

  Some preamble prose that must be ignored.

  ## v0.2.0 — 2026-06-09

  ### Improved

  **Second headline.** Second body.

  ## v0.1.0 — 2026-06-01

  ### Fixed

  **First headline.** First body.
  """

  describe "split/1" do
    test "splits versions newest-first with date and body, dropping the preamble" do
      assert [
               %{version: "0.2.0", date: "2026-06-09", body: body2},
               %{version: "0.1.0", date: "2026-06-01", body: body1}
             ] = Changelog.split(@fixture)

      assert body2 =~ "### Improved"
      assert body2 =~ "**Second headline.** Second body."
      refute body2 =~ "v0.1.0"
      assert body1 =~ "**First headline.** First body."
    end

    test "off-format input degrades to an empty list rather than crashing" do
      assert Changelog.split("no version headers here\njust text") == []
    end
  end

  describe "for_version/1 and all/0 over the embedded CHANGELOG" do
    test "all/0 returns a non-empty list of well-formed entries" do
      entries = Changelog.all()
      assert is_list(entries) and entries != []
      assert Enum.all?(entries, &match?(%{version: _, date: _, body: _}, &1))
    end

    test "for_version returns a body for a known version and nil for an unknown one" do
      %{version: known} = hd(Changelog.all())
      assert is_binary(Changelog.for_version(known))
      assert Changelog.for_version("0.0.0-nonexistent") == nil
    end
  end
end
