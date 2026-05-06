defmodule MediaCentarr.Subtitles.LanguageCode do
  @moduledoc """
  Normalises subtitle language codes to ISO 639-1 (two-letter, lowercase).

  Both ffprobe (`tags.language` from MKV/MP4 containers) and sidecar
  filename suffixes (`Movie.eng.srt`, `Movie.en.srt`) emit a mix of
  ISO 639-2 (three-letter) and ISO 639-1 (two-letter) codes. The UI
  needs a single canonical form, so this module funnels all inputs
  through one mapping.

  Unknown or non-language inputs (`forced`, `sdh`, `default`, `""`,
  `nil`) return `nil` — the caller's signal that the source carried
  no usable language metadata.

  Only the codes most likely to appear in curated movie libraries are
  enumerated; expand the table when a real-world rip surfaces a missing
  one. The list is small on purpose — it's not a general-purpose ISO
  registry.
  """

  # ISO 639-2 (bibliographic + terminologic) → ISO 639-1
  @three_to_two %{
    "eng" => "en",
    "spa" => "es",
    "fre" => "fr",
    "fra" => "fr",
    "ger" => "de",
    "deu" => "de",
    "ita" => "it",
    "por" => "pt",
    "rus" => "ru",
    "jpn" => "ja",
    "kor" => "ko",
    "chi" => "zh",
    "zho" => "zh",
    "ara" => "ar",
    "hin" => "hi",
    "nld" => "nl",
    "dut" => "nl",
    "swe" => "sv",
    "nor" => "no",
    "dan" => "da",
    "fin" => "fi",
    "pol" => "pl",
    "ces" => "cs",
    "cze" => "cs",
    "tur" => "tr",
    "heb" => "he",
    "tha" => "th",
    "vie" => "vi",
    "ind" => "id",
    "ell" => "el",
    "gre" => "el",
    "hun" => "hu",
    "ron" => "ro",
    "rum" => "ro",
    "ukr" => "uk",
    "bul" => "bg",
    "cat" => "ca"
  }

  @two_letter_set @three_to_two |> Map.values() |> MapSet.new()

  @spec normalize(String.t() | nil) :: String.t() | nil
  def normalize(nil), do: nil
  def normalize(""), do: nil

  def normalize(code) when is_binary(code) do
    lower = String.downcase(code)

    cond do
      Map.has_key?(@three_to_two, lower) -> Map.fetch!(@three_to_two, lower)
      MapSet.member?(@two_letter_set, lower) -> lower
      true -> nil
    end
  end

  def normalize(_), do: nil
end
