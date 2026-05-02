defmodule MediaCentarrWeb.Storybook.Foundations.Typography do
  @moduledoc """
  Typography foundations — type scale, weights, and numeric guidance.

  No custom font families are configured in `assets/css/app.css`; the app
  uses Tailwind's default `font-sans` (system UI stack) for body and
  display copy, and the monospace stack `ui-monospace, "JetBrains Mono",
  "SF Mono", Menlo, Consolas, monospace` for code-like content (used by
  the console panel and applied via `font-mono` here).

  All Tailwind classes shown below are **literal**. Tailwind v4 scans
  source for verbatim class names and emits CSS only for what it sees,
  so interpolated classes like `text-\#{size}` would render unstyled.
  The `prefix_psb/1` helper rewrites a list of unprefixed classes into
  `psb:`-prefixed equivalents so the same class string can drive both
  the rendered preview (inside storybook chrome, which scopes everything
  under `psb:`) and the visible code label next to it (the unprefixed
  form, which is what a contributor would type in HEEx).
  """

  use PhoenixStorybook.Story, :page

  def doc, do: "Type scale, weights, and tabular-nums guidance."

  def render(assigns) do
    ~H"""
    <div class="psb:p-6 psb:max-w-5xl psb:mx-auto psb:space-y-12">
      <header>
        <h1 class="psb:text-2xl psb:font-semibold psb:mb-2">Typography</h1>
        <p class="psb:text-sm psb:text-slate-500">
          System default sans for body and display, monospace stack for code-like
          content. No custom font families — relies on Tailwind defaults. Sizes,
          weights, and tracking shown below are the literal Tailwind utility
          classes used across the app.
        </p>
      </header>

      <section>
        <h2 class="psb:text-lg psb:font-semibold psb:mb-1">Scale</h2>
        <p class="psb:text-sm psb:text-slate-500 psb:mb-4">
          Page-level headings step down from the hero billboard title to the
          smallest legible caption. Each row renders the actual class string
          shown to its right.
        </p>

        <div class="psb:space-y-3">
          <.type_row tw="text-5xl font-bold tracking-tight" sample="Display large" />
          <.type_row tw="text-4xl font-bold tracking-tight" sample="Display medium" />
          <.type_row tw="text-3xl font-semibold tracking-tight" sample="Heading 1 — page title" />
          <.type_row tw="text-2xl font-semibold" sample="Heading 2 — section title" />
          <.type_row tw="text-xl font-semibold" sample="Heading 3 — sub-section" />
          <.type_row tw="text-lg font-medium" sample="Heading 4 — card title" />
          <.type_row tw="text-base font-normal" sample="Body — default paragraph copy" />
          <.type_row tw="text-sm font-normal" sample="Body small — dense lists, secondary copy" />
          <.type_row
            tw="text-xs font-medium uppercase tracking-wider"
            sample="Eyebrow / overline label"
          />
          <.type_row tw="text-xs font-normal" sample="Caption — timestamps, hints, footnotes" />
        </div>
      </section>

      <section>
        <h2 class="psb:text-lg psb:font-semibold psb:mb-1">Weights</h2>
        <p class="psb:text-sm psb:text-slate-500 psb:mb-4">
          Five weights cover everything in the system. Lighter weights are
          reserved for large display copy where extra mass would feel heavy.
        </p>

        <div class="psb:space-y-3">
          <.type_row tw="text-2xl font-light" sample="Light" />
          <.type_row tw="text-2xl font-normal" sample="Normal" />
          <.type_row tw="text-2xl font-medium" sample="Medium" />
          <.type_row tw="text-2xl font-semibold" sample="Semibold" />
          <.type_row tw="text-2xl font-bold" sample="Bold" />
        </div>
      </section>

      <section>
        <h2 class="psb:text-lg psb:font-semibold psb:mb-1">Numerics</h2>
        <p class="psb:text-sm psb:text-slate-500 psb:mb-4">
          Use <code class="psb:text-xs">tabular-nums</code>
          (or the CSS <code class="psb:text-xs">font-variant-numeric: tabular-nums</code>) on any
          digits that update in place — progress percentages, durations, counts, log timestamps.
          Without it, proportional digits cause visible width jitter as values change.
        </p>

        <div class="psb:grid psb:grid-cols-1 md:psb:grid-cols-2 psb:gap-4">
          <div class="psb:rounded-md psb:border psb:border-slate-300/40 psb:p-4 psb:bg-white">
            <div class="psb:text-xs psb:uppercase psb:tracking-wider psb:text-slate-500 psb:mb-3">
              Without tabular-nums
            </div>
            <div class="psb:font-sans psb:text-lg psb:text-slate-900 psb:space-y-1">
              <div>12.3%</div>
              <div>123.4%</div>
              <div>1234.5%</div>
              <div>00:12:34</div>
              <div>11:11:11</div>
            </div>
            <p class="psb:text-xs psb:text-slate-500 psb:mt-3">
              Digit columns drift — `1` is narrower than `0`, so each row sits at a different width.
            </p>
          </div>

          <div class="psb:rounded-md psb:border psb:border-slate-300/40 psb:p-4 psb:bg-white">
            <div class="psb:text-xs psb:uppercase psb:tracking-wider psb:text-slate-500 psb:mb-3">
              With <code class="psb:text-xs">tabular-nums</code>
            </div>
            <div class="psb:font-sans psb:text-lg psb:text-slate-900 psb:tabular-nums psb:space-y-1">
              <div>12.3%</div>
              <div>123.4%</div>
              <div>1234.5%</div>
              <div>00:12:34</div>
              <div>11:11:11</div>
            </div>
            <p class="psb:text-xs psb:text-slate-500 psb:mt-3">
              Every digit occupies the same column width — values can update without reflow.
            </p>
          </div>
        </div>

        <div class="psb:mt-4 psb:text-xs psb:text-slate-500">
          In CSS the same effect comes from
          <code class="psb:text-xs">font-variant-numeric: tabular-nums</code>
          — see <code class="psb:text-xs">.console-timestamp</code>
          and <code class="psb:text-xs">.console-buffer-size-label</code>
          in <code class="psb:text-xs">assets/css/app.css</code>.
        </div>
      </section>
    </div>
    """
  end

  defp type_row(assigns) do
    ~H"""
    <div class="psb:flex psb:items-baseline psb:gap-6 psb:border-b psb:border-slate-300/40 psb:pb-3">
      <div class={"psb:flex-1 psb:text-slate-900 #{prefix_psb(@tw)}"}>{@sample}</div>
      <code class="psb:text-xs psb:text-slate-500 psb:font-mono psb:whitespace-nowrap">
        {@tw}
      </code>
    </div>
    """
  end

  # Rewrite a space-separated Tailwind class list (no prefix) into the
  # `psb:`-prefixed form storybook chrome requires. Letting the same
  # source string drive both rendering and the visible label keeps them
  # from drifting apart — what you see is what would land in HEEx.
  defp prefix_psb(classes) do
    classes |> String.split(" ", trim: true) |> Enum.map_join(" ", &"psb:#{&1}")
  end
end
