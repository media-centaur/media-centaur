defmodule MediaCentaur.Playback.Iso639 do
  @moduledoc """
  Playback-facing facade over the canonical `MediaCentaur.Iso639` table.

  ADR-048 named this module as the resolver's single language-normalization
  entry point (`normalize/1`, `equal?/2`, `find_match/2`, plus the settings
  picker's `all/0`, `code_for_name/1`, `display_name/1`). The code table
  itself now lives in the boundary-neutral `MediaCentaur.Iso639` so the
  `Subtitles` context can share it without depending on `Playback` (it was
  duplicated before — see ADR-048's single-table intent). This module keeps
  the ADR-048 API stable and delegates every call.
  """

  alias MediaCentaur.Iso639

  defdelegate all(), to: Iso639
  defdelegate code_for_name(input), to: Iso639
  defdelegate normalize(code), to: Iso639
  defdelegate equal?(a, b), to: Iso639
  defdelegate display_name(code), to: Iso639
  defdelegate find_match(target, languages), to: Iso639
end
