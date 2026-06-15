# Guide book — Phase 0 implementation plan (infrastructure + pilot chapter)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. REQUIRED SUB-SKILL when authoring the pilot chapter prose: the `writing-copy` skill. REQUIRED SUB-SKILL before writing any test/impl: automated-testing (this repo is test-first).

**Goal:** Stand up the in-app guide vertical slice — markdown chapters in `priv/guide/`, an Earmark-based renderer, a deep-linkable `/guide` route with the book layout, a Settings → System link, and one fully-authored pilot chapter — proving the whole pipeline before farming the remaining 18 chapters.

**Architecture:** Chapters are markdown files with light frontmatter under `priv/guide/`. A compile-time `Guide.Library` reads and parses them into an ordered Parts→Chapters index (each file registered via `@external_resource` so edits trigger recompile). `Guide.Renderer` turns the Earmark AST into styled HEEx, handling callouts, cross-links, code, tables, and heading anchors, and extracts an on-this-page outline. `GuideLive` serves `/guide` and `/guide/:slug` with a sidebar + reading pane + outline.

**Tech Stack:** Elixir/Phoenix LiveView, **Earmark** (pure-Elixir CommonMark → AST; chosen over MDEx to avoid native code / per-target NIFs — see campaign decision), Tailwind/daisyUI for styling, ExUnit + LazyHTML/Phoenix.LiveViewTest.

**Scope note:** Rendering lives in plain modules and LiveView-local markup, **not** catalogued function components, to avoid the MC0009 storybook requirement in Phase 0. If a reusable function component is later extracted under `components/**`, it must ship a story in the same change.

---

## File structure

- Create: `priv/guide/how-identification-works.md` — pilot chapter content.
- Create: `lib/media_centaur/guide.ex` — public context: `chapters/0`, `parts/0`, `fetch_chapter/1`.
- Create: `lib/media_centaur/guide/chapter.ex` — `%Chapter{}` struct + frontmatter parsing.
- Create: `lib/media_centaur/guide/library.ex` — compile-time load/index of `priv/guide/*.md`.
- Create: `lib/media_centaur/guide/renderer.ex` — Earmark AST → HEEx + outline extraction.
- Create: `lib/media_centaur_web/live/guide_live.ex` — the `/guide` page.
- Modify: `lib/media_centaur_web/router.ex` — add `/guide` and `/guide/:slug` routes.
- Modify: `lib/media_centaur_web/live/settings_live/system_section.ex` — add the entry link.
- Modify: `mix.exs` — add `{:earmark, "~> 1.4"}`.
- Tests: `test/media_centaur/guide/chapter_test.exs`, `test/media_centaur/guide/library_test.exs`, `test/media_centaur/guide/renderer_test.exs`, `test/media_centaur_web/live/guide_live_test.exs`.

Boundary: if contexts use `use Boundary`, `MediaCentaur.Guide` is a new context — declare it and add `MediaCentaur.Guide` to the web layer's deps. Check a sibling context (e.g. `lib/media_centaur/retention.ex`) for the exact `use Boundary` shape and mirror it.

---

### Task 1: Add the Earmark dependency

**Files:**
- Modify: `mix.exs`

- [ ] **Step 1: Add the dep**

In `mix.exs` `deps/0`, add (keep the list alphabetized if it is):

```elixir
{:earmark, "~> 1.4"},
```

- [ ] **Step 2: Fetch and compile**

Run: `mix deps.get && mix compile`
Expected: Earmark fetched and compiled, no warnings.

- [ ] **Step 3: Verify the AST shape in IEx** (informs every render clause below)

Run:
```bash
mix run -e 'IO.inspect(Earmark.as_ast("## Hi\n\nA `b` and [c](/guide/x).\n\n> [!NOTE]\n> heads up", gfm: true), limit: :infinity)'
```
Expected: `{:ok, ast, _warnings}` where `ast` is a list of 4-tuples `{tag, attrs, children, meta}` (strings for text). **Record the exact tag/attr shapes** (e.g. `{"h2", [], ["Hi"], %{}}`, `{"a", [{"href", "/guide/x"}], ["c"], %{}}`, blockquote shape for the `[!NOTE]`). The renderer clauses in Task 5 must match what you see here.

- [ ] **Step 4: Commit**

```bash
git add mix.exs mix.lock
git commit -m "build: add earmark for guide markdown rendering"
```

---

### Task 2: Chapter struct + frontmatter parser

A chapter file starts with a YAML-ish frontmatter block we parse by hand (no YAML dep — same instinct as the existing ReleaseNotes parser). Only four keys: `title`, `part`, `slug`, `order`.

**Files:**
- Create: `lib/media_centaur/guide/chapter.ex`
- Test: `test/media_centaur/guide/chapter_test.exs`

- [ ] **Step 1: Write the failing test**

```elixir
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
end
```

- [ ] **Step 2: Run it, verify it fails**

Run: `mix test test/media_centaur/guide/chapter_test.exs`
Expected: FAIL (`MediaCentaur.Guide.Chapter` undefined).

- [ ] **Step 3: Implement**

```elixir
defmodule MediaCentaur.Guide.Chapter do
  @moduledoc """
  A single guide chapter: parsed frontmatter plus the raw markdown body.

  Frontmatter is a small fixed key set (`title`, `part`, `slug`, `order`)
  delimited by `---` lines at the top of the file. Parsed by hand to avoid
  a YAML dependency, matching the project's lean-deps instinct.
  """

  @enforce_keys [:title, :part, :slug, :order, :body]
  defstruct [:title, :part, :slug, :order, :body]

  @type t :: %__MODULE__{
          title: String.t(),
          part: String.t(),
          slug: String.t(),
          order: non_neg_integer(),
          body: String.t()
        }

  @spec parse(String.t()) :: {:ok, t()} | {:error, term()}
  def parse(raw) when is_binary(raw) do
    with {:ok, fm_block, body} <- split(raw),
         {:ok, fields} <- parse_fields(fm_block) do
      {:ok,
       %__MODULE__{
         title: fields["title"],
         part: fields["part"],
         slug: fields["slug"],
         order: String.to_integer(fields["order"]),
         body: String.trim(body)
       }}
    end
  end

  defp split(raw) do
    case String.split(raw, ~r/\A---\n(.*?)\n---\n/s, parts: 2, include_captures: true) do
      ["", capture, body] ->
        [_, fm, _] = Regex.run(~r/\A---\n(.*?)\n---\n/s, capture)
        {:ok, fm, body}

      _ ->
        {:error, :missing_frontmatter}
    end
  end

  @required ~w(title part slug order)
  defp parse_fields(block) do
    fields =
      block
      |> String.split("\n", trim: true)
      |> Map.new(fn line ->
        [k, v] = String.split(line, ":", parts: 2)
        {String.trim(k), String.trim(v)}
      end)

    if Enum.all?(@required, &Map.has_key?(fields, &1)),
      do: {:ok, fields},
      else: {:error, {:missing_keys, @required -- Map.keys(fields)}}
  end
end
```

- [ ] **Step 4: Run it, verify it passes**

Run: `mix test test/media_centaur/guide/chapter_test.exs`
Expected: PASS. (If `split/1` is fiddly, simplify by matching the literal `"---\n"` boundaries with `String.split(raw, "---\n", parts: 3)` and treating part 2 as frontmatter, part 3 as body — adjust the test only if behavior is equivalent.)

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur/guide/chapter.ex test/media_centaur/guide/chapter_test.exs
git commit -m "feat(guide): chapter struct + frontmatter parser"
```

---

### Task 3: Compile-time chapter library + public context

**Files:**
- Create: `lib/media_centaur/guide/library.ex`
- Create: `lib/media_centaur/guide.ex`
- Test: `test/media_centaur/guide/library_test.exs`

For the test to have content, create a throwaway fixture chapter now (the real pilot lands in Task 8):

`priv/guide/how-identification-works.md`:
```markdown
---
title: How identification works
part: Your library
slug: how-identification-works
order: 4
---
Placeholder body — replaced in Task 8.
```

- [ ] **Step 1: Write the failing test**

```elixir
defmodule MediaCentaur.Guide.LibraryTest do
  use ExUnit.Case, async: true

  test "loads chapters ordered by :order" do
    chapters = MediaCentaur.Guide.chapters()
    assert Enum.any?(chapters, &(&1.slug == "how-identification-works"))
    orders = Enum.map(chapters, & &1.order)
    assert orders == Enum.sort(orders)
  end

  test "fetch_chapter/1 returns {:ok, chapter} for a known slug" do
    assert {:ok, ch} = MediaCentaur.Guide.fetch_chapter("how-identification-works")
    assert ch.title == "How identification works"
  end

  test "fetch_chapter/1 returns :error for an unknown slug" do
    assert :error = MediaCentaur.Guide.fetch_chapter("nope")
  end
end
```

- [ ] **Step 2: Run it, verify it fails**

Run: `mix test test/media_centaur/guide/library_test.exs`
Expected: FAIL (`MediaCentaur.Guide` undefined).

- [ ] **Step 3: Implement the library (compile-time load)**

```elixir
defmodule MediaCentaur.Guide.Library do
  @moduledoc """
  Loads and indexes guide chapters from `priv/guide/*.md` at COMPILE TIME.

  Each markdown file is registered as an `@external_resource`, so editing a
  chapter triggers a recompile (the dev workflow is `recompile` in IEx).
  Parsing at compile time means zero runtime file IO and an immutable index,
  matching the desktop-app rendering defaults.
  """
  alias MediaCentaur.Guide.Chapter

  @guide_dir Application.app_dir(:media_centaur, "priv/guide")

  paths = Path.wildcard(Path.join(@guide_dir, "*.md"))
  for path <- paths, do: @external_resource(path)

  @chapters paths
            |> Enum.map(fn path ->
              {:ok, chapter} = path |> File.read!() |> Chapter.parse()
              chapter
            end)
            |> Enum.sort_by(& &1.order)

  @spec chapters() :: [Chapter.t()]
  def chapters, do: @chapters

  @by_slug Map.new(@chapters, &{&1.slug, &1})

  @spec fetch(String.t()) :: {:ok, Chapter.t()} | :error
  def fetch(slug), do: Map.fetch(@by_slug, slug)
end
```

```elixir
defmodule MediaCentaur.Guide do
  @moduledoc """
  Public context for the in-app guide. Read-only access to the compiled
  chapter index. See `MediaCentaur.Guide.Library` for the load mechanism
  and `MediaCentaur.Guide.Renderer` for markdown → HEEx.
  """
  alias MediaCentaur.Guide.{Chapter, Library}

  @spec chapters() :: [Chapter.t()]
  defdelegate chapters(), to: Library

  @doc "Chapters grouped into ordered parts: `[{part_name, [chapter]}]`."
  @spec parts() :: [{String.t(), [Chapter.t()]}]
  def parts do
    chapters()
    |> Enum.chunk_by(& &1.part)
    |> Enum.map(fn [%{part: part} | _] = chs -> {part, chs} end)
  end

  @spec fetch_chapter(String.t()) :: {:ok, Chapter.t()} | :error
  defdelegate fetch_chapter(slug), to: Library, as: :fetch
end
```

- [ ] **Step 4: Run it, verify it passes**

Run: `mix test test/media_centaur/guide/library_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur/guide.ex lib/media_centaur/guide/library.ex priv/guide/how-identification-works.md test/media_centaur/guide/library_test.exs
git commit -m "feat(guide): compile-time chapter index + public context"
```

---

### Task 4: Renderer — markdown AST → HEEx, with anchors, callouts, cross-links

Render the Earmark AST to HEEx via a recursive walk. Use the exact tag/attr shapes recorded in Task 1, Step 3. This task covers headings (with slugified `id` anchors), paragraphs, lists, links, inline code, code blocks, and tables. Callout (GitHub-alert blockquote) handling is its own clause.

**Files:**
- Create: `lib/media_centaur/guide/renderer.ex`
- Test: `test/media_centaur/guide/renderer_test.exs`

- [ ] **Step 1: Write the failing test**

```elixir
defmodule MediaCentaur.Guide.RendererTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest, only: [rendered_to_string: 1]
  alias MediaCentaur.Guide.Renderer

  defp html(md), do: md |> Renderer.to_heex() |> rendered_to_string()

  test "renders a heading with a slugified anchor id" do
    assert html("## How it works") =~ ~s(id="how-it-works")
    assert html("## How it works") =~ "How it works"
  end

  test "renders inline code and links" do
    out = html("See `ffprobe` and [the queue](/guide/the-review-queue).")
    assert out =~ "<code"
    assert out =~ "ffprobe"
    assert out =~ ~s(href="/guide/the-review-queue")
  end

  test "renders a GitHub-style note callout" do
    out = html("> [!NOTE]\n> ffprobe unlocks track detection.")
    assert out =~ "ffprobe unlocks track detection."
    # callout wrapper carries a data attribute we can assert on
    assert out =~ ~s(data-callout="note")
  end
end
```

- [ ] **Step 2: Run it, verify it fails**

Run: `mix test test/media_centaur/guide/renderer_test.exs`
Expected: FAIL (`Renderer` undefined).

- [ ] **Step 3: Implement the renderer**

Note: the clauses below assume Earmark's standard 4-tuple AST. **Adjust attr access to match what Task 1/Step 3 printed.** `to_heex/1` returns a `Phoenix.LiveView.Rendered` struct (HEEx), so the LiveView can interpolate it directly.

```elixir
defmodule MediaCentaur.Guide.Renderer do
  @moduledoc """
  Renders guide markdown to HEEx via Earmark's AST.

  We walk the AST ourselves (rather than emitting Earmark's HTML string) so
  we control styling, add heading anchors for deep-linking and the
  on-this-page outline, turn GitHub-style alert blockquotes (`> [!NOTE]`)
  into styled callouts, and keep cross-links as in-app navigation.
  """
  use Phoenix.Component

  @doc "Render markdown to a HEEx rendered struct."
  def to_heex(markdown) when is_binary(markdown) do
    {:ok, ast, _warnings} = Earmark.as_ast(markdown, gfm: true)
    assigns = %{nodes: ast}

    ~H"""
    <div class="guide-prose space-y-4 leading-relaxed text-base-content/85">
      <.node :for={n <- @nodes} node={n} />
    </div>
    """
  end

  @doc "Extract the on-this-page outline: `[{level, text, anchor}]` for h2/h3."
  def outline(markdown) when is_binary(markdown) do
    {:ok, ast, _} = Earmark.as_ast(markdown, gfm: true)

    for {tag, _attrs, children, _meta} <- ast, tag in ~w(h2 h3) do
      text = node_text(children)
      {String.to_integer(String.trim_leading(tag, "h")), text, slugify(text)}
    end
  end

  # --- node dispatch -------------------------------------------------------

  attr :node, :any, required: true

  # Headings: add a slugified id so anchors + outline links resolve.
  defp node(%{node: {tag, _a, children, _m}} = assigns) when tag in ~w(h1 h2 h3 h4) do
    assigns = assign(assigns, anchor: slugify(node_text(children)), children: children, tag: tag)

    ~H"""
    <.dynamic_tag name={@tag} id={@anchor} class={heading_class(@tag)}>
      <.node :for={c <- @children} node={c} />
    </.dynamic_tag>
    """
  end

  # GitHub alert blockquote → callout. Detect the `[!NOTE]` marker in the
  # first paragraph's leading text. Falls back to a plain blockquote.
  defp node(%{node: {"blockquote", _a, children, _m}} = assigns) do
    case callout_kind(children) do
      {kind, rest} ->
        assigns = assign(assigns, kind: kind, rest: rest)

        ~H"""
        <aside data-callout={@kind} class={callout_class(@kind)}>
          <.node :for={c <- @rest} node={c} />
        </aside>
        """

      :plain ->
        assigns = assign(assigns, children: children)

        ~H"""
        <blockquote class="border-l-2 border-base-content/20 pl-4 italic">
          <.node :for={c <- @children} node={c} />
        </blockquote>
        """
    end
  end

  defp node(%{node: {"a", attrs, children, _m}} = assigns) do
    assigns = assign(assigns, href: attr(attrs, "href"), children: children)

    ~H"""
    <.link navigate={@href} class="text-primary underline underline-offset-2 hover:opacity-80">
      <.node :for={c <- @children} node={c} />
    </.link>
    """
  end

  defp node(%{node: {"code", _a, children, _m}} = assigns) do
    assigns = assign(assigns, children: children)

    ~H"""
    <code class="font-mono text-sm px-1 py-0.5 rounded bg-base-content/10">
      <.node :for={c <- @children} node={c} />
    </code>
    """
  end

  defp node(%{node: {"pre", _a, children, _m}} = assigns) do
    assigns = assign(assigns, children: children)

    ~H"""
    <pre class="font-mono text-sm p-3 rounded bg-base-300 overflow-x-auto"><.node :for={c <- @children} node={c} /></pre>
    """
  end

  # Generic passthrough for p, ul, ol, li, strong, em, table, thead, tbody,
  # tr, th, td, etc. Keep a small class map; default to no class.
  defp node(%{node: {tag, _a, children, _m}} = assigns) do
    assigns = assign(assigns, tag: tag, children: children)

    ~H"""
    <.dynamic_tag name={@tag} class={generic_class(@tag)}>
      <.node :for={c <- @children} node={c} />
    </.dynamic_tag>
    """
  end

  # Text node.
  defp node(%{node: text} = assigns) when is_binary(text) do
    assigns = assign(assigns, text: text)
    ~H"{@text}"
  end

  # --- helpers -------------------------------------------------------------

  defp attr(attrs, key) do
    Enum.find_value(attrs, fn {k, v} -> if k == key, do: v end)
  end

  defp node_text(children) do
    children
    |> List.wrap()
    |> Enum.map_join("", fn
      t when is_binary(t) -> t
      {_tag, _a, kids, _m} -> node_text(kids)
    end)
  end

  defp callout_kind(children) do
    text = node_text(children)

    case Regex.run(~r/\A\s*\[!(NOTE|TIP|WARNING|IMPORTANT)\]\s*/i, text) do
      [_full, kind] -> {String.downcase(kind), strip_marker(children)}
      _ -> :plain
    end
  end

  # Remove the `[!NOTE]` marker text from the first child paragraph.
  defp strip_marker(children) do
    # Implementation detail: map over children, and in the first text-bearing
    # node, drop the leading `[!KIND]` token. Verify against the blockquote
    # AST shape from Task 1/Step 3 (the marker may sit in a `p` child).
    Enum.map(children, fn
      {"p", a, kids, m} -> {"p", a, drop_leading_marker(kids), m}
      other -> other
    end)
  end

  defp drop_leading_marker([first | rest]) when is_binary(first),
    do: [Regex.replace(~r/\A\s*\[![A-Z]+\]\s*/i, first, "") | rest]

  defp drop_leading_marker(kids), do: kids

  defp slugify(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "-")
    |> String.trim("-")
  end

  defp heading_class("h2"), do: "text-xl font-semibold text-base-content pt-4 scroll-mt-20"
  defp heading_class("h3"), do: "text-lg font-semibold text-base-content pt-2 scroll-mt-20"
  defp heading_class(_), do: "font-semibold text-base-content scroll-mt-20"

  defp callout_class("warning"), do: "rounded-md border border-warning/40 bg-warning/10 p-3 space-y-2"
  defp callout_class("tip"), do: "rounded-md border border-success/40 bg-success/10 p-3 space-y-2"
  defp callout_class(_), do: "rounded-md border border-info/40 bg-info/10 p-3 space-y-2"

  defp generic_class("ul"), do: "list-disc pl-5 space-y-1"
  defp generic_class("ol"), do: "list-decimal pl-5 space-y-1"
  defp generic_class("table"), do: "w-full text-sm border-collapse"
  defp generic_class("th"), do: "text-left font-semibold border-b border-base-content/20 p-2"
  defp generic_class("td"), do: "border-b border-base-content/10 p-2"
  defp generic_class("strong"), do: "font-semibold text-base-content"
  defp generic_class(_), do: nil
end
```

- [ ] **Step 4: Run it, verify it passes**

Run: `mix test test/media_centaur/guide/renderer_test.exs`
Expected: PASS. If a clause doesn't match the real AST, fix the pattern to the shape from Task 1/Step 3 — do not change the assertions.

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur/guide/renderer.ex test/media_centaur/guide/renderer_test.exs
git commit -m "feat(guide): markdown→HEEx renderer with anchors, callouts, links"
```

---

### Task 5: GuideLive + routes + book layout

**Files:**
- Create: `lib/media_centaur_web/live/guide_live.ex`
- Modify: `lib/media_centaur_web/router.ex`
- Test: `test/media_centaur_web/live/guide_live_test.exs`

- [ ] **Step 1: Add routes**

In `router.ex`, inside the same `live_session :default` block that holds the other pages:

```elixir
live "/guide", GuideLive, :index
live "/guide/:slug", GuideLive, :show
```

(Alias `GuideLive` consistent with how the other lives are referenced in that block.)

- [ ] **Step 2: Write the failing test**

```elixir
defmodule MediaCentaurWeb.GuideLiveTest do
  use MediaCentaurWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  test "GET /guide renders the first chapter and the sidebar", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/guide")
    assert html =~ "How identification works"
    # sidebar lists the part
    assert html =~ "Your library"
  end

  test "deep link /guide/:slug renders that chapter", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/guide/how-identification-works")
    assert html =~ "How identification works"
  end

  test "unknown slug redirects to the guide index", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/guide"}}} =
             live(conn, ~p"/guide/does-not-exist")
  end
end
```

- [ ] **Step 3: Run it, verify it fails**

Run: `mix test test/media_centaur_web/live/guide_live_test.exs`
Expected: FAIL (`GuideLive` undefined / route missing).

- [ ] **Step 4: Implement GuideLive**

```elixir
defmodule MediaCentaurWeb.GuideLive do
  @moduledoc """
  The in-app guide at `/guide` and `/guide/:slug`. Sidebar of parts →
  chapters, a reading pane rendering the current chapter's markdown, and an
  on-this-page outline. Entry point: Settings → System (not the main nav).
  """
  use MediaCentaurWeb, :live_view

  alias MediaCentaur.Guide
  alias MediaCentaur.Guide.Renderer

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, parts: Guide.parts(), page_title: "Guide")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    slug = params["slug"] || default_slug()

    case Guide.fetch_chapter(slug) do
      {:ok, chapter} ->
        {:noreply,
         assign(socket,
           chapter: chapter,
           body: Renderer.to_heex(chapter.body),
           outline: Renderer.outline(chapter.body)
         )}

      :error ->
        {:noreply, push_navigate(socket, to: ~p"/guide")}
    end
  end

  defp default_slug do
    case Guide.chapters() do
      [first | _] -> first.slug
      [] -> ""
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex gap-8 max-w-6xl mx-auto p-6">
      <nav class="w-56 shrink-0 sticky top-6 self-start space-y-4">
        <div :for={{part, chapters} <- @parts}>
          <div class="text-xs uppercase tracking-wider text-base-content/50 mb-1">{part}</div>
          <.link
            :for={ch <- chapters}
            patch={~p"/guide/#{ch.slug}"}
            class={[
              "block px-2 py-1 rounded text-sm",
              ch.slug == @chapter.slug && "bg-base-content/10 text-base-content",
              ch.slug != @chapter.slug && "text-base-content/70 hover:bg-base-content/5"
            ]}
          >
            {ch.title}
          </.link>
        </div>
      </nav>

      <article class="min-w-0 flex-1">
        <h1 class="text-2xl font-bold text-base-content mb-4">{@chapter.title}</h1>
        {@body}
      </article>

      <aside :if={@outline != []} class="w-48 shrink-0 sticky top-6 self-start hidden xl:block">
        <div class="text-xs uppercase tracking-wider text-base-content/50 mb-1">On this page</div>
        <a
          :for={{level, text, anchor} <- @outline}
          href={"#" <> anchor}
          class={["block text-sm text-base-content/60 hover:text-base-content py-0.5", level == 3 && "pl-3"]}
        >
          {text}
        </a>
      </aside>
    </div>
    """
  end
end
```

- [ ] **Step 5: Run it, verify it passes**

Run: `mix test test/media_centaur_web/live/guide_live_test.exs`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/media_centaur_web/live/guide_live.ex lib/media_centaur_web/router.ex test/media_centaur_web/live/guide_live_test.exs
git commit -m "feat(guide): GuideLive page with sidebar, reading pane, outline"
```

---

### Task 6: Settings → System entry link

**Files:**
- Modify: `lib/media_centaur_web/live/settings_live/system_section.ex`
- Test: extend `test/media_centaur_web/live/settings_live_test.exs` (or wherever the System section is tested — find it first with `grep -rl "system_section\|System" test/media_centaur_web/live/`)

- [ ] **Step 1: Write the failing test**

Add to the existing settings live test (match its setup/use):

```elixir
test "System section links to the guide", %{conn: conn} do
  {:ok, _view, html} = live(conn, ~p"/settings?section=system")
  assert html =~ ~p"/guide"
  assert html =~ "Guide"
end
```

- [ ] **Step 2: Run it, verify it fails**

Run: `mix test test/media_centaur_web/live/settings_live_test.exs -k "links to the guide"`
Expected: FAIL.

- [ ] **Step 3: Implement — add the link**

In `system_section.ex`, add a link in a sensible spot in the System section markup. Copy follows the `writing-copy` skill (reader-first, plain):

```heex
<.link navigate={~p"/guide"} class="text-primary underline underline-offset-2">
  Open the guide
</.link>
<p class="text-sm text-base-content/60">
  How Media Centaur works, chapter by chapter — including features you may not be using yet.
</p>
```

- [ ] **Step 4: Run it, verify it passes**

Run: `mix test test/media_centaur_web/live/settings_live_test.exs -k "links to the guide"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur_web/live/settings_live/system_section.ex test/media_centaur_web/live/settings_live_test.exs
git commit -m "feat(guide): link to the guide from Settings → System"
```

---

### Task 7: Author the pilot chapter (replaces the placeholder)

**REQUIRED SUB-SKILL: `writing-copy`.** This chapter is the proof that the voice + discovery objective land in real content.

**Files:**
- Modify: `priv/guide/how-identification-works.md`

- [ ] **Step 1: Study the source first**

Read the actual ingestion path before writing a word (do not write from memory):
- The Broadway pipeline stages — `grep -ri "Broadway" lib/media_centaur/` and `docs/pipeline.md`.
- The parser — find it via the parser test `test/media_centaur/parser_test.exs`, read the module it exercises.
- TMDB matching + the confidence threshold that routes to Review.
- Note the **non-obvious capabilities** to surface (discovery objective): e.g. what filename shapes the parser handles, how to report an unparsed name, where the Review queue catches low-confidence matches.

- [ ] **Step 2: Write the chapter**

Replace the file body. Apply `writing-copy`: build antecedents in order, plain/operational, true names, link to source on `main` and the issue tracker, close with a short takeaway. Include one `> [!NOTE]` or `> [!TIP]` callout that surfaces a capability the reader probably isn't using, and a cross-link to the (future) Review queue chapter. Keep frontmatter intact.

```markdown
---
title: How identification works
part: Your library
slug: how-identification-works
order: 4
---
When a new file is detected in a watched directory, it's processed automatically
through the ingestion pipeline. The pipeline parses the file and folder names and
attempts to find a TMDB match. If it matches, the file is added as a new library entry.

Filename parsing is done with a series of string-matching algorithms against known
formats. [Submit an issue](https://github.com/<owner>/<repo>/issues/new) to share a
filename that wasn't parsed correctly so we can improve the parser. The
[parsing code is here](https://github.com/<owner>/<repo>/blob/main/lib/.../parser.ex).

When a file can't be matched to TMDB at a sufficient confidence, it lands in the
Review queue, where you match it by hand.

> [!TIP]
> <a discovery-oriented tip surfaced from Step 1 — e.g. what ffprobe enables, or a
> filename convention that improves matching>

In short, drop correctly-named files into a watched directory and they identify
themselves; anything ambiguous waits for you in the Review queue rather than guessing.
```

Replace `<owner>/<repo>` and the exact parser path with the real values found in Step 1. Verify the GitHub repo URL against `git remote -v`.

- [ ] **Step 3: Render check (manual, in the running app)**

The dev asset watchers are off and chapters load at compile time — after editing, `recompile` in the IEx session (or restart it), then load `http://localhost:1080/guide/how-identification-works`. Confirm: heading anchors, the callout renders styled, links work, the outline lists sections.

- [ ] **Step 4: Commit**

```bash
git add priv/guide/how-identification-works.md
git commit -m "docs(guide): pilot chapter — how identification works"
```

---

### Task 8: Precommit + boundary

- [ ] **Step 1: Full precommit**

Run: `MIX_OS_DEPS_COMPILE_PARTITION_COUNT=8 mix precommit`
Expected: green. Fix every warning (zero-warnings policy). If Boundary complains, add the `MediaCentaur.Guide` context declaration and the web-layer dep as noted in File structure.

- [ ] **Step 2: Flake check on the new tests**

Run: `mix test test/media_centaur/guide/ test/media_centaur_web/live/guide_live_test.exs --repeat-until-failure 20`
Expected: 20× green.

- [ ] **Step 3: Final commit if anything changed**

```bash
git add -A -- lib/ test/ priv/ mix.exs
git commit -m "chore(guide): precommit fixes for phase 0"
```

(Use a path-scoped `git add` so a concurrently-working agent's files are never swept in.)

---

## Self-review (run before handing off)

- **Spec coverage:** markdown-as-source ✓ (priv/guide), `/guide` deep-linkable ✓ (routes), Settings entry only ✓ (Task 6, no nav change), text-first reading UI ✓ (sidebar/pane/outline), callouts/code/tables/links ✓ (Task 4), voice + source links + discovery ✓ (Task 7), no wiki export ✓ (absent by design).
- **Deferred to later phases (not Phase 0):** kbd-chip styling, gamepad glyphs, client-side filter (Phase 0 ships sidebar without the filter — add filter in Phase 1 or as polish), full-text search, screenshots. Sidebar title filter is intentionally **not** in Phase 0; note this so it isn't mistaken for missing.
- **Type consistency:** `Chapter` fields (`title/part/slug/order/body`) used identically in Library, Guide, GuideLive. `Renderer.to_heex/1` + `Renderer.outline/1` signatures match GuideLive calls.
- **Concurrency safety:** every commit uses path-scoped `git add`; only `system_section.ex` and `router.ex` are shared files and the other agent is in `presentable_queries.ex`/`subtitles.ex` — confirm no overlap before editing.

## Open items the implementer must resolve

1. Exact Earmark AST tag/attr shapes (Task 1, Step 3) — every `Renderer` clause depends on it.
2. The real parser module path + GitHub repo slug for the pilot chapter's source links (Task 7).
3. Whether `MediaCentaur.Guide` needs a `use Boundary` declaration (mirror a sibling context).
