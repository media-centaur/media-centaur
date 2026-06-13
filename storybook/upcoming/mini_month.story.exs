defmodule MediaCentaurWeb.Storybook.Upcoming.MiniMonth do
  @moduledoc "The quiet sticky mini-month companion — release-day dots, today fill, focused-day ring."

  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.Upcoming.MiniMonth.mini_month/1
  def render_source, do: :function

  def template do
    """
    <div class="max-w-xs p-4 bg-base-100 rounded-xl">
      <.psb-variation/>
    </div>
    """
  end

  def variations do
    [
      %Variation{
        id: :with_marks,
        description: "Release days dotted by status; today filled, focused day ringed",
        attributes: %{
          year: 2026,
          month: 6,
          today: ~D[2026-06-14],
          focused_day: ~D[2026-06-17],
          marks: %{
            ~D[2026-06-14] => %{count: 2, status: :under_pursuit},
            ~D[2026-06-17] => %{count: 1, status: :armed},
            ~D[2026-06-22] => %{count: 1, status: :armed},
            ~D[2026-06-30] => %{count: 1, status: :theatrical_info}
          }
        }
      },
      %Variation{
        id: :empty,
        description: "A quiet month with nothing scheduled",
        attributes: %{year: 2026, month: 6, today: ~D[2026-06-14], focused_day: nil, marks: %{}}
      }
    ]
  end
end
