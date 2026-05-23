defmodule MediaCentaur.Playback.Iso639 do
  @moduledoc """
  ISO 639 language code normalization.

  Real-world media metadata mixes ISO 639-1 (2-letter, used by TMDB:
  `"en"`, `"ja"`) and ISO 639-2/T (3-letter, used by mpv's `track-list`
  for embedded streams: `"eng"`, `"jpn"`). The two forms are not
  string-equal but refer to the same languages.

  Some 639-2 codes also have bibliographic ↔ terminologic alternates
  (`"fre"` / `"fra"` both = French) that mpv may emit depending on the
  encoder. These collapse to the terminologic form.

  Used by `TrackResolver` whenever it compares a policy/override
  language code to a file's track language — call `equal?/2` instead
  of `==`, or `normalize/1` to bring values to a canonical form.

  Covers the ~40 most common subtitle/audio languages. Unknown codes
  pass through unchanged — comparison still works as long as both
  sides spell the language the same way (or one side normalizes via
  this module's table).
  """

  # 2-letter (ISO 639-1) → canonical 3-letter (ISO 639-2/T).
  # Limited to languages plausibly found in media metadata; extend as
  # the library grows.
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

  # Canonical 3-letter ISO 639-2/T code → English display name. Keyed on
  # the *normalized* form, so `display_name/1` works for any input form
  # (2-letter, bibliographic alternate) by normalizing first. Covers the
  # same language set as the tables above; unknown codes fall back to the
  # raw code so the UI degrades to what the metadata actually carried.
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
