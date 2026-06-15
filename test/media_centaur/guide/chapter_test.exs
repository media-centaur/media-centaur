defmodule MediaCentaur.Guide.ChapterTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Guide.Chapter

  test "parses frontmatter and body from raw file content" do
    raw = """
    ---
    title: How identification works
    part: Your library
    slug: how-identification-works
    order: 4
    ---
    When a new file is detected in a watched directory, it's processed.
    """

    assert {:ok, %Chapter{} = ch} = Chapter.parse(raw)
    assert ch.title == "How identification works"
    assert ch.part == "Your library"
    assert ch.slug == "how-identification-works"
    assert ch.order == 4
    assert ch.body =~ "watched directory"
    refute ch.body =~ "title:"
  end

  test "returns an error when frontmatter is missing required keys" do
    raw = "---\ntitle: Only a title\n---\nbody"
    assert {:error, _reason} = Chapter.parse(raw)
  end

  test "returns an error when there is no frontmatter block" do
    assert {:error, _reason} = Chapter.parse("# Just a heading\n\nbody")
  end
end
