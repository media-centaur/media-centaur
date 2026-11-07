defmodule MediaCentaurWeb.Storybook.Settings.SettingsTextRow do
  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.Settings.settings_text_row/1
  def render_source, do: :function

  def variations do
    [
      %Variation{
        id: :path,
        description: "A free-text setting that commits on Enter or blur.",
        attributes: %{
          label: "Data directory",
          description: "Where cached posters and backdrops are stored.",
          name: "data_dir",
          value: "/home/sample/.local/share/media-centaur",
          placeholder: "/path",
          event: "save_data_dir",
          mono: true
        }
      },
      %Variation{
        id: :one_of_several,
        description:
          "A row of one record among several: its id rides in the payload, the name is capped.",
        attributes: %{
          label: "Name",
          description: "What this player is called here and on Status.",
          name: "name",
          value: "Living room TV",
          event: "rename_player",
          event_value: %{"id" => "7"},
          maxlength: 40,
          autocomplete: "off"
        }
      }
    ]
  end
end
