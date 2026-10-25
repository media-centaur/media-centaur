defmodule MediaCentaurWeb.TvPerformanceCssTest do
  @moduledoc """
  The TV app is the performance floor (UIDR-056, `docs/tv-performance.md`).
  The rules a machine can check about the stylesheet and templates: no
  fixed-attachment background, which Chromium repaints on every scroll
  frame (it held the TV's scrolling to 30 fps), and backdrop blur off on
  a remote player, where the blurred poster cards took 93 ms a frame.
  """

  use MediaCentaur.Case, async: true

  # Declarations only: comments explain the rules by naming what they forbid.
  @css "assets/css/app.css" |> File.read!() |> String.replace(~r{/\*.*?\*/}s, "")

  test "no stylesheet rule fixes a background to the viewport" do
    refute @css =~ ~r/background-attachment:\s*fixed/
  end

  test "no template uses Tailwind's fixed-background utility" do
    offenders =
      Enum.filter(
        Path.wildcard("lib/media_centaur_web/**/*.{ex,heex}"),
        &(File.read!(&1) =~ ~r/["\s]bg-fixed["\s]/)
      )

    assert offenders == []
  end

  test "a remote player turns every backdrop blur off" do
    assert @css =~ ~r/html\[data-player="remote"\] \*[^{]*\{\s*backdrop-filter:\s*none !important;/
  end
end
