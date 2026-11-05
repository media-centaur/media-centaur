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
        id: :labelled,
        description: "Named, for a card that holds more than one list.",
        attributes: %{
          label: "By folder name",
          items: ["Sample"],
          remove_event: "config_list_remove",
          add_event: "config_list_add",
          event_value: %{"key" => "skip_dirs"},
          placeholder: "Sample",
          add_label: "Add"
        }
      },
      %Variation{
        id: :read_only,
        description:
          "Entries made elsewhere, each a value with its label and a Forget; no add form. Settings → Media Import's remembered matches.",
        attributes: %{
          items: [
            {"rm-1", "Sample Show Signed · TV → Sample Show (1995)"},
            {"rm-2", "Movie A Directors Cut (1999) · Movie → Movie A (1999)"}
          ],
          remove_event: "forget_remembered_match",
          remove_label: "Forget"
        }
      },
      %Variation{
        id: :read_only_empty,
        description: "A read-only list with nothing in it says what will appear.",
        attributes: %{
          items: [],
          remove_event: "forget_remembered_match",
          remove_label: "Forget",
          empty_text: "Nothing yet. Matching files by hand in Review adds them here."
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
          change_event: "exclude_dir:validate",
          value: "cache",
          add_disabled: true,
          error: "Must be an absolute path."
        }
      }
    ]
  end
end
