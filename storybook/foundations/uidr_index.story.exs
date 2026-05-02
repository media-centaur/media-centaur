defmodule MediaCentarrWeb.Storybook.Foundations.UidrIndex do
  @moduledoc """
  UI Design Rule (UIDR) index — the design-system entry point.

  Each rule pairs with the storybook component that implements it (when one
  exists). For pending components the "Story" link drops to the relevant
  foundation page or shows "no story yet" with the phase note from
  `docs/storybook.md`.

  Source of truth for rule text is the matching ADR under
  `decisions/user-interface/`; the `.claude/skills/user-interface/SKILL.md`
  recipe table is the day-to-day reference. This page is the visual jump
  point — keep prose in the skill / ADR, links here.
  """

  use PhoenixStorybook.Story, :page

  def doc, do: "Browseable index of UI design rules with links to component stories."

  # Update this list when a UIDR is added or moved. Format:
  #   {number, category, title, story_path_or_nil, summary, note}
  #
  # Categories: :visual, :interaction, :content, :layout
  # `story_path` is `nil` when no story exists yet. `note` carries the
  # phase reference from the storybook triage table.
  @rules [
    {1, :content, "File path display convention", "/storybook/foundations/typography",
     "Start-truncation with `<bdo>` and a `title` tooltip — filename always visible, directory prefix elided.",
     "no story yet — typography page documents the path treatment until the dedicated component lands"},
    {2, :visual, "Badge style convention", nil,
     "Plain colored text for status, solid `badge` for metric values, `badge-outline` for type classification.",
     "no story yet — see docs/storybook.md Phase 5"},
    {3, :interaction, "Button style convention", "/storybook/core_components/button",
     ~s(Use `<.button variant="…" size="…">`. `btn-soft` for actions, `btn-ghost` for dismiss, never solid semantic.),
     nil},
    {4, :content, "Human-readable durations", nil,
     "Display as `Xh Ym` (no seconds, no leading zeros). Storage stays ISO 8601 — formatting is a display concern.",
     "no story yet — display rule, surfaces in playback / detail components"},
    {5, :layout, "Playback card hierarchy", nil,
     "Three-row playback card: header, identity, progress bar — fixed order, fixed responsibilities per row.",
     "no story yet — see docs/storybook.md Phase 5 (`detail.play_card/1`)"},
    {6, :layout, "Library zone architecture", nil,
     "Library zones share one LiveView and switch via `push_patch` instead of separate routes.",
     "no story — architectural decision, superseded in part by UIDR-010"},
    {7, :layout, "Left wall enters sidebar", "/storybook/foundations/spacing",
     "Collapsible sidebar (200px expanded / 52px collapsed) replaces the previous left-wall navigation.",
     "no dedicated story — sidebar behaviour is page-level; spacing page covers the rail surface"},
    {8, :visual, "Flex rows with mixed-size text use baseline alignment",
     "/storybook/foundations/typography",
     "`align-items: baseline` whenever a flex row mixes text sizes — keeps glyph baselines aligned across siblings.",
     "no dedicated story — typography page demonstrates the baseline-aligned row"},
    {9, :visual, "Modal panels must set explicit text color", nil,
     "`.modal-panel` declares `color: var(--color-base-content)` so daisyUI tokens inherit correctly inside the always-in-DOM modal.",
     "no story yet — see docs/storybook.md Phase 4 (`modal_shell/1`)"},
    {10, :layout, "Page redistribution — Watch / System sidebar groups", nil,
     "Home / Library / Upcoming / History split out of the legacy LibraryLive zones; sidebar groups Watch vs System.",
     "no story — IA decision, surfaces in page smoke tests rather than component stories"}
  ]

  def render(assigns) do
    assigns =
      assigns
      |> assign(:rules, @rules)
      |> assign(:categories, [
        {:visual, "Visual"},
        {:interaction, "Interaction"},
        {:content, "Content"},
        {:layout, "Layout & architecture"}
      ])

    ~H"""
    <div class="psb:p-6 psb:max-w-5xl psb:mx-auto psb:space-y-10">
      <header>
        <h1 class="psb:text-2xl psb:font-semibold psb:mb-2">UI Design Rules (UIDR)</h1>
        <p class="psb:text-sm psb:text-slate-500">
          Numbered design rules that govern the look and feel of the app.
          Each rule links to the storybook component that implements it
          (when one exists). Source of truth for rule text is the matching
          ADR under <code class="psb:text-xs">decisions/user-interface/</code>;
          this page is the visual jump point — start here when designing or
          reviewing a new surface.
        </p>
      </header>

      <section :for={{cat, label} <- @categories}>
        <h2 class="psb:text-lg psb:font-semibold psb:mb-3">{label}</h2>
        <div class="psb:rounded-md psb:border psb:border-slate-300/40 psb:overflow-hidden psb:bg-white">
          <.rule_row :for={rule <- rules_for(@rules, cat)} rule={rule} />
        </div>
      </section>

      <footer class="psb:text-xs psb:text-slate-500 psb:pt-4 psb:border-t psb:border-slate-200">
        <p>
          New rule? Add an ADR under <code class="psb:text-xs">decisions/user-interface/</code>
          following the <code class="psb:text-xs">YYYY-MM-DD-NNN-short-title.md</code>
          convention, then append the rule to the <code class="psb:text-xs">@rules</code>
          list in this story. Story links should target an existing component
          story — drop to a foundation page or leave <code class="psb:text-xs">nil</code>
          (with a note) only while the component story is pending.
        </p>
      </footer>
    </div>
    """
  end

  defp rule_row(assigns) do
    ~H"""
    <div class="psb:flex psb:items-baseline psb:gap-4 psb:px-4 psb:py-3 psb:border-b psb:border-slate-200 last:psb:border-b-0">
      <span class="psb:inline-flex psb:items-center psb:justify-center psb:w-12 psb:h-7 psb:rounded-full psb:bg-slate-900 psb:text-white psb:text-xs psb:font-mono psb:font-semibold psb:flex-shrink-0">
        {format_number(rule_number(@rule))}
      </span>
      <div class="psb:flex-1 psb:min-w-0">
        <div class="psb:text-sm psb:font-semibold psb:text-slate-800">
          {rule_title(@rule)}
        </div>
        <p class="psb:text-xs psb:text-slate-600 psb:mt-0.5">
          {rule_summary(@rule)}
        </p>
        <p :if={rule_note(@rule)} class="psb:text-xs psb:text-slate-400 psb:italic psb:mt-1">
          {rule_note(@rule)}
        </p>
      </div>
      <div class="psb:flex-shrink-0 psb:w-44 psb:text-right">
        <%= if rule_story_path(@rule) do %>
          <a
            href={rule_story_path(@rule)}
            class="psb:inline-flex psb:items-center psb:gap-1 psb:text-xs psb:font-medium psb:text-blue-600 hover:psb:text-blue-700 hover:psb:underline"
          >
            View story <span aria-hidden="true">→</span>
          </a>
        <% else %>
          <span class="psb:text-xs psb:text-slate-400">no story yet</span>
        <% end %>
      </div>
    </div>
    """
  end

  defp rules_for(rules, category) do
    Enum.filter(rules, fn {_n, cat, _t, _path, _s, _note} -> cat == category end)
  end

  defp rule_number({n, _cat, _title, _path, _summary, _note}), do: n
  defp rule_title({_n, _cat, title, _path, _summary, _note}), do: title
  defp rule_story_path({_n, _cat, _title, path, _summary, _note}), do: path
  defp rule_summary({_n, _cat, _title, _path, summary, _note}), do: summary
  defp rule_note({_n, _cat, _title, _path, _summary, note}), do: note

  defp format_number(n) when n < 10, do: "00#{n}"
  defp format_number(n) when n < 100, do: "0#{n}"
  defp format_number(n), do: Integer.to_string(n)
end
