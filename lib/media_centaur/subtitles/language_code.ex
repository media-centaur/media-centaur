defmodule MediaCentaur.Subtitles.LanguageCode do
  @moduledoc """
  Normalises subtitle language codes to ISO 639-1 (two-letter, lowercase).

  Both ffprobe (`tags.language` from MKV/MP4 containers) and sidecar
  filename suffixes (`Movie.eng.srt`, `Movie.en.srt`) emit a mix of
  ISO 639-2 (three-letter) and ISO 639-1 (two-letter) codes. The UI
  needs a single canonical form, so this module funnels all inputs
  through one mapping.

  Thin projection over `MediaCentaur.Iso639` — the boundary-neutral owner
  of the one code table (ADR-048). This module used to hard-code its own
  smaller 3→2 table, which drifted from the playback table (e.g. `est` /
  `hrv` resolved for playback but returned `nil` here). Sharing the table
  *widens* subtitle detection to the fuller language set — an intended
  improvement the previous moduledoc already sanctioned ("expand the table
  when a real-world rip surfaces a missing one").

  Unknown or non-language inputs (`forced`, `sdh`, `default`, `""`,
  `nil`) return `nil` — the caller's signal that the source carried
  no usable language metadata.
  """

  alias MediaCentaur.Iso639

  @spec normalize(String.t() | nil) :: String.t() | nil
  defdelegate normalize(code), to: Iso639, as: :to_iso1
end
