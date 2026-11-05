defmodule MediaCentaur.Guide.GuideWordsTest do
  @moduledoc """
  The in-app guide speaks the UI's words. A download goal is a *download*,
  the client's item a *job*, a release tried a *release* (the owner's
  decision of 2026-11-05 in `pursuit-window.md`, a campaign completed and
  removed — see git history); "pursuit" is the code's word
  and never reaches a reader. The web layer was swept by a Credo scaffold
  (MC0044) during the campaign and that check left with it; the guide is
  markdown, and this test holds the line there.
  """
  use MediaCentaur.Case, async: true

  @code_word ~r/(?<![\w\-])pursuits?(?![\w\-])/i

  test "no guide chapter says \"pursuit\"" do
    offenders =
      for chapter <- MediaCentaur.Guide.chapters(),
          {line, number} <- Enum.with_index(String.split(chapter.body, "\n"), 1),
          Regex.match?(@code_word, line),
          do: "#{chapter.slug}:#{number}: #{String.trim(line)}"

    assert offenders == [],
           ~s(the guide says "pursuit" where the UI says "download":\n) <> Enum.join(offenders, "\n")
  end

  test "no guide chapter is titled or addressed by the code's word" do
    for chapter <- MediaCentaur.Guide.chapters() do
      refute Regex.match?(@code_word, chapter.title), "chapter title: #{chapter.title}"
      refute Regex.match?(@code_word, chapter.slug), "chapter slug: #{chapter.slug}"
    end
  end
end
