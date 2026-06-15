defmodule MediaCentaurWeb.SettingsLive.Language do
  @moduledoc """
  The Language section of the Settings page — understood-languages list plus
  the audio/subtitle policy form. `SettingsLive` delegates to `render/1` and
  hosts the add/move/remove and save-policy event handlers.
  """

  use MediaCentaurWeb, :html

  alias MediaCentaur.Playback.{Iso639, LanguagePolicy}

  attr :language_options, :list, required: true
  attr :language_draft, :list, required: true
  attr :language_policy, :map, required: true

  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <form phx-submit="add_language" class="p-5 rounded-lg glass-surface space-y-4">
        <div>
          <h2 class="text-lg font-semibold">Languages you understand</h2>
          <p class="text-sm text-base-content/50 mt-0.5">
            Add the languages you can follow without subtitles, most-preferred first.
            Used to pick audio you understand and which language to show subtitles in.
            Changes here save automatically.
          </p>
        </div>

        <div class="flex gap-2">
          <input
            type="text"
            name="lang"
            list="language-options"
            class="input input-bordered flex-1 text-sm"
            placeholder="Add a language…"
            autocomplete="off"
            data-nav-item
            tabindex="0"
          />
          <datalist id="language-options">
            <option :for={{_code, name} <- @language_options} value={name}></option>
          </datalist>
          <.button type="submit" variant="neutral" size="sm" data-nav-item tabindex="0">
            Add
          </.button>
        </div>

        <ol :if={@language_draft != []} class="space-y-2">
          <li
            :for={{code, index} <- Enum.with_index(@language_draft)}
            id={"understood-lang-#{code}"}
            class="flex items-center gap-2 glass-inset rounded-lg px-3 py-2"
          >
            <span class="w-5 text-xs tabular-nums text-base-content/40">{index + 1}</span>
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
        <p :if={@language_draft == []} class="text-sm text-base-content/40">
          No languages added yet — subtitles will always be shown until you add one.
        </p>
      </form>

      <form phx-submit="save_language_policy" class="p-5 rounded-lg glass-surface space-y-5">
        <div class="flex items-start justify-between gap-4">
          <div class="min-w-0">
            <h2 class="text-lg font-semibold">Audio &amp; subtitles</h2>
            <p class="text-sm text-base-content/50 mt-0.5">
              How tracks are picked automatically when playback starts. Per-show overrides
              (set by changing tracks during playback) always win over these.
            </p>
          </div>
          <.button
            type="submit"
            variant="secondary"
            size="sm"
            class="shrink-0"
            data-nav-item
            tabindex="0"
          >
            Save
          </.button>
        </div>

        <div class="space-y-4">
          <div>
            <label class="text-xs font-medium uppercase tracking-wider text-base-content/50 block mb-1.5">
              Audio preference
            </label>
            <select
              name="audio_priority"
              class="select select-bordered w-full text-sm"
              data-nav-item
              tabindex="0"
            >
              <option
                value="original_first"
                selected={LanguagePolicy.audio_priority_preset(@language_policy) == "original_first"}
              >
                Original language first (subtitles do the work)
              </option>
              <option
                value="understood_first"
                selected={
                  LanguagePolicy.audio_priority_preset(@language_policy) == "understood_first"
                }
              >
                My languages first (prefer dubs)
              </option>
              <option
                value="any"
                selected={LanguagePolicy.audio_priority_preset(@language_policy) == "any"}
              >
                No preference (whatever the file defaults to)
              </option>
            </select>
          </div>

          <div class="grid grid-cols-2 gap-3">
            <div>
              <label class="text-xs font-medium uppercase tracking-wider text-base-content/50 block mb-1.5">
                Show subtitles
              </label>
              <select
                name="subtitles_when"
                class="select select-bordered w-full text-sm"
                data-nav-item
                tabindex="0"
              >
                <option value="off" selected={@language_policy.subtitles_when == "off"}>
                  Never
                </option>
                <option
                  value="when_audio_not_understood"
                  selected={@language_policy.subtitles_when == "when_audio_not_understood"}
                >
                  Only when I don't understand the audio
                </option>
                <option value="always" selected={@language_policy.subtitles_when == "always"}>
                  Always
                </option>
              </select>
            </div>

            <div>
              <label class="text-xs font-medium uppercase tracking-wider text-base-content/50 block mb-1.5">
                Subtitle language
              </label>
              <select
                name="subtitles_language"
                class="select select-bordered w-full text-sm"
                data-nav-item
                tabindex="0"
              >
                <option
                  value="understood"
                  selected={@language_policy.subtitles_language == "understood"}
                >
                  One of my languages
                </option>
                <option
                  value="audio_language"
                  selected={@language_policy.subtitles_language == "audio_language"}
                >
                  Match the audio (language learning)
                </option>
              </select>
            </div>

            <div>
              <label class="text-xs font-medium uppercase tracking-wider text-base-content/50 block mb-1.5">
                Subtitle style
              </label>
              <select
                name="subtitles_variant"
                class="select select-bordered w-full text-sm"
                data-nav-item
                tabindex="0"
              >
                <option value="standard" selected={@language_policy.subtitles_variant == "standard"}>
                  Standard
                </option>
                <option
                  value="sdh_preferred"
                  selected={@language_policy.subtitles_variant == "sdh_preferred"}
                >
                  Prefer SDH (deaf / hard-of-hearing)
                </option>
              </select>
            </div>

            <div>
              <label class="text-xs font-medium uppercase tracking-wider text-base-content/50 block mb-1.5">
                Forced subtitles
              </label>
              <select
                name="forced_subs"
                class="select select-bordered w-full text-sm"
                data-nav-item
                tabindex="0"
              >
                <option value="never" selected={@language_policy.forced_subs == "never"}>
                  Never
                </option>
                <option value="fill_gaps" selected={@language_policy.forced_subs == "fill_gaps"}>
                  Fill gaps (foreign-dialog scenes)
                </option>
                <option value="always" selected={@language_policy.forced_subs == "always"}>
                  Always
                </option>
              </select>
            </div>
          </div>
        </div>
      </form>
    </div>
    """
  end
end
