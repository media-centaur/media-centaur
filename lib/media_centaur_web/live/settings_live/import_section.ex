defmodule MediaCentaurWeb.SettingsLive.ImportSection do
  @moduledoc """
  The Media Import section of the Settings page (UIDR-041): the extras
  folder names as a list setting, the remembered matches (answers given in
  Review, kept for the name the files were read as; `Review.RememberedMatch`)
  with Forget, the match auto-approve threshold as a stepper, and the
  artwork resolution as a choice. Ignore rules used to
  sit here as a second list; they moved to Library → Ignore rules, where
  the path-matched half already lived. Extras names stay because they
  are classification — which title a file belongs to — not admission.
  (Named
  for the user-facing task; the machinery behind it is the Broadway
  pipeline.) `SettingsLive` delegates to `render/1` and hosts the
  `config_list_add` / `config_list_remove` / `set_*` handlers.
  `threshold_ladder/0` is the stepper's rungs, shared with its handler.
  """

  use MediaCentaurWeb, :html

  import MediaCentaurWeb.Components.Settings

  alias MediaCentaur.Settings.Config
  alias MediaCentaur.Settings.Ladder

  attr :config, :map,
    required: true,
    doc: "settings config map (reads :extras_dirs, :auto_approve_threshold)."

  attr :remembered_matches, :list,
    default: [],
    doc: "`Review.RememberedMatch` rows, from `Review.list_remembered_matches/0`."

  def render(assigns) do
    assigns = assign(assigns, :threshold, assigns.config[:auto_approve_threshold] || threshold_default())

    ~H"""
    <div class="space-y-4">
      <.settings_card
        title="Extras folder names"
        description="Folder names found within your media whose files import as bonus content."
      >
        <.settings_list
          id="extras-dirs"
          items={@config[:extras_dirs] || []}
          remove_event="config_list_remove"
          add_event="config_list_add"
          event_value={%{"key" => "extras_dirs"}}
          placeholder="Featurettes"
        />
      </.settings_card>

      <.settings_card
        title="Remembered matches"
        description="When you match files in Review by hand, the title you chose is remembered for the name the files were read as. New files read the same way match without asking."
      >
        <.settings_list
          id="remembered-matches"
          items={Enum.map(@remembered_matches, &{&1.id, remembered_match_label(&1)})}
          remove_event="forget_remembered_match"
          remove_label="Forget"
          empty_text="Nothing yet. Matching files by hand in Review adds them here."
        />
      </.settings_card>

      <.settings_card title="Matching">
        <div class="space-y-0.5">
          <.settings_stepper
            id="auto-approve-threshold"
            label="Auto-approve threshold"
            description="A TMDB match scoring at least this confidence is approved on its own; the rest wait in Review."
            value_label={format_threshold(@threshold)}
            down_value={Ladder.down(threshold_ladder(), @threshold)}
            up_value={Ladder.up(threshold_ladder(), @threshold)}
            reset_value={threshold_default()}
            at_min={@threshold <= 0.5}
            at_max={@threshold >= 1.0}
            at_default={@threshold == threshold_default()}
            event="set_auto_approve_threshold"
          />
          <.settings_choice
            id="import-image_resolution"
            label="Artwork resolution"
            description="Backdrops are downloaded at this size from now on; existing artwork keeps its size until refreshed. Posters and thumbnails always use a display-appropriate size."
            options={[{"4k", "4K"}, {"1080p", "1080p"}]}
            selected={Config.image_resolution()}
            event="set_image_resolution"
          />
        </div>
      </.settings_card>
    </div>
    """
  end

  @doc """
  One remembered match as the card lists it: the name the files were read
  as, with its year and type, and the title it means —
  `Sample Show Signed · TV → Sample Show (1995)`.
  """
  @spec remembered_match_label(map()) :: String.t()
  def remembered_match_label(remembered) do
    name =
      if remembered.parsed_year,
        do: "#{remembered.parsed_title} (#{remembered.parsed_year})",
        else: remembered.parsed_title

    type = if remembered.media_type == "tv", do: "TV", else: String.capitalize(remembered.media_type)
    title = remembered.match_title || "TMDB #{remembered.tmdb_id}"
    title = if remembered.match_year, do: "#{title} (#{remembered.match_year})", else: title

    "#{name} · #{type} → #{title}"
  end

  @doc "The auto-approve stepper's rungs: 0.50 to 1.00 in steps of 0.05."
  @spec threshold_ladder() :: [float()]
  def threshold_ladder, do: for(n <- 50..100//5, do: n / 100)

  @doc "The auto-approve threshold the app ships with."
  @spec threshold_default() :: float()
  def threshold_default, do: Application.get_env(:media_centaur, :auto_approve_threshold) || 0.85

  defp format_threshold(value), do: :erlang.float_to_binary(value / 1, decimals: 2)
end
