defmodule MediaCentarrWeb.Storybook.CoreComponents.Table do
  @moduledoc """
  Rubric-bar story for `table/1` — empty, default, long-rows,
  `row_id`/`row_item` callbacks, and the `:action` slot.
  """

  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentarrWeb.CoreComponents.table/1
  def imports, do: [{MediaCentarrWeb.CoreComponents, button: 1}]
  def render_source, do: :function
  def layout, do: :one_column

  def template do
    """
    <div class="w-4/5 mb-4" psb-code-hidden>
      <.psb-variation/>
    </div>
    """
  end

  def variations do
    [
      %Variation{
        id: :empty,
        description: "No rows — header still rendered",
        attributes: %{
          id: "users-empty",
          rows: []
        },
        slots: table_slots()
      },
      %Variation{
        id: :default,
        description: "Two rows — basic case",
        attributes: %{
          id: "users-default",
          rows: table_rows()
        },
        slots: table_slots()
      },
      %Variation{
        id: :long_rows,
        description: "Twelve rows — verifies vertical density",
        attributes: %{
          id: "users-long",
          rows: long_rows()
        },
        slots: table_slots()
      },
      %Variation{
        id: :with_function,
        description: "row_id and row_item callbacks transform each row",
        attributes: %{
          id: "users-with-fn",
          rows: table_rows(),
          row_id: {:eval, ~S|&"user-#{&1.id}"|},
          row_item: {:eval, ~S"&%{&1 | last_name: String.upcase(&1.last_name)}"}
        },
        slots: table_slots()
      },
      %Variation{
        id: :with_actions,
        description: "Action slot adds a trailing button column",
        attributes: %{
          id: "users-with-actions",
          rows: table_rows()
        },
        slots: [
          """
          <:action>
            <.button>Show</.button>
          </:action>
          """
          | table_slots()
        ]
      }
    ]
  end

  defp table_rows do
    [
      %{id: 1, first_name: "Ada", last_name: "Lovelace", city: "London"},
      %{id: 2, first_name: "Grace", last_name: "Hopper", city: "New York"}
    ]
  end

  defp long_rows do
    for n <- 1..12 do
      %{
        id: n,
        first_name: "First #{n}",
        last_name: "Last #{n}",
        city: "City #{n}"
      }
    end
  end

  defp table_slots do
    [
      """
      <:col :let={user} label="ID">
        <%= user.id %>
      </:col>
      """,
      """
      <:col :let={user} label="First name">
        <%= user.first_name %>
      </:col>
      """,
      """
      <:col :let={user} label="Last name">
        <%= user.last_name %>
      </:col>
      """,
      """
      <:col :let={user} label="City">
        <%= user.city %>
      </:col>
      """
    ]
  end
end
