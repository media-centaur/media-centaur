defmodule MediaCentaur.Search.TitleForm do
  @moduledoc """
  The two forms a title takes once it leaves TMDB: the one an indexer is
  asked for, and the one identity comparison uses.

  Both start by folding the title to the ASCII letters scene releases are
  named with. TMDB carries a title as it is written (`Amélie`); release
  groups write `Amelie`. That difference costs on both sides — measured
  against a live indexer, `Amélie` returned 4 results where `Amelie`
  returned 38, and an unfolded comparison never matched the releases it
  did return, because the accented letter is not the same token.

  Apostrophes go the same way (`Sample's Movie` is released as
  `Samples.Movie`), which is why both forms live here rather than one in
  the query builder and one in the matcher: the two must agree, and a
  rule written twice is a rule that drifts.

  Applies to constructed terms only (`Acquisition.Plans.LadderTerms`,
  `Search.QueryBuilder`'s tmdb variants) and to `Search.TitleMatcher`.
  A user-typed `manual_query` passes through untouched — the user
  already trusts their query.

  Pure module — no I/O, no DB.
  """

  # Letters that carry no canonical decomposition, so NFD leaves them
  # whole. Scene names spell them out; the list is deliberately short —
  # these are the ones that actually appear in film and series titles.
  @indivisible %{
    "ß" => "ss",
    "æ" => "ae",
    "œ" => "oe",
    "ø" => "o",
    "đ" => "d",
    "ð" => "d",
    "þ" => "th",
    "ł" => "l",
    "ħ" => "h",
    "ı" => "i"
  }

  @combining_marks ~r/[\x{0300}-\x{036F}]/u
  @apostrophes ~r/['']/u

  @doc """
  The form sent to an indexer: folded to ASCII, apostrophes removed,
  whitespace collapsed. Keeps the title's own casing and punctuation —
  indexers tokenize those away themselves (a colon changes nothing,
  measured), and preserving them keeps a search term readable in the
  console and the corpus key.
  """
  @spec query(String.t()) :: String.t()
  def query(title) do
    title
    |> fold()
    |> String.replace(@apostrophes, "")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  @doc """
  The form identity comparison uses: folded to ASCII, case-folded,
  apostrophes removed, and every run of anything else read as a single
  separator — so `Sample's Show Twelve` and `Samples.Show.Twelve` are
  the same title.
  """
  @spec compare(String.t()) :: String.t()
  def compare(title) do
    title
    |> fold()
    |> String.downcase()
    |> String.replace(@apostrophes, "")
    |> String.replace(~r/[^a-z0-9]+/, " ")
    |> String.trim()
  end

  # NFD splits an accented letter into its base plus a combining mark;
  # dropping the marks leaves the base. The handful of letters that do
  # not decompose are spelled out first.
  defp fold(title) do
    title
    |> spell_out_indivisible()
    |> :unicode.characters_to_nfd_binary()
    |> String.replace(@combining_marks, "")
  end

  defp spell_out_indivisible(title) do
    Enum.reduce(@indivisible, title, fn {letter, spelling}, folded ->
      folded
      |> String.replace(letter, spelling)
      |> String.replace(String.upcase(letter), String.capitalize(spelling))
    end)
  end
end
