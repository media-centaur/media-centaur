defmodule MediaCentarrWeb.Storybook.Foundations.Colors do
  @moduledoc """
  Color foundations — daisyUI semantic tokens and surface treatments.

  Documents the dark-only palette configured in `assets/css/app.css` plus
  the glass-surface and body-gradient utilities that everything else in
  the system layers on top of.

  All color swatches and surface previews use **literal** Tailwind class
  names. Tailwind v4 scans source files for class names and only emits
  CSS for what it sees verbatim, so interpolated classes like
  `bg-\#{token}` would render unstyled. Helpers below pattern-match on a
  token atom and return the full literal class string per token.
  """

  use PhoenixStorybook.Story, :page

  def doc, do: "daisyUI semantic color tokens and surface treatments."

  def render(assigns) do
    ~H"""
    <div class="psb:p-6 psb:max-w-5xl psb:mx-auto psb:space-y-10">
      <header>
        <h1 class="psb:text-2xl psb:font-semibold psb:mb-2">Colors</h1>
        <p class="psb:text-sm psb:text-slate-500">
          Dark-only palette. Slate-cool greys (hue 264) for surfaces; muted blue/violet
          for interactive; clear-but-not-neon status. Configured in <code class="psb:text-xs">assets/css/app.css</code>.
        </p>
      </header>

      <section>
        <h2 class="psb:text-lg psb:font-semibold psb:mb-3">Semantic tokens</h2>
        <p class="psb:text-sm psb:text-slate-500 psb:mb-4">
          Use these for intent, not appearance. Each token pairs with a
          <code class="psb:text-xs">-content</code>
          variant for legible text on top of the colored surface.
        </p>

        <div class="psb:grid psb:grid-cols-1 sm:psb:grid-cols-2 psb:gap-3">
          <.swatch
            token={:primary}
            use_for="Primary actions, focus rings, sidebar-active state, brand accents."
          />
          <.swatch
            token={:secondary}
            use_for="Secondary actions and softer accents that should still feel interactive."
          />
          <.swatch
            token={:accent}
            use_for="Tertiary highlights — chips, badges, subtle dividers that need a third hue."
          />
          <.swatch
            token={:neutral}
            use_for="Subtle containers, library tab pill background, non-status surfaces."
          />
          <.swatch
            token={:info}
            use_for="Informational notes — neutral status messaging, no action implied."
          />
          <.swatch token={:success} use_for="Confirmations, completed-watch state, smart-play flash." />
          <.swatch
            token={:warning}
            use_for="Reversible warnings — destructive intent that has not yet committed."
          />
          <.swatch token={:error} use_for="Errors, irreversible failures, destructive confirms." />
        </div>
      </section>

      <section>
        <h2 class="psb:text-lg psb:font-semibold psb:mb-3">Base surfaces</h2>
        <p class="psb:text-sm psb:text-slate-500 psb:mb-4">
          The three layers that make up every page background. Cards step <em>down</em>
          into base-200/300 for inset surfaces, and modal panels
          use base-100 as their solid backdrop.
        </p>

        <div class="psb:grid psb:grid-cols-1 sm:psb:grid-cols-3 psb:gap-3">
          <.surface_swatch
            token={:"base-100"}
            use_for="Default page background, modal panel surface."
          />
          <.surface_swatch
            token={:"base-200"}
            use_for="Inset panels, count-badge backgrounds inside library tabs."
          />
          <.surface_swatch
            token={:"base-300"}
            use_for="Deepest tier — borders, dividers, highlighted-tab badges."
          />
        </div>
      </section>

      <section>
        <h2 class="psb:text-lg psb:font-semibold psb:mb-3">Surface treatments</h2>
        <p class="psb:text-sm psb:text-slate-500 psb:mb-4">
          Custom classes layered on top of the palette. The body-gradient
          backdrop is what gives glass surfaces something to show through.
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
            <div>
              <div class="psb:text-xs psb:uppercase psb:tracking-wider psb:text-slate-300/70 psb:mb-1">
                Body gradient
              </div>
              <p class="psb:text-sm psb:text-slate-200/90 psb:mb-2">
                <code class="psb:text-xs">body.media-centarr</code>
                — radial blobs of <code class="psb:text-xs">--glass-gradient-a</code>
                (blue) and <code class="psb:text-xs">--glass-gradient-b</code>
                (violet) over <code class="psb:text-xs">base-100</code>.
                Use for: backdrop the entire app paints on. The gradient is what makes
                <code class="psb:text-xs">.glass-surface</code>
                worth using — frosted glass needs depth behind it.
              </p>
            </div>

            <div class="glass-surface psb:rounded-md psb:p-4">
              <div class="psb:text-xs psb:uppercase psb:tracking-wider psb:text-slate-300/70 psb:mb-1">
                .glass-surface
              </div>
              <p class="psb:text-sm psb:text-slate-200/90">
                Translucent frosted card — backdrop-blur 12px over
                <code class="psb:text-xs">--glass-bg</code>
                with a hairline border. Use for: cards and panels that should let the
                gradient show through. Companion classes: <code class="psb:text-xs">.glass-nav</code>
                (top bar), <code class="psb:text-xs">.glass-sidebar</code>
                (rail), <code class="psb:text-xs">.glass-inset</code>
                (inner panels).
              </p>
            </div>

            <div class="psb:rounded-md psb:p-4 psb:border psb:border-slate-500/30 psb:bg-slate-900/40">
              <div class="psb:text-xs psb:uppercase psb:tracking-wider psb:text-slate-300/70 psb:mb-2">
                Focus ring
              </div>
              <p class="psb:text-sm psb:text-slate-200/90 psb:mb-3">
                Outline-only, primary-colored, only visible in keyboard/gamepad mode.
                Mouse mode hides the ring entirely. Driven by
                <code class="psb:text-xs">[data-input]</code>
                on <code class="psb:text-xs">&lt;html&gt;</code>; preview shown statically below.
              </p>
              <span
                class="psb:inline-block psb:px-3 psb:py-2 psb:rounded-md psb:bg-slate-800 psb:text-slate-100 psb:text-sm"
                style="outline: 2px solid var(--color-primary); outline-offset: 2px;"
              >
                Focused nav item
              </span>
            </div>
          </div>
        </div>
      </section>
    </div>
    """
  end

  defp swatch(assigns) do
    ~H"""
    <div class="psb:flex psb:flex-col psb:rounded-md psb:overflow-hidden psb:border psb:border-slate-300/40">
      <div class={[
        "psb:h-16 psb:flex psb:items-center psb:px-3 psb:text-sm psb:font-medium",
        swatch_classes(@token)
      ]}>
        {token_label(@token)}
      </div>
      <div class="psb:p-3 psb:bg-white">
        <div class="psb:text-xs psb:font-mono psb:text-slate-700 psb:mb-1">
          {token_class_hint(@token)}
        </div>
        <div class="psb:text-xs psb:text-slate-600">
          {@use_for}
        </div>
      </div>
    </div>
    """
  end

  defp surface_swatch(assigns) do
    ~H"""
    <div class="psb:flex psb:flex-col psb:rounded-md psb:overflow-hidden psb:border psb:border-slate-300/40">
      <div class={[
        "psb:h-16 psb:flex psb:items-center psb:px-3 psb:text-sm psb:font-medium psb:text-slate-100",
        surface_classes(@token)
      ]}>
        {token_label(@token)}
      </div>
      <div class="psb:p-3 psb:bg-white">
        <div class="psb:text-xs psb:font-mono psb:text-slate-700 psb:mb-1">
          {token_class_hint(@token)}
        </div>
        <div class="psb:text-xs psb:text-slate-600">
          {@use_for}
        </div>
      </div>
    </div>
    """
  end

  # Literal Tailwind classes per token. Tailwind v4 scans source for verbatim
  # class names — interpolated `bg-\#{token}` strings are invisible to the
  # scanner. One clause per token keeps every class observable.
  defp swatch_classes(:primary), do: "bg-primary text-primary-content"
  defp swatch_classes(:secondary), do: "bg-secondary text-secondary-content"
  defp swatch_classes(:accent), do: "bg-accent text-accent-content"
  defp swatch_classes(:neutral), do: "bg-neutral text-neutral-content"
  defp swatch_classes(:info), do: "bg-info text-info-content"
  defp swatch_classes(:success), do: "bg-success text-success-content"
  defp swatch_classes(:warning), do: "bg-warning text-warning-content"
  defp swatch_classes(:error), do: "bg-error text-error-content"

  defp surface_classes(:"base-100"), do: "bg-base-100 border-b border-base-300"
  defp surface_classes(:"base-200"), do: "bg-base-200 border-b border-base-300"
  defp surface_classes(:"base-300"), do: "bg-base-300"

  defp token_label(token), do: Atom.to_string(token)

  defp token_class_hint(:primary), do: "bg-primary / text-primary-content"
  defp token_class_hint(:secondary), do: "bg-secondary / text-secondary-content"
  defp token_class_hint(:accent), do: "bg-accent / text-accent-content"
  defp token_class_hint(:neutral), do: "bg-neutral / text-neutral-content"
  defp token_class_hint(:info), do: "bg-info / text-info-content"
  defp token_class_hint(:success), do: "bg-success / text-success-content"
  defp token_class_hint(:warning), do: "bg-warning / text-warning-content"
  defp token_class_hint(:error), do: "bg-error / text-error-content"
  defp token_class_hint(:"base-100"), do: "bg-base-100"
  defp token_class_hint(:"base-200"), do: "bg-base-200"
  defp token_class_hint(:"base-300"), do: "bg-base-300"
end
