defmodule MediaCentaurWeb.Storybook.CoreComponents.MenuSelect do
  @moduledoc """
  The menu select (spec 2026-09-12 §15): a quiet trigger showing the
  current value, a chevron, and the glass menu of options with the
  current one marked. The library sort control and the title detail
  modal's scope select are its tenants.
  """

  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.GlassMenu.menu_select/1
  def render_source, do: :function

  def template do
    """
    <div class="pb-32">
      <.psb-variation/>
    </div>
    """
  end

  def variations do
    [
      %Variation{
        id: :closed,
        description: "Closed, showing the current choice.",
        attributes: base(open: false),
        slots: scope_items()
      },
      %Variation{
        id: :open,
        description: "Open: the current choice marked, the other plain.",
        attributes: base(open: true),
        slots: scope_items()
      },
      %Variation{
        id: :sort,
        description: "The library sort control's four options, with a `data-sort` on the wrapper.",
        attributes:
          base(
            id: "sort",
            open: true,
            value_label: "Recently Added",
            label: "Sort",
            "data-sort": "recent"
          ),
        slots: [
          ~s|<:item id="sort-recent" event="sort" values={%{"sort" => "recent"}} active>Recently Added</:item>|,
          ~s|<:item id="sort-watched" event="sort" values={%{"sort" => "watched"}}>Recently Watched</:item>|,
          ~s|<:item id="sort-alpha" event="sort" values={%{"sort" => "alpha"}}>A–Z</:item>|,
          ~s|<:item id="sort-year" event="sort" values={%{"sort" => "year"}}>Year</:item>|
        ]
      }
    ]
  end

  defp base(overrides) do
    Map.merge(
      %{
        id: "scope",
        open: false,
        on_toggle: "title_scope_toggle",
        on_close: "title_menu_close",
        menu_zone: "sample_menu",
        value_label: "Season 1",
        label: "Download scope"
      },
      Map.new(overrides)
    )
  end

  defp scope_items do
    [
      ~s|<:item id="scope-first_season" event="title_scope" values={%{"choice" => "first_season"}} active>Season 1</:item>|,
      ~s|<:item id="scope-everything" event="title_scope" values={%{"choice" => "everything"}}>All seasons</:item>|
    ]
  end
end
