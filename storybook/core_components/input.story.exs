defmodule MediaCentarrWeb.Storybook.CoreComponents.Input do
  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentarrWeb.CoreComponents.input/1
  def render_source, do: :function
  def layout, do: :one_column

  # Mirrors the live `attr :type, values: [...]` declaration in
  # MediaCentarrWeb.CoreComponents.input/1. Keep in sync; every value here
  # must have a visual representation (none of the supported types are visually
  # invisible like a hypothetical `hidden`).
  @types ~w(text email password search tel url number color date datetime-local
            month time week file textarea select checkbox)

  def template do
    """
    <.form for={%{}} class="w-full space-y-6" psb-code-hidden>
      <.psb-variation-group />
    </.form>
    """
  end

  def variations do
    [
      %VariationGroup{
        id: :types,
        description: "Every supported input type, default state",
        variations:
          for type <- @types do
            %Variation{
              id: String.to_atom(String.replace(type, "-", "_")),
              attributes: attrs_for(type)
            }
          end
      },
      %VariationGroup{
        id: :with_error,
        description: "Error state — message appears beneath the field",
        variations: [
          %Variation{
            id: :text_error,
            attributes:
              Map.merge(attrs_for("text"), %{
                label: "Text with error",
                value: "invalid value",
                errors: ["This field is invalid"]
              })
          },
          %Variation{
            id: :email_error,
            attributes:
              Map.merge(attrs_for("email"), %{
                label: "Email with error",
                value: "not-an-email",
                errors: ["Must be a valid email address"]
              })
          },
          %Variation{
            id: :select_error,
            attributes:
              Map.merge(attrs_for("select"), %{
                label: "Select with error",
                errors: ["Please choose an option"]
              })
          }
        ]
      },
      %Variation{
        id: :disabled,
        attributes:
          Map.merge(attrs_for("text"), %{
            label: "Disabled input",
            value: "Read-only value",
            disabled: true
          })
      },
      %Variation{
        id: :with_help_text,
        attributes:
          Map.merge(attrs_for("text"), %{
            label: "Field with placeholder hint",
            value: "",
            placeholder: "e.g. enter a short description"
          })
      },
      %Variation{
        id: :checkbox_checked,
        attributes: Map.merge(attrs_for("checkbox"), %{label: "Checked option", value: true})
      },
      %Variation{
        id: :select_with_options,
        attributes:
          Map.merge(attrs_for("select"), %{
            label: "Select with prompt",
            value: nil,
            prompt: "Choose one",
            options: [{"Option A", "a"}, {"Option B", "b"}, {"Option C", "c"}]
          })
      }
    ]
  end

  # Builds the base attribute map for a given input type. Provides sensible
  # defaults so each Variation can override only what differs.
  defp attrs_for("checkbox") do
    %{
      id: "input_checkbox",
      name: "checkbox_field",
      type: "checkbox",
      label: "Checkbox option",
      value: false,
      errors: []
    }
  end

  defp attrs_for("select") do
    %{
      id: "input_select",
      name: "select_field",
      type: "select",
      label: "Select list",
      value: "b",
      options: [{"Option A", "a"}, {"Option B", "b"}],
      errors: []
    }
  end

  defp attrs_for("textarea") do
    %{
      id: "input_textarea",
      name: "textarea_field",
      type: "textarea",
      label: "Textarea",
      value: "Multi-line\nsample text",
      errors: []
    }
  end

  defp attrs_for(type) do
    %{
      id: "input_#{String.replace(type, "-", "_")}",
      name: "#{String.replace(type, "-", "_")}_field",
      type: type,
      label: String.capitalize(type),
      value: default_value_for(type),
      errors: []
    }
  end

  # Per-type sensible default value for visual rendering.
  defp default_value_for("number"), do: 42
  defp default_value_for("color"), do: "#3366cc"
  defp default_value_for("date"), do: "2026-05-02"
  defp default_value_for("datetime-local"), do: "2026-05-02T14:30"
  defp default_value_for("month"), do: "2026-05"
  defp default_value_for("time"), do: "14:30"
  defp default_value_for("week"), do: "2026-W18"
  defp default_value_for("email"), do: "user@example.com"
  defp default_value_for("url"), do: "https://example.com"
  defp default_value_for("tel"), do: "+1-555-0100"
  defp default_value_for("password"), do: "secret-value"
  defp default_value_for("search"), do: "query"
  defp default_value_for("file"), do: nil
  defp default_value_for(_), do: "Sample value"
end
