defmodule MediaCentarrWeb.Storybook.Welcome do
  @moduledoc """
  Storybook landing page — restates our philosophy of use.

  Keep this page in sync with [`docs/storybook.md`](../../docs/storybook.md);
  the prose here is the abridged version.
  """

  use PhoenixStorybook.Story, :page

  def doc, do: "Media Centarr component catalog — philosophy and conventions."

  def render(assigns) do
    ~H"""
    <div class="psb:prose psb:max-w-none psb:p-6">
      <h1 class="psb:text-2xl psb:font-semibold psb:mb-4">Media Centarr storybook</h1>

      <p class="psb:text-base psb:mb-4">
        A live catalog of the design system. Every component renders here exactly the
        way it does in the real UI, against the same theme and glass surfaces.
      </p>

      <h2 class="psb:text-lg psb:font-semibold psb:mt-6 psb:mb-2">Philosophy</h2>

      <ol class="psb:list-decimal psb:pl-6 psb:space-y-2">
        <li>
          <strong>Components, not pages.</strong>
          Storybook catalogs function components. Full LiveViews are covered by page
          smoke tests and the screenshot tour — they depend on PubSub, contexts, and
          the input system in ways that don't survive isolation.
        </li>
        <li>
          <strong>Stories follow the component contract.</strong>
          Variations are struct literals. If a component can't be storyboarded
          without faking an entire context, fix the contract — don't fake the story.
        </li>
        <li>
          <strong>Every meaningful state.</strong>
          Empty / loading / error / loaded. Every variant × size × shape. The story
          is the runnable companion to the <code class="psb:text-sm">user-interface</code>
          skill recipes.
        </li>
        <li>
          <strong>Same unit of work as the component.</strong>
          A PR that adds or changes a component must update its story — same rule
          we apply to wiki sync. Drift kills the value.
        </li>
        <li>
          <strong>Dev-only.</strong>
          Mounted under <code class="psb:text-sm">if Mix.env() == :dev</code>
          in the router. No production endpoint, same posture as Tidewave.
        </li>
        <li>
          <strong>Visuals only.</strong>
          No assertions, no logic — that's <code class="psb:text-sm">automated-testing</code>'s job. Storybook is the
          parallel design-system surface.
        </li>
        <li>
          <strong>Skip when it doesn't fit.</strong>
          Components requiring <code class="psb:text-sm">data-input</code>
          modes, sticky LiveView state, or PubSub topics get a static example or none
          at all — don't fake what isn't representative.
        </li>
      </ol>

      <h2 class="psb:text-lg psb:font-semibold psb:mt-6 psb:mb-2">Adding a story</h2>

      <ol class="psb:list-decimal psb:pl-6 psb:space-y-2">
        <li>
          Create <code class="psb:text-sm">storybook/&lt;area&gt;/&lt;component&gt;.story.exs</code>.
        </li>
        <li>
          Define a module under <code class="psb:text-sm">MediaCentarrWeb.Storybook.*</code>
          (matters for Boundary).
        </li>
        <li>
          List variations covering every meaningful state. Group with
          <code class="psb:text-sm">VariationGroup</code>
          when a control has many axes (size × variant × shape).
        </li>
        <li>
          If the component needs custom hooks or assigns, prefer fixing the
          component contract over scaffolding fake state.
        </li>
      </ol>

      <p class="psb:text-sm psb:mt-6 psb:text-slate-400">
        See <code class="psb:text-sm">docs/storybook.md</code>
        for the long-form philosophy and the component-by-component triage of what
        belongs here.
      </p>
    </div>
    """
  end
end
