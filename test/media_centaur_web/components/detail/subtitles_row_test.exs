defmodule MediaCentaurWeb.Components.Detail.SubtitlesRowTest do
  use ExUnit.Case, async: true

  alias MediaCentaurWeb.Components.Detail.SubtitlesRow

  # The rendering decision is the per-entry label; the row structure (empty
  # → nothing, separators between entries) is verified by the storybook
  # variations (subtitles_row.story.exs covers [], single, multi, nil, mix).
  describe "language_label/1" do
    test "an unknown-language sidecar (nil) reads as 'external'" do
      assert SubtitlesRow.language_label(nil) == "external"
    end

    test "a recognised ISO 639-1 code renders verbatim" do
      assert SubtitlesRow.language_label("en") == "en"
      assert SubtitlesRow.language_label("pt") == "pt"
    end
  end
end
