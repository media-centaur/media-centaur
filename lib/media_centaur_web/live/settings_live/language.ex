defmodule MediaCentaurWeb.SettingsLive.Language do
  @moduledoc """
  The Language section of the Settings page (UIDR-041): the ordered
  understood-languages list and, as select rows that save on change, the
  audio/subtitle policy. `SettingsLive` delegates to `render/1` and hosts
  the add/move/remove and `set_language_policy` handlers.
  """

  use MediaCentaurWeb, :html

  import MediaCentaurWeb.Components.Settings

  alias MediaCentaur.Iso639
  alias MediaCentaur.Playback.LanguagePolicy

  attr :language_options, :list,
    required: true,
    doc: "`[{code, display_name}]` tuples for the add-language datalist."

  attr :language_draft, :list,
    required: true,
    doc: "ordered list of ISO 639-1 codes — the understood-languages draft, most-preferred first."

  attr :language_policy, :map,
    required: true,
    doc: "the `LanguagePolicy` settings map (audio priority + subtitle preferences)."

  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <.settings_card
        title="Languages you understand"
        description="Add the languages you can follow without subtitles, most-preferred first. Used to pick audio you understand and which language to show subtitles in."
      >
        <form phx-submit="add_language" class="flex gap-2">
          <.settings_input
            name="lang"
            list="language-options"
            placeholder="Add a language…"
            autocomplete="off"
            class="flex-1"
          />
          <datalist id="language-options">
            <option :for={{_code, name} <- @language_options} value={name}></option>
          </datalist>
          <.button type="submit" variant="neutral" size="sm" data-nav-item tabindex="0">
            Add
          </.button>
        </form>

        <ol :if={@language_draft != []} class="space-y-2">
          <li
            :for={{code, index} <- Enum.with_index(@language_draft)}
            id={"understood-lang-#{code}"}
            class="flex items-center gap-2 glass-inset rounded-lg px-3 py-2"
          >
            <span class="w-5 text-xs tabular-nums text-base-content/55">{index + 1}</span>
            <span class="flex-1 text-sm">{Iso639.display_name(code)}</span>
            <.button
              type="button"
              variant="dismiss"
              size="xs"
              phx-click="move_language_up"
              phx-value-code={code}
              disabled={index == 0}
              data-nav-item
              tabindex="0"
              aria-label={"Move #{Iso639.display_name(code)} up"}
            >
              <.icon name="hero-chevron-up-mini" class="size-4" />
            </.button>
            <.button
              type="button"
              variant="dismiss"
              size="xs"
              phx-click="move_language_down"
              phx-value-code={code}
              disabled={index == length(@language_draft) - 1}
              data-nav-item
              tabindex="0"
              aria-label={"Move #{Iso639.display_name(code)} down"}
            >
              <.icon name="hero-chevron-down-mini" class="size-4" />
            </.button>
            <.button
              type="button"
              variant="destructive_inline"
              size="xs"
              phx-click="remove_language"
              phx-value-code={code}
              data-nav-item
              tabindex="0"
              aria-label={"Remove #{Iso639.display_name(code)}"}
            >
              <.icon name="hero-x-mark-mini" class="size-4" />
            </.button>
          </li>
        </ol>
        <p :if={@language_draft == []} class="text-sm text-base-content/55">
          No languages added yet — subtitles will always be shown until you add one.
        </p>
      </.settings_card>

      <.settings_card
        title="Audio & subtitles"
        description="How tracks are picked automatically when playback starts. Per-show overrides (set by changing tracks during playback) always win over these."
      >
        <div class="space-y-0.5">
          <.settings_select_row
            id="language-audio_priority"
            label="Audio preference"
            name="audio_priority"
            options={[
              {"original_first", "Original language first (subtitles do the work)"},
              {"understood_first", "My languages first (prefer dubs)"},
              {"any", "No preference (whatever the file defaults to)"}
            ]}
            selected={LanguagePolicy.audio_priority_preset(@language_policy)}
            event="set_language_policy"
          />
          <.settings_select_row
            id="language-subtitles_when"
            label="Show subtitles"
            name="subtitles_when"
            options={[
              {"off", "Never"},
              {"when_audio_not_understood", "Only when I don't understand the audio"},
              {"always", "Always"}
            ]}
            selected={@language_policy.subtitles_when}
            event="set_language_policy"
          />
          <.settings_select_row
            id="language-subtitles_language"
            label="Subtitle language"
            name="subtitles_language"
            options={[
              {"understood", "One of my languages"},
              {"audio_language", "Match the audio (language learning)"}
            ]}
            selected={@language_policy.subtitles_language}
            event="set_language_policy"
          />
          <.settings_select_row
            id="language-subtitles_variant"
            label="Subtitle style"
            name="subtitles_variant"
            options={[
              {"standard", "Standard"},
              {"sdh_preferred", "Prefer SDH (deaf / hard-of-hearing)"}
            ]}
            selected={@language_policy.subtitles_variant}
            event="set_language_policy"
          />
          <.settings_select_row
            id="language-forced_subs"
            label="Forced subtitles"
            name="forced_subs"
            options={[
              {"never", "Never"},
              {"fill_gaps", "Fill gaps (foreign-dialog scenes)"},
              {"always", "Always"}
            ]}
            selected={@language_policy.forced_subs}
            event="set_language_policy"
          />
        </div>
      </.settings_card>
    </div>
    """
  end
end
