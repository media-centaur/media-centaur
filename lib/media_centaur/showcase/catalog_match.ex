defmodule MediaCentaur.Showcase.CatalogMatch do
  use Boundary, top_level?: true, check: [in: false, out: false]

  @moduledoc """
  Picks the TMDB result a `MediaCentaur.Showcase.Catalog` entry meant.

  The catalog is a legally vetted list — every title on it has been
  checked to be public-domain or Creative Commons. TMDB search is ranked
  by popularity, so its first result is the *famous* film with a similar
  name, not the one the catalog names: asking for the Blender short
  "Spring" (2019) returns "Spring Breakers" (2013) first. The seeder used
  to take that first result, which put a copyrighted title in the demo
  catalog and from there into a marketing screenshot.

  So the entry is authoritative and the search only confirms it. A result
  qualifies when its title matches the entry's — ignoring case,
  punctuation and accents, and accepting TMDB's `original_title` for
  films catalogued under a translated name — and its year is within one
  of the entry's, which absorbs regional release-date drift without
  letting a remake through. The closest year wins.

  No qualifying result is an error, never a guess: `MediaCentaur.Showcase`
  raises on it, so a catalog entry TMDB cannot confirm stops the seed
  instead of quietly seeding the wrong film.
  """

  @year_tolerance 1

  @doc """
  The id of the result matching `title` and `year`, or `{:error, {:no_match,
  seen}}` where `seen` lists what TMDB offered. `title_key` is `"title"`
  for movies and `"name"` for TV.
  """
  @spec pick([map()], String.t(), integer(), String.t()) ::
          {:ok, integer()} | {:error, {:no_match, [String.t()]}}
  def pick(results, title, year, title_key) do
    wanted = normalize(title)

    results
    |> Enum.filter(&titles_match?(&1, wanted, title_key))
    |> Enum.map(&{&1["id"], year_of(&1)})
    |> Enum.filter(fn {_id, found} -> found && abs(found - year) <= @year_tolerance end)
    |> Enum.min_by(fn {_id, found} -> abs(found - year) end, fn -> nil end)
    |> case do
      {id, _year} -> {:ok, id}
      nil -> {:error, {:no_match, Enum.map(results, &describe(&1, title_key))}}
    end
  end

  defp titles_match?(result, wanted, title_key) do
    [result[title_key], result["original_title"], result["original_name"]]
    |> Enum.reject(&is_nil/1)
    |> Enum.any?(&(normalize(&1) == wanted))
  end

  defp year_of(result) do
    case result["release_date"] || result["first_air_date"] do
      <<year::binary-4, _rest::binary>> -> String.to_integer(year)
      _absent -> nil
    end
  rescue
    ArgumentError -> nil
  end

  defp describe(result, title_key) do
    name = result[title_key] || result["original_title"] || "?"
    "#{name} (#{year_of(result) || "?"})"
  end

  # Enough normalisation to survive punctuation and accents without
  # letting a different film through: "The Cabinet of Dr. Caligari" and
  # "the cabinet of dr caligari" are the same title, "Spring" and
  # "Spring Breakers" are not.
  defp normalize(title) do
    title
    |> String.normalize(:nfd)
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.downcase()
    |> String.replace(~r/[^\p{L}\p{N}]+/u, " ")
    |> String.trim()
  end
end
