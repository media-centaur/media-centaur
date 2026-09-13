defmodule MediaCentaurWeb.Storybook.Settings.SettingsList do
  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.Settings.settings_list/1
  def render_source, do: :function

  def variations do
    [
      %Variation{
        id: :items,
        description: "One row per entry with Remove, an inline input with Add.",
        attributes: %{
          items: ["Extras", "Featurettes"],
          remove_event: "config_list_remove",
          add_event: "config_list_add",
          event_value: %{"key" => "extras_dirs"},
          placeholder: "Folder name",
          add_label: "Add"
        }
      },
      %Variation{
        id: :empty_with_error,
        description: "Nothing listed yet; the last add was refused and says why.",
        attributes: %{
          items: [],
          remove_event: "exclude_dir:remove",
          add_event: "exclude_dir:add",
          placeholder: "/path",
          add_label: "Add",
          mono: true,
          error: "That path is inside a media directory."
        }
      }
    ]
  end
end
