defmodule MediaCentaurWeb.Storybook.CoreComponents.Disclosure do
  @moduledoc """
  Story for `<.disclosure>` — the one disclosure: a head that shows or hides
  a body, owned by the LiveView. The head carries `aria-expanded` (the caret
  turns when open) and the body is rendered only while open. Variants are
  styling only; the contract is the same in each.
  """

  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.Disclosure.disclosure/1
  def render_source, do: :function

  def variations do
    [
      %VariationGroup{
        id: :quiet,
        description:
          "`:quiet` (default) — rare content behind a caret and a small muted label, " <>
            "the body indented under a hairline. Settings' secret key, service details.",
        variations: [
          %Variation{
            id: :quiet_closed,
            attributes: %{id: "story-quiet-closed", open: false, label: "Show service details"},
            slots: [~s|<p class="text-xs">never rendered while closed</p>|]
          },
          %Variation{
            id: :quiet_open,
            attributes: %{id: "story-quiet-open", open: true, label: "Show service details"},
            slots: [~s|<p class="text-xs text-base-content/70">The body, under a hairline.</p>|]
          }
        ]
      },
      %VariationGroup{
        id: :panel,
        description:
          "`:panel` — an inset box whose head is its first row, the body below a rule. " <>
            "Status' technical logs, the plan board's How we searched.",
        variations: [
          %Variation{
            id: :panel_closed,
            attributes: %{
              id: "story-panel-closed",
              open: false,
              variant: :panel,
              label: "Technical logs"
            },
            slots: [~s|<p class="text-xs">never rendered while closed</p>|]
          },
          %Variation{
            id: :panel_open,
            attributes: %{id: "story-panel-open", open: true, variant: :panel, label: "Technical logs"},
            slots: [
              ~s|<p class="font-mono text-xs text-base-content/70">12:00:01 pipeline — file matched</p>|
            ]
          }
        ]
      },
      %Variation{
        id: :bare_with_head,
        description:
          "`:bare` with a `:head` slot — the host draws the head's content and styles " <>
            "it through `head_class`. A release history row: version left, date right.",
        attributes: %{
          id: "story-bare",
          open: true,
          variant: :bare,
          head_class: "flex w-full items-center gap-1.5 text-xs py-0.5",
          body_class: "mt-1.5 mb-2 pl-5 text-xs"
        },
        slots: [
          """
          <:head>
            <span class="font-mono text-base-content/70">v1.43.0</span>
            <span class="ml-auto text-base-content/55">Sep 28</span>
          </:head>
          <p class="text-base-content/70">Release notes for this version.</p>
          """
        ]
      },
      %VariationGroup{
        id: :nav,
        description:
          "How the input system reaches the head: a `data-nav-item` (default), a " <>
            "`data-nav-sub-item` inside a row's own controls, or nothing (an unmanaged " <>
            "overlay such as the report modal, where the head is a plain button).",
        variations:
          for nav <- [:item, :sub_item, :none] do
            %Variation{
              id: nav,
              attributes: %{id: "story-nav-#{nav}", open: false, nav: nav, label: "nav: #{nav}"},
              slots: [~s|<p class="text-xs">body</p>|]
            }
          end
      },
      %Variation{
        id: :keep_body_closed,
        description:
          "`keep_body` — a closed body is rendered `hidden` rather than not at all, so " <>
            "form fields inside it still submit. The media directory dialog's Advanced.",
        attributes: %{
          id: "story-keep-body",
          open: false,
          keep_body: true,
          label: "Advanced — images directory"
        },
        slots: [~s|<input type="text" name="entry[images_dir]" class="library-filter w-full" />|]
      }
    ]
  end
end
