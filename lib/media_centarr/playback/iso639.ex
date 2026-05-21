defmodule MediaCentarr.Playback.Iso639 do
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
