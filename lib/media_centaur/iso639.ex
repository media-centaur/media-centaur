defmodule MediaCentaur.Iso639 do
  @moduledoc """
  The one canonical ISO 639 language-code table for the whole system.

  Real-world media metadata mixes ISO 639-1 (2-letter, used by TMDB:
  `"en"`, `"ja"`) and ISO 639-2/T (3-letter, used by mpv's `track-list`
  and by MKV/MP4 container tags: `"eng"`, `"jpn"`). Some 639-2 codes also
  have bibliographic ↔ terminologic alternates (`"fre"` / `"fra"` both =
  French) that an encoder may emit either way. These forms are not
  string-equal but denote the same language.

  This module is the single owner of the code table (ADR-048's
  single-table intent). It is **boundary-neutral** — declared with the
  `top_level?` escape hatch (as `Topics` / `WatcherStatus` are) so both
  the `Playback` and `Subtitles` bounded contexts can normalize codes
  without either depending on the other. `Playback.Iso639` is a thin
  facade over this module (preserving the ADR-048-named API), and
  `Subtitles.LanguageCode` is a thin projection over `to_iso1/1`.

  Two projections of the same table:

    * `normalize/1` → canonical 3-letter ISO 639-2/T (playback comparisons)
    * `to_iso1/1`   → 2-letter ISO 639-1, or `nil` (subtitle-label UI)

  Covers the ~45 most common subtitle/audio languages. Unknown codes pass
  through `normalize/1` unchanged (comparison still works when both sides
  spell it the same) and resolve to `nil` under `to_iso1/1`. Extend the
  tables when a real-world rip surfaces a missing language.
  """
  use Boundary, top_level?: true, check: [in: false, out: false]

  # 2-letter (ISO 639-1) → canonical 3-letter (ISO 639-2/T).
  @two_to_three %{
    "ar" => "ara",
    "bg" => "bul",
    "ca" => "cat",
    "cs" => "ces",
    "da" => "dan",
    "de" => "deu",
    "el" => "ell",
    "en" => "eng",
    "es" => "spa",
    "et" => "est",
    "fa" => "fas",
    "fi" => "fin",
    "fr" => "fra",
    "he" => "heb",
    "hi" => "hin",
    "hr" => "hrv",
    "hu" => "hun",
    "id" => "ind",
    "is" => "isl",
    "it" => "ita",
    "ja" => "jpn",
    "ko" => "kor",
    "la" => "lat",
    "lt" => "lit",
    "lv" => "lav",
    "ms" => "msa",
    "nb" => "nob",
    "nl" => "nld",
    "nn" => "nno",
    "no" => "nor",
    "pl" => "pol",
    "pt" => "por",
    "ro" => "ron",
    "ru" => "rus",
    "sk" => "slk",
    "sl" => "slv",
    "sr" => "srp",
    "sv" => "swe",
    "th" => "tha",
    "tr" => "tur",
    "uk" => "ukr",
    "vi" => "vie",
    "zh" => "zho"
  }

  # ISO 639-2/B (bibliographic) → ISO 639-2/T (terminologic).
  # mpv emits whichever the encoder wrote; we always normalize to T.
  @alternates %{
    "fre" => "fra",
    "ger" => "deu",
    "gre" => "ell",
    "chi" => "zho",
    "cze" => "ces",
    "dut" => "nld",
    "per" => "fas",
    "ice" => "isl",
    "mac" => "mkd",
    "may" => "msa",
    "rum" => "ron",
    "slo" => "slk",
    "tib" => "bod",
    "wel" => "cym",
    "arm" => "hye",
    "bur" => "mya",
    "geo" => "kat"
  }

  # Reverse of @two_to_three: canonical 3-letter (T) → 2-letter (639-1).
  # A T-code with no 639-1 equivalent (e.g. one reached only via an
  # alternate whose 639-1 isn't tabled) simply has no entry → `to_iso1`
  # yields `nil`, the subtitle UI's "no usable language" signal.
  @three_to_one for {two, three} <- @two_to_three, into: %{}, do: {three, two}

  # Canonical 3-letter ISO 639-2/T code → English display name. Keyed on
  # the *normalized* form, so `display_name/1` works for any input form
  # (2-letter, bibliographic alternate) by normalizing first. Unknown
  # codes fall back to the raw code so the UI degrades to what the
  # metadata actually carried.
  @names %{
    "ara" => "Arabic",
    "bod" => "Tibetan",
    "bul" => "Bulgarian",
    "cat" => "Catalan",
    "ces" => "Czech",
    "cym" => "Welsh",
    "dan" => "Danish",
    "deu" => "German",
    "ell" => "Greek",
    "eng" => "English",
    "est" => "Estonian",
    "fas" => "Persian",
    "fin" => "Finnish",
    "fra" => "French",
    "heb" => "Hebrew",
    "hin" => "Hindi",
    "hrv" => "Croatian",
    "hun" => "Hungarian",
    "hye" => "Armenian",
    "ind" => "Indonesian",
    "isl" => "Icelandic",
    "ita" => "Italian",
    "jpn" => "Japanese",
    "kat" => "Georgian",
    "kor" => "Korean",
    "lat" => "Latin",
    "lav" => "Latvian",
    "lit" => "Lithuanian",
    "mkd" => "Macedonian",
    "msa" => "Malay",
    "mya" => "Burmese",
    "nld" => "Dutch",
    "nno" => "Norwegian Nynorsk",
    "nob" => "Norwegian Bokmål",
    "nor" => "Norwegian",
    "pol" => "Polish",
    "por" => "Portuguese",
    "ron" => "Romanian",
    "rus" => "Russian",
    "slk" => "Slovak",
    "slv" => "Slovenian",
    "spa" => "Spanish",
    "srp" => "Serbian",
    "swe" => "Swedish",
    "tha" => "Thai",
    "tur" => "Turkish",
    "ukr" => "Ukrainian",
    "vie" => "Vietnamese",
    "zho" => "Chinese"
  }

  # Reverse index: lowercased display name → canonical code. Compiled
  # from @names so `code_for_name/1` resolves a typed language name.
  @name_to_code for {code, name} <- @names, into: %{}, do: {String.downcase(name), code}

  @doc """
  All known languages as `{code, display_name}` tuples, sorted by name.
  Powers language pickers in the UI — exactly the set the resolver can
  match, so users can only choose languages the app understands.
  """
  @spec all() :: [{String.t(), String.t()}]
  def all do
    Enum.sort_by(@names, fn {_code, name} -> name end)
  end

  @doc """
  Resolve a free-text language input to a canonical 3-letter code, or
  `nil` if it matches no known language. Accepts an exact display name
  (case-insensitive, e.g. `"French"`) or any ISO form of a known code
  (`"fr"`, `"fre"`, `"fra"`). Used by the settings language picker to
  turn what the user typed or selected into a stored code.
  """
  @spec code_for_name(String.t() | nil) :: String.t() | nil
  def code_for_name(nil), do: nil

  def code_for_name(input) when is_binary(input) do
    case String.trim(input) do
      "" -> nil
      trimmed -> Map.get(@name_to_code, String.downcase(trimmed)) || known_code(trimmed)
    end
  end

  defp known_code(input) do
    case normalize(input) do
      code when is_binary(code) -> if Map.has_key?(@names, code), do: code
      _ -> nil
    end
  end

  @doc "Canonicalize a language code to its 3-letter ISO 639-2/T form."
  @spec normalize(String.t() | nil) :: String.t() | nil
  def normalize(nil), do: nil

  def normalize(code) when is_binary(code) do
    code = code |> String.downcase() |> String.trim()

    cond do
      Map.has_key?(@two_to_three, code) -> Map.fetch!(@two_to_three, code)
      Map.has_key?(@alternates, code) -> Map.fetch!(@alternates, code)
      true -> code
    end
  end

  @doc """
  Project a language code to its 2-letter ISO 639-1 form, or `nil` when
  the language has no 639-1 code or is unknown / non-language metadata
  (`"forced"`, `"sdh"`, `""`, `nil`). Normalizes to 3-letter ISO 639-2/T
  first, so any accepted input form (2-letter, bibliographic alternate,
  terminologic) resolves. This is the projection `Subtitles.LanguageCode`
  builds on for the subtitle-label UI.
  """
  @spec to_iso1(String.t() | nil) :: String.t() | nil
  def to_iso1(code) when is_binary(code), do: Map.get(@three_to_one, normalize(code))
  def to_iso1(_), do: nil

  @doc "Compare two language codes, treating equivalent forms as equal."
  @spec equal?(String.t() | nil, String.t() | nil) :: boolean()
  def equal?(a, b), do: normalize(a) == normalize(b)

  @doc """
  Human-readable English name for a language code (`"jpn"` / `"ja"` →
  `"Japanese"`). Normalizes the input first, so any accepted form maps to
  the same name. Unknown codes fall back to the code itself; `nil` → `nil`.
  """
  @spec display_name(String.t() | nil) :: String.t() | nil
  def display_name(nil), do: nil

  def display_name(code) when is_binary(code) do
    case Map.fetch(@names, normalize(code)) do
      {:ok, name} -> name
      :error -> code
    end
  end

  @doc """
  Check whether a language code matches any entry in a list of codes,
  using `equal?/2` semantics. Order-preserving — the first matching
  entry's *original* form is returned, useful when callers care which
  entry from the user's list was hit.
  """
  @spec find_match(String.t() | nil, [String.t()]) :: String.t() | nil
  def find_match(_target, []), do: nil
  def find_match(nil, _languages), do: nil

  def find_match(target, languages) when is_list(languages) do
    Enum.find(languages, fn lang -> equal?(target, lang) end)
  end
end
