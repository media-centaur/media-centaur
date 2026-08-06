defmodule MediaCentaur.Playback.LanguagePolicy do
  @moduledoc """
  The user's per-install policy for picking audio and subtitle tracks
  at the start of playback. One row per install, stored in the
  `Settings.Entry` table under the key `playback.tracks`. Defaults live
  here so a fresh install behaves sensibly without any user setup.

  ## Fields

    * `understood_languages` — ordered list of ISO 639-2 language codes
      the user can comprehend without subtitles. Used both for audio
      ("understood" = first available track in this list, in order) and
      subs (when subs are needed, pick the first available in this
      order). Empty list means "the user understands no languages
      without subs" — effectively forces subs always.

    * `audio_priority` — ordered list of preference categories. Each
      element is one of `"original"` (a track in the entity's original
      language), `"understood"` (any track in `understood_languages`),
      `"any"` (any audio track). The resolver walks the list and picks
      the first that matches a track in the file.

    * `subtitles_when` — when to enable main subtitles.
      `"off"` | `"when_audio_not_understood"` | `"always"`.

    * `subtitles_language` — which language to pick subs in.
      `"understood"` (first available understood-language track) |
      `"audio_language"` (match the chosen audio's language — for
      language learners). Consulted only when `subtitles_when ≠ off`.

    * `subtitles_variant` — variant preference within the chosen
      language. `"standard"` | `"sdh_preferred"` (prefer SDH-flagged
      tracks for hard-of-hearing users, falls back to standard if
      none).

    * `forced_subs` — orthogonal forced-subtitle behaviour for
      foreign-dialog scenes ("Star Wars Greedo speaks Huttese" etc.).
      `"never"` | `"always"` | `"fill_gaps"` (show forced subs only
      when the audio's language IS understood — fills the gaps left by
      `subtitles_when` choosing not to show main subs).
  """

  alias MediaCentaur.Playback.Iso639
  alias MediaCentaur.Settings

  @settings_key "playback.tracks"

  @builtin_defaults %{
    understood_languages: ["eng"],
    audio_priority: ["original", "understood", "any"],
    subtitles_when: "when_audio_not_understood",
    subtitles_language: "understood",
    subtitles_variant: "standard",
    forced_subs: "fill_gaps"
  }

  defstruct Map.to_list(@builtin_defaults)

  @type audio_priority_token :: String.t()
  @type t :: %__MODULE__{
          understood_languages: [String.t()],
          audio_priority: [audio_priority_token()],
          subtitles_when: String.t(),
          subtitles_language: String.t(),
          subtitles_variant: String.t(),
          forced_subs: String.t()
        }

  @doc """
  The Settings key under which the policy is stored. Exposed so the
  Settings LiveView and tests can reference it without hardcoding the
  string.
  """
  @spec settings_key() :: String.t()
  def settings_key, do: @settings_key

  @doc "Returns the built-in default policy as a `%LanguagePolicy{}`."
  @spec defaults() :: t()
  def defaults, do: %__MODULE__{}

  @doc """
  Returns the built-in defaults as a plain map (string keys). Used by
  the Settings UI to seed the form on first save and by tests that
  compare against expected serialized shape.
  """
  @spec default_map() :: map()
  def default_map do
    %{
      "understood_languages" => @builtin_defaults.understood_languages,
      "audio_priority" => @builtin_defaults.audio_priority,
      "subtitles_when" => @builtin_defaults.subtitles_when,
      "subtitles_language" => @builtin_defaults.subtitles_language,
      "subtitles_variant" => @builtin_defaults.subtitles_variant,
      "forced_subs" => @builtin_defaults.forced_subs
    }
  end

  @doc """
  Loads the policy from Settings, applying built-in fallbacks for any
  field missing from the persisted value. Returns a `%LanguagePolicy{}`
  ready to hand to `TrackResolver.resolve/4`.
  """
  @spec load() :: t()
  def load do
    case Settings.get_by_key(@settings_key) do
      %{value: value} when is_map(value) -> from_map(value)
      _ -> defaults()
    end
  end

  @doc """
  Build a policy from the Settings form's submitted params. Languages
  arrive as a comma-separated string and are split/trimmed/normalized;
  audio priority arrives as a single preset token (`"original_first"` |
  `"understood_first"` | `"any"`) which expands to the ordered list the
  resolver expects; the subtitle enums pass through verbatim.
  """
  @spec from_form(map()) :: t()
  def from_form(params) when is_map(params) do
    %__MODULE__{
      understood_languages: parse_languages(params["understood_languages"]),
      audio_priority: parse_audio_priority(params["audio_priority"]),
      subtitles_when: params["subtitles_when"] || @builtin_defaults.subtitles_when,
      subtitles_language: params["subtitles_language"] || @builtin_defaults.subtitles_language,
      subtitles_variant: params["subtitles_variant"] || @builtin_defaults.subtitles_variant,
      forced_subs: params["forced_subs"] || @builtin_defaults.forced_subs
    }
  end

  @doc """
  Reverse of `from_form`'s audio-priority mapping: collapse the ordered
  list back to the select's preset token, so the form can show the
  current selection.
  """
  @spec audio_priority_preset(t()) :: String.t()
  def audio_priority_preset(%__MODULE__{audio_priority: priority}) do
    case priority do
      ["understood" | _] -> "understood_first"
      ["any"] -> "any"
      _ -> "original_first"
    end
  end

  @doc """
  Persists the policy. Accepts either a `%LanguagePolicy{}` or a plain
  map with string-keyed fields (as produced by a form submit). Returns
  `{:ok, _}` / `{:error, _}` from the Settings write.
  """
  @spec save(t() | map()) :: {:ok, Settings.Entry.t()} | {:error, Ecto.Changeset.t()}
  def save(%__MODULE__{} = policy) do
    save(to_map(policy))
  end

  def save(value) when is_map(value) do
    Settings.find_or_create_entry(%{key: @settings_key, value: value})
  end

  @doc """
  Serializes a `%LanguagePolicy{}` to the string-keyed map shape used in
  Settings storage and form submits.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = policy) do
    %{
      "understood_languages" => policy.understood_languages,
      "audio_priority" => policy.audio_priority,
      "subtitles_when" => policy.subtitles_when,
      "subtitles_language" => policy.subtitles_language,
      "subtitles_variant" => policy.subtitles_variant,
      "forced_subs" => policy.forced_subs
    }
  end

  defp from_map(value) when is_map(value) do
    %__MODULE__{
      # Boundary normalization: canonicalize understood languages to
      # 3-letter ISO 639-2/T on load so the resolver compares like with
      # like regardless of whether the user typed "en" or "eng".
      understood_languages:
        value
        |> read_list("understood_languages", @builtin_defaults.understood_languages)
        |> Enum.map(&Iso639.normalize/1),
      audio_priority: read_list(value, "audio_priority", @builtin_defaults.audio_priority),
      subtitles_when: read_string(value, "subtitles_when", @builtin_defaults.subtitles_when),
      subtitles_language: read_string(value, "subtitles_language", @builtin_defaults.subtitles_language),
      subtitles_variant: read_string(value, "subtitles_variant", @builtin_defaults.subtitles_variant),
      forced_subs: read_string(value, "forced_subs", @builtin_defaults.forced_subs)
    }
  end

  defp read_string(value, key, default) do
    case Map.get(value, key) do
      v when is_binary(v) -> v
      _ -> default
    end
  end

  defp read_list(value, key, default) do
    case Map.get(value, key) do
      v when is_list(v) -> Enum.filter(v, &is_binary/1)
      _ -> default
    end
  end

  defp parse_languages(nil), do: @builtin_defaults.understood_languages

  defp parse_languages(value) when is_binary(value) do
    value
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&Iso639.normalize/1)
    |> case do
      [] -> @builtin_defaults.understood_languages
      langs -> langs
    end
  end

  defp parse_audio_priority("understood_first"), do: ["understood", "original", "any"]
  defp parse_audio_priority("any"), do: ["any"]
  defp parse_audio_priority(_), do: ["original", "understood", "any"]
end
