defmodule MediaCentaurWeb.Storybook.CoreComponents.SplitButton do
  @moduledoc """
  The split button (spec 2026-09-12 §14): a main segment that performs
  the default action and a chevron that opens the glass menu with the
  other choices. The open list is a nav zone of its own, so the story
  pins the wiring — `data-nav-zone`, `data-nav-dismiss-event`,
  `aria-expanded` — as much as the look. Every `variant` and `size` of
  the underlying button is exercised (MC0009).
  """

  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.GlassMenu.split_button/1
  def render_source, do: :function

  # The open list drops below the trigger via `position: absolute`.
  def template do
    """
    <div class="pb-24">
      <.psb-variation/>
    </div>
    """
  end

  def variations do
    [
      %Variation{
        id: :closed,
        description: "Closed: the main segment carries the verb, the chevron waits.",
        attributes: base(open: false),
        slots: download_slots()
      },
      %Variation{
        id: :open,
        description: "Open: the one other choice, under the button.",
        attributes: base(open: true),
        slots: download_slots()
      },
      %Variation{
        id: :open_two_items,
        description: "A longer menu.",
        attributes: base(open: true),
        slots: [
          ~s|Download|,
          ~s|<:item id="split-other" event="title_download" values={%{"mode" => "manually_select_release"}}>Manually select release</:item>|,
          ~s|<:item id="split-follow" event="title_follow">Download and follow</:item>|
        ]
      },
      %Variation{
        id: :pending,
        description: "Disabled while the host plans — the label says why.",
        attributes: base(open: false, disabled: true),
        slots: [
          ~s|Planning…|,
          ~s|<:item id="split-other" event="title_download" values={%{"mode" => "manually_select_release"}}>Manually select release</:item>|
        ]
      },
      %VariationGroup{
        id: :variants,
        description: "Every button variant, closed.",
        variations:
          for variant <-
                ~w(primary secondary action info risky danger dismiss destructive_inline neutral outline) do
            %Variation{
              id: String.to_atom("variant_" <> variant),
              attributes: base(open: false, variant: variant),
              slots: download_slots()
            }
          end
      },
      %VariationGroup{
        id: :sizes,
        description: "Every size, closed.",
        variations:
          for size <- ~w(xs sm md lg) do
            %Variation{
              id: String.to_atom("size_" <> size),
              attributes: base(open: false, size: size),
              slots: download_slots()
            }
          end
      }
    ]
  end

  defp base(overrides) do
    Map.merge(
      %{
        id: "split",
        open: false,
        on_toggle: "title_menu_toggle",
        on_close: "title_menu_close",
        menu_zone: "sample_menu",
        menu_label: "More download options",
        "phx-click": "title_download"
      },
      Map.new(overrides)
    )
  end

  defp download_slots do
    [
      ~s|Download|,
      ~s|<:item id="split-other" event="title_download" values={%{"mode" => "manually_select_release"}}>Manually select release</:item>|
    ]
  end
end
