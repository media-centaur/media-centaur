defmodule MediaCentaurWeb.GuideMarkdownTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [rendered_to_string: 1]

  alias MediaCentaurWeb.GuideMarkdown

  defp html(md), do: md |> GuideMarkdown.to_heex() |> rendered_to_string()

  test "renders a heading with a slugified anchor id" do
    out = html("## How it works")
    assert out =~ ~s(id="how-it-works")
    assert out =~ "How it works"
  end

  test "fenced code blocks render tight — no leading blank line or indent" do
    out = html("Install:\n\n```sh\ngit clone x\ncp a b\n```")
    [_, code] = Regex.run(~r/<code[^>]*>(.*?)<\/code>/s, out)
    assert String.starts_with?(code, "git clone"), "code began with whitespace: #{inspect(code)}"
    refute String.starts_with?(code, "\n")
    refute String.ends_with?(code, "\n")
  end

  test "renders inline code and an internal cross-link" do
    out = html("See `ffprobe` and [the queue](/guide/the-review-queue).")
    assert out =~ "<code"
    assert out =~ "ffprobe"
    assert out =~ ~s(href="/guide/the-review-queue")
  end

  test "renders an external link in a new tab" do
    out = html("[issue](https://github.com/owner/repo/issues)")
    assert out =~ ~s(href="https://github.com/owner/repo/issues")
    assert out =~ ~s(target="_blank")
  end

  test "renders a GitHub-style note callout and strips the marker" do
    out = html("> [!NOTE]\n> ffprobe unlocks track detection.")
    assert out =~ "ffprobe unlocks track detection."
    assert out =~ ~s(data-callout="note")
    refute out =~ "[!NOTE]"
  end

  test "outline/1 extracts h2/h3 headings with anchors" do
    outline = GuideMarkdown.outline("## First\n\ntext\n\n### Sub\n\n## Second")
    assert {2, "First", "first"} in outline
    assert {3, "Sub", "sub"} in outline
    assert {2, "Second", "second"} in outline
  end
end
