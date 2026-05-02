defmodule MediaCentarrWeb.Storybook.Foundations.Spacing do
  @moduledoc """
  Spacing foundations — scale, glass surface, and hover/focus rules.

  Documents the Tailwind default spacing scale (no project override),
  the `.glass-surface` treatment that defines most cards, and the
  hover-scale + keyboard/gamepad focus-ring conventions.

  Spacing rows are rendered with literal inline `style="width: …rem"`
  rather than dynamic `class={"w-\#{n}"}` strings — Tailwind v4 scans
  source files for verbatim class names and would not emit per-row
  width utilities derived at render time. The rendered bars therefore
  carry the rem value directly so the visualisation cannot drift from
  the named scale.
  """

  use PhoenixStorybook.Story, :page

  def doc, do: "Spacing scale, glass surface, and hover/focus rules."

  def render(assigns) do
    ~H"""
    <div class="psb:p-6 psb:max-w-5xl psb:mx-auto psb:space-y-12">
      <header>
        <h1 class="psb:text-2xl psb:font-semibold psb:mb-2">Spacing &amp; surfaces</h1>
        <p class="psb:text-sm psb:text-slate-500">
          Tailwind defaults, no project override — every step is
          <code class="psb:text-xs">0.25rem</code>
          (4px). Smaller values dominate component-internal spacing
          (<code class="psb:text-xs">p-2</code> through <code class="psb:text-xs">p-6</code>); larger values
          (<code class="psb:text-xs">8</code>+) are reserved for page-level
          hero or landing rhythm. Surface and focus rules complete the picture.
        </p>
      </header>

      <section>
        <h2 class="psb:text-lg psb:font-semibold psb:mb-1">Scale</h2>
        <p class="psb:text-sm psb:text-slate-500 psb:mb-4">
          Each row visualises a step in the scale at its true rem width.
          The <em>use for</em>
          column is the project's most common application —
          most cards land at <code class="psb:text-xs">p-3</code>
          / <code class="psb:text-xs">p-4</code>, sections at <code class="psb:text-xs">space-y-6</code>, and anything past
          <code class="psb:text-xs">p-8</code>
          shows up only at the page or hero level.
        </p>

        <div class="psb:rounded-md psb:border psb:border-slate-300/40 psb:overflow-hidden">
          <.spacing_row
            n="1"
            rem="0.25rem"
            width="0.25rem"
            use_for="Tightest — between icon and label"
          />
          <.spacing_row
            n="2"
            rem="0.5rem"
            width="0.5rem"
            use_for="Compact lists, inline groups (gap-2 is the most common gap in the app)"
          />
          <.spacing_row
            n="3"
            rem="0.75rem"
            width="0.75rem"
            use_for="Default inner padding for small components"
          />
          <.spacing_row
            n="4"
            rem="1rem"
            width="1rem"
            use_for="Default — most card padding, button gaps"
          />
          <.spacing_row
            n="6"
            rem="1.5rem"
            width="1.5rem"
            use_for="Section padding, sidebar gaps, page-shell padding"
          />
          <.spacing_row
            n="8"
            rem="2rem"
            width="2rem"
            use_for="Major separator, header padding (rare — only at top-level layouts)"
          />
          <.spacing_row
            n="12"
            rem="3rem"
            width="3rem"
            use_for="Page margin (reserved for landing-style spacing)"
          />
          <.spacing_row
            n="16"
            rem="4rem"
            width="4rem"
            use_for="Hero spacing (marketing surfaces only)"
          />
          <.spacing_row
            n="24"
            rem="6rem"
            width="6rem"
            use_for="Large hero / landing rhythm (showcase + docs-site)"
          />
        </div>
      </section>

      <section>
        <h2 class="psb:text-lg psb:font-semibold psb:mb-1">Glass surface</h2>
        <p class="psb:text-sm psb:text-slate-500 psb:mb-4">
          The <code class="psb:text-xs">.glass-surface</code>
          class is the workhorse card treatment: a translucent
          <code class="psb:text-xs">--glass-bg</code>
          fill, a 12px backdrop-blur, a hairline border, and a soft drop shadow.
          It only reads correctly over the body's radial gradient — that
          gradient is what gives the frosted layer something to refract.
          The preview below renders the gradient locally so you can see
          the actual class against the actual backdrop.
        </p>

        <div class="media-centarr psb:rounded-md psb:overflow-hidden psb:border psb:border-slate-300/40">
          <div
            class="psb:p-6 psb:space-y-4"
            style={
              "color-scheme: dark; color: var(--color-base-content); " <>
                "background-color: var(--color-base-100); " <>
                "background-image: radial-gradient(ellipse at 20% 15%, var(--glass-gradient-a), transparent 60%), radial-gradient(ellipse at 80% 80%, var(--glass-gradient-b), transparent 60%);"
            }
          >
            <div class="glass-surface psb:rounded-md psb:p-4">
              <div class="psb:text-xs psb:uppercase psb:tracking-wider psb:text-slate-300/70 psb:mb-1">
                .glass-surface
              </div>
              <p class="psb:text-sm psb:text-slate-200/90">
                Translucent card with backdrop-blur over the body gradient.
                Use for: cards, panels, dropdowns — anything that should let
                the gradient show through. Companion classes:
                <code class="psb:text-xs">.glass-nav</code>
                (top bar, stronger blur), <code class="psb:text-xs">.glass-sidebar</code>
                (rail, vertical orientation), <code class="psb:text-xs">.glass-inset</code>
                (nested panel, darker fill).
              </p>
            </div>

            <code class="psb:block psb:text-xs psb:text-slate-400 psb:font-mono">
              &lt;div class="glass-surface rounded-md p-4"&gt;…&lt;/div&gt;
            </code>
          </div>
        </div>
      </section>

      <section>
        <h2 class="psb:text-lg psb:font-semibold psb:mb-1">Hover scale &amp; focus ring</h2>
        <p class="psb:text-sm psb:text-slate-500 psb:mb-4">
          Mouse hover lifts an interactive element with a subtle scale.
          Keyboard or gamepad focus paints a primary-colored outline ring
          driven by <code class="psb:text-xs">[data-input=keyboard]</code>
          or <code class="psb:text-xs">[data-input=gamepad]</code>
          on <code class="psb:text-xs">&lt;html&gt;</code>. In storybook, that
          attribute is not set by default, so tabbing to the live button
          will not show the project's ring — the static preview on the
          right shows what the ring looks like when active.
        </p>

        <div class="media-centarr psb:rounded-md psb:overflow-hidden psb:border psb:border-slate-300/40">
          <div
            class="psb:p-8 psb:flex psb:flex-wrap psb:gap-8 psb:items-center"
            style={
              "color-scheme: dark; color: var(--color-base-content); " <>
                "background-color: var(--color-base-100); " <>
                "background-image: radial-gradient(ellipse at 20% 15%, var(--glass-gradient-a), transparent 60%), radial-gradient(ellipse at 80% 80%, var(--glass-gradient-b), transparent 60%);"
            }
          >
            <div class="psb:flex psb:flex-col psb:gap-2 psb:items-start">
              <span class="psb:text-xs psb:uppercase psb:tracking-wider psb:text-slate-300/70">
                Live — hover me
              </span>
              <button
                type="button"
                class="psb:inline-block psb:px-4 psb:py-2 psb:rounded-md psb:bg-primary psb:text-primary-content psb:text-sm psb:font-medium psb:transition-transform hover:psb:scale-105"
              >
                Hover scale 105%
              </button>
              <code class="psb:text-xs psb:text-slate-400 psb:font-mono">
                hover:scale-105 transition-transform
              </code>
            </div>

            <div class="psb:flex psb:flex-col psb:gap-2 psb:items-start">
              <span class="psb:text-xs psb:uppercase psb:tracking-wider psb:text-slate-300/70">
                Static — focus ring preview
              </span>
              <span
                class="psb:inline-block psb:px-4 psb:py-2 psb:rounded-md psb:bg-slate-800 psb:text-slate-100 psb:text-sm psb:font-medium"
                style="outline: 2px solid var(--color-primary); outline-offset: 2px;"
              >
                Focused nav item
              </span>
              <code class="psb:text-xs psb:text-slate-400 psb:font-mono">
                outline 2px var(--color-primary), offset 2px
              </code>
            </div>
          </div>
        </div>

        <p class="psb:text-xs psb:text-slate-500 psb:mt-3">
          Focus-ring CSS lives under
          <code class="psb:text-xs">[data-input=keyboard] [data-nav-item]:focus</code>
          / <code class="psb:text-xs">[data-input=gamepad] [data-nav-item]:focus</code>
          in <code class="psb:text-xs">assets/css/app.css</code>. Mouse mode
          hides the ring entirely. Toggle the input mode in a real page
          (press a key or gamepad button) to see the live ring; storybook
          chrome stays in mouse mode.
        </p>
      </section>
    </div>
    """
  end

  defp spacing_row(assigns) do
    ~H"""
    <div class="psb:flex psb:items-center psb:gap-4 psb:px-4 psb:py-2 psb:border-b psb:border-slate-300/40 last:psb:border-b-0 psb:bg-white">
      <code class="psb:w-12 psb:text-xs psb:font-mono psb:text-slate-700">p-{@n}</code>
      <code class="psb:w-20 psb:text-xs psb:font-mono psb:text-slate-500">{@rem}</code>
      <div class="psb:flex psb:items-center psb:w-24">
        <span
          class="psb:inline-block psb:h-3 psb:bg-primary psb:rounded-sm"
          style={"width: #{@width};"}
        >
        </span>
      </div>
      <div class="psb:flex-1 psb:text-xs psb:text-slate-600">
        {@use_for}
      </div>
    </div>
    """
  end
end
