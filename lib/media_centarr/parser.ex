defmodule MediaCentarr.Parser do
  use Boundary, top_level?: true, check: [in: false, out: false]

  @moduledoc """
  Parses media file paths to extract title, year, type, season, and episode information.
  Pure module — no GenServer, no DB, no side effects.

  ## Patterns Recognised

  **Movie:**

      Movie.Name.YEAR.1080p.BluRay.x264-GROUP.mkv
      Movie Name (YEAR).mkv
      Movie Name YEAR.mkv
      /path/to/Movie Name (YEAR)/movie.mkv   # directory name used if file is generic

  **TV:**

      Show.Name.S01E05.Episode.Title.1080p.mkv
      Show Name - S01E05 - Episode Title.mkv
      Show.Name.S01E05-06.mkv                 # multi-episode (treat as first episode)
      /Show Name/Season 1/S01E05 - Title.mkv  # directory hints used

  ## Decision Tree

  `candidate_name/1` selects the best text source, then pattern matching
  (TV → season pack → movie → unknown) classifies the result, followed by
  title cleaning.

  **`candidate_name/1` fallback chain:**

  1. Parent is a season directory (`Season 1`, `S01`) → use grandparent (show name) + filename base
  2. Filename is a bare episode marker (`S01E03`) → use parent directory + filename base
  3. Filename is generic or very short lowercase → use parent directory
  4. Otherwise → use filename base

  **Quality token stripping:** bracket patterns first, then quality keywords,
  then release groups.

  **TV title extraction:** strips year tokens, cleans title, strips trailing
  season markers (`S01`), falls back to directory names when the result is empty.

  **Key constraint:** TV pattern `(.+?)SxxExx` requires at least one character
  before the S marker — bare episode filenames like `S01E03.mkv` won't match
  TV on their own, which is why `candidate_name/1` must prepend the show name
  from ancestor directories.
  """

  defmodule Result do
    @moduledoc false
    @enforce_keys [:file_path, :title, :type]
    defstruct [
      :file_path,
      :title,
      :year,
      :type,
      :season,
      :episode,
      :episode_title,
      :parent_title,
      :parent_year
    ]

    @type t :: %__MODULE__{
            file_path: String.t(),
            title: String.t(),
            year: integer() | nil,
            type: :movie | :tv | :extra | :unknown,
            season: integer() | nil,
            episode: integer() | nil,
            episode_title: String.t() | nil,
            parent_title: String.t() | nil,
            parent_year: integer() | nil
          }
  end

  @doc """
  Resolves the effective media type for extras.

  Extras with a season number are TV extras; extras without are movie extras.
  Non-extra types pass through unchanged.
  """
  @spec effective_media_type(Result.t()) :: :movie | :tv | :extra | :unknown
  def effective_media_type(%Result{type: :extra, season: season}) when is_integer(season), do: :tv
  def effective_media_type(%Result{type: :extra}), do: :movie
  def effective_media_type(%Result{type: type}), do: type

  @default_extras_dirs ~w(extras featurettes bonus sample samples)
  @default_extras_dirs_multi_word ["special features", "behind the scenes", "deleted scenes"]

  @generic_names ~w(movie video episode file index sample)

  @media_extensions ~w(.mkv .mp4 .avi .mov .wmv .m4v .flv .ts .m2ts .iso .webm .mpg .mpeg)

  # Quality tokens that signal the end of the meaningful title/episode portion
  @quality_pattern ~r/\b(2160p|1080p|720p|480p|4K|UHD|BluRay|BDRip|BDRemux|BDMux|WEB-DL|WEBRip|WEB|HDTV|DVDRip|Blu-ray|REMASTERED|REPACK|PROPER|COMPLETE|HYBRID|LIMITED|AMZN|ATVP|CRAV|HULU|iCMAL|iTA|ENG|ITA|FRE|DUAL)\b.*$/i

  @quality_bracket_pattern ~r/[\[(][^\])]*(1080|720|2160|BluRay|WEB|x26|HEVC|HDR|DDP|AAC|YTS|TGx)[^\])]*[\])]/i

  @release_group_pattern ~r/\s*-\s*[A-Za-z0-9][A-Za-z0-9.]*$/

  @url_prefix_pattern ~r/^www\.\S+\s+-\s+/i

  # SxxExx pattern — captures show name, season, episode, optional episode title
  @tv_pattern ~r/^(.+?)[.\s_-]*[Ss](\d{1,2})[Ee](\d{1,2})(?:-[Ee]?\d{1,2})?(?:[.\s_-]+(.+?))?$/i

  # NxNN pattern — e.g. "Show Name 7x02 - Episode Title"
  @tv_nxnn_pattern ~r/^(.+?)[.\s_-]+(\d{1,2})x(\d{2,3})(?:[.\s_-]+(.+?))?$/i

  # Spelled-out "Season N Episode N" pattern — e.g. "Show (2022) Season 5 Episode 1- Title"
  @tv_spelled_pattern ~r/^(.+?)\s*Season\s+(\d+)\s*Episode\s+(\d+)[.\s_-]*(.+)?$/i

  # Season-only pack pattern (no episode number)
  @season_pack_pattern ~r/^(.+?)[.\s_-]*[Ss](\d{1,2})[.\s_-]/i

  # Year pattern for movies: 4 digits between 1900–2099 with surrounding separators (or end-of-string)
  @year_pattern ~r/[\s.\[(]((19|20)\d{2})(?:[\s.)\]]|$)/

  # Year pattern for TV: includes parentheses as valid delimiters
  @year_in_tv_title_pattern ~r/[\s._\[(]((19|20)\d{2})[\s._\])]/

  @spec parse(String.t(), keyword()) :: Result.t()
  def parse(file_path, opts \\ []) do
    extras_dirs =
      Keyword.get(opts, :extras_dirs, @default_extras_dirs ++ @default_extras_dirs_multi_word)

    cond do
      extras_file?(file_path, extras_dirs) ->
        parse_extra(file_path, extras_dirs)

      sample_filename?(file_path) ->
        parse_sample(file_path)

      result = parse_compact_episode(file_path) ->
        result

      true ->
        candidate = candidate_name(file_path)
        candidate = strip_url_prefix(candidate)

        cond do
          match = Regex.run(@tv_pattern, candidate, capture: :all_but_first) ->
            parse_tv(file_path, candidate, match)

          match = Regex.run(@tv_nxnn_pattern, candidate, capture: :all_but_first) ->
            parse_tv(file_path, candidate, match)

          match = Regex.run(@tv_spelled_pattern, candidate, capture: :all_but_first) ->
            parse_tv(file_path, candidate, match)

          match = Regex.run(@season_pack_pattern, candidate, capture: :all_but_first) ->
            parse_season_pack(file_path, match)

          match = Regex.run(@year_pattern, candidate, capture: :all_but_first) ->
            parse_movie(file_path, candidate, match)

          true ->
            parse_unknown(file_path, candidate)
        end
    end
  end

  # ---------------------------------------------------------------------------
  # Extras detection
  # ---------------------------------------------------------------------------

  defp extras_file?(file_path, extras_dirs) do
    find_extras_ancestor(file_path, extras_dirs) != nil
  end

  @sample_suffix_pattern ~r/-sample$/i

  defp sample_filename?(file_path) do
    base = base_without_media_extension(file_path)
    Regex.match?(@sample_suffix_pattern, base)
  end

  defp parse_sample(file_path) do
    parent = file_path |> Path.dirname() |> Path.basename()
    {parent_title, parent_year} = parse_parent_movie(parent)

    %Result{
      file_path: file_path,
      title: "Sample",
      type: :extra,
      parent_title: parent_title,
      parent_year: parent_year
    }
  end

  # Returns the index (in Path.split/1) of the extras directory ancestor, or nil
  defp find_extras_ancestor(file_path, extras_dirs) do
    parts = Path.split(file_path)
    downcased_dirs = Enum.map(extras_dirs, &String.downcase/1)

    parts
    |> Enum.with_index()
    |> Enum.drop(-1)
    |> Enum.find_value(fn {part, index} ->
      if String.downcase(part) in downcased_dirs, do: index
    end)
  end

  defp parse_extra(file_path, extras_dirs) do
    parts = Path.split(file_path)
    extras_index = find_extras_ancestor(file_path, extras_dirs)

    # Directories between the extras dir and the file (e.g. Featurettes/subdir/file.mkv → ["subdir"])
    intermediate_dirs = Enum.slice(parts, (extras_index + 1)..(length(parts) - 2)//1)
    base = base_without_media_extension(file_path)

    extra_title =
      case intermediate_dirs do
        [] -> clean_title(base, strip_release_group: false)
        dirs -> clean_title(Enum.join(dirs ++ [base], " - "), strip_release_group: false)
      end

    {parent_title, parent_year, season} = parse_extra_parent(parts, extras_index)

    %Result{
      file_path: file_path,
      title: extra_title,
      year: nil,
      type: :extra,
      season: season,
      episode: nil,
      episode_title: nil,
      parent_title: parent_title,
      parent_year: parent_year
    }
  end

  defp parse_extra_parent(parts, extras_index) do
    above_extras = if extras_index > 0, do: Enum.at(parts, extras_index - 1)

    cond do
      # Layout A: directory above extras is a pure season dir (Season 1, S01)
      above_extras && season_directory?(above_extras) ->
        season = extract_season_number(above_extras)
        two_above = if extras_index > 1, do: Enum.at(parts, extras_index - 2)
        {title, year} = parse_parent_movie(two_above)
        {title, year, season}

      # Layout B: directory above extras contains embedded season marker
      above_extras && extract_embedded_season(above_extras) != nil ->
        season = extract_embedded_season(above_extras)
        {title, year} = parse_parent_with_season_stripped(above_extras)
        {title, year, season}

      # Movie extra
      true ->
        {title, year} = parse_parent_movie(above_extras)
        {title, year, nil}
    end
  end

  defp extract_season_number(dir) do
    case Regex.run(~r/^Season\s+(\d+)$/i, dir, capture: :all_but_first) do
      [num] ->
        String.to_integer(num)

      nil ->
        case Regex.run(~r/^[Ss](\d{1,2})$/, dir, capture: :all_but_first) do
          [num] -> String.to_integer(num)
          nil -> nil
        end
    end
  end

  defp extract_embedded_season(dir) do
    case Regex.run(~r/\bSeason\s+(\d+)/i, dir, capture: :all_but_first) do
      [num] ->
        String.to_integer(num)

      nil ->
        case Regex.run(~r/[.\s_-]S(\d{2})[.\s_-]/i, dir, capture: :all_but_first) do
          [num] -> String.to_integer(num)
          nil -> nil
        end
    end
  end

  defp parse_parent_with_season_stripped(dir_name) do
    # Strip from the season marker onward, then parse as a movie parent
    stripped = Regex.replace(~r/\s*\bSeason\s+\d+\b.*/i, dir_name, "")

    stripped =
      if stripped == dir_name do
        Regex.replace(~r/\s*[.\s_-]S\d{2}[.\s_-].*/i, dir_name, "")
      else
        stripped
      end

    parse_parent_movie(stripped)
  end

  defp parse_parent_movie(nil), do: {nil, nil}

  defp parse_parent_movie(dir_name) do
    # Pad with space so year pattern can match at boundaries
    padded = " " <> dir_name <> " "

    case Regex.run(@year_pattern, padded, capture: :all_but_first) do
      [year_str | _] ->
        year = String.to_integer(year_str)

        title =
          case Regex.run(~r/^(.+?)[\s.\[(]#{year_str}/, dir_name, capture: :all_but_first) do
            [raw_title] -> clean_title(raw_title, strip_release_group: false)
            nil -> clean_title(dir_name, strip_release_group: false)
          end

        {title, year}

      nil ->
        {clean_title(dir_name, strip_release_group: false), nil}
    end
  end

  # ---------------------------------------------------------------------------
  # Candidate name selection
  # ---------------------------------------------------------------------------

  defp candidate_name(file_path) do
    parts = Path.split(file_path)
    base = base_without_media_extension(file_path)
    parent = parts |> Enum.drop(-1) |> List.last()
    grandparent = parts |> Enum.drop(-2) |> List.last()

    cond do
      # File is inside a "Season N" or "S01" directory → use grandparent (show name) + file base
      # Skip prepend if the base already starts with the show name (e.g. "Show Name 7x02")
      parent && season_directory?(parent) ->
        show_name = grandparent || base

        if grandparent && String.starts_with?(String.downcase(base), String.downcase(grandparent)) do
          base
        else
          show_name <> " " <> base
        end

      # Bare episode filename (e.g. "S01E03") → prepend parent directory name
      bare_episode?(base) && parent ->
        parent <> " " <> base

      # Generic or very short lowercase base → use parent directory
      generic_base?(base) && parent ->
        parent

      true ->
        base
    end
  end

  defp season_directory?(dir) do
    Regex.match?(~r/^(Season\s+\d+|[Ss]\d{1,2})$/i, dir)
  end

  defp bare_episode?(base) do
    Regex.match?(~r/^[Ss]\d{1,2}[Ee]\d{1,2}$/, base)
  end

  # Only strip the extension if it's a known media format — prevents confusing
  # extensions from URL-style filenames like "www.site.org - Show S01E01"
  defp base_without_media_extension(path) do
    ext = path |> Path.extname() |> String.downcase()

    if ext in @media_extensions do
      Path.basename(path, Path.extname(path))
    else
      Path.basename(path)
    end
  end

  defp generic_base?(base) do
    lowercase_base = String.downcase(base)

    Enum.member?(@generic_names, lowercase_base) ||
      (base == lowercase_base && String.length(base) <= 10 &&
         not Regex.match?(~r/[Ss]\d{1,2}[Ee]\d{1,2}/, base))
  end

  # ---------------------------------------------------------------------------
  # URL prefix stripping
  # ---------------------------------------------------------------------------

  defp strip_url_prefix(candidate) do
    Regex.replace(@url_prefix_pattern, candidate, "")
  end

  # ---------------------------------------------------------------------------
  # Compact episode numbering (e.g. "501" = season 5, episode 01)
  # Only matches when the file is inside a season directory.
  # ---------------------------------------------------------------------------

  # Pattern: digits followed by optional separator and episode title (e.g. "501- My Title")
  @compact_episode_pattern ~r/^(\d{3,4})[.\s_-]*(.+)?$/

  defp parse_compact_episode(file_path) do
    parts = Path.split(file_path)
    parent = parts |> Enum.drop(-1) |> List.last()
    grandparent = parts |> Enum.drop(-2) |> List.last()
    base = base_without_media_extension(file_path)

    with true <- parent != nil and season_directory?(parent),
         season_from_dir when is_integer(season_from_dir) <- extract_season_number(parent),
         [digits, raw_episode_title] <-
           Regex.run(@compact_episode_pattern, base, capture: :all_but_first),
         {episode, _season_prefix} <- parse_compact_digits(digits, season_from_dir) do
      show_name = if grandparent, do: clean_title(grandparent), else: "Unknown"
      episode_title = extract_episode_title(raw_episode_title)

      %Result{
        file_path: file_path,
        title: show_name,
        year: nil,
        type: :tv,
        season: season_from_dir,
        episode: episode,
        episode_title: episode_title
      }
    else
      _ -> nil
    end
  end

  # Split compact digits into season prefix + episode. The season prefix must match
  # the season from the directory. E.g. "501" with season 5 → episode 01.
  defp parse_compact_digits(digits, season_from_dir) do
    season_str = Integer.to_string(season_from_dir)
    season_len = String.length(season_str)

    if String.starts_with?(digits, season_str) do
      episode_str = String.slice(digits, season_len..-1//1)

      case Integer.parse(episode_str) do
        {episode, ""} when episode > 0 -> {episode, season_str}
        _ -> nil
      end
    end
  end

  # ---------------------------------------------------------------------------
  # TV episode parsing
  # ---------------------------------------------------------------------------

  defp parse_tv(file_path, _candidate, [raw_title, raw_season, raw_episode | rest]) do
    season = String.to_integer(raw_season)
    episode = String.to_integer(raw_episode)
    raw_episode_title = List.first(rest)

    year = extract_year_from_tv_title(raw_title) || extract_year_from_ancestors(file_path)
    title = extract_tv_title(raw_title, file_path)
    episode_title = extract_episode_title(raw_episode_title)

    %Result{
      file_path: file_path,
      title: title,
      year: year,
      type: :tv,
      season: season,
      episode: episode,
      episode_title: episode_title
    }
  end

  defp extract_tv_title(raw_title, file_path) do
    # Strip year tokens before cleaning so they don't appear in the title
    cleaned =
      raw_title
      |> strip_year_tokens()
      |> clean_title()
      |> strip_trailing_season_marker()

    if cleaned == "" do
      # Title was blank — use show directory name
      file_path
      |> Path.split()
      |> Enum.drop(-1)
      |> List.last()
      |> then(fn dir ->
        if dir && season_directory?(dir) do
          file_path |> Path.split() |> Enum.drop(-2) |> List.last()
        else
          dir
        end
      end)
      |> then(&if(&1, do: strip_trailing_season_marker(clean_title(&1)), else: ""))
    else
      cleaned
    end
  end

  # Strip year tokens (with optional surrounding parens/brackets/separators) anywhere in string
  defp strip_year_tokens(str) do
    String.trim(Regex.replace(~r/\s*[\[(]?(19|20)\d{2}[\])]?\s*/, str, " "))
  end

  defp strip_trailing_season_marker(title) do
    Regex.replace(~r/\s+[Ss]\d{1,2}$/, title, "")
  end

  defp extract_year_from_tv_title(raw_title) do
    # Pad with space so the leading delimiter character class can match at position 0
    padded = " " <> raw_title <> " "

    case Regex.run(@year_in_tv_title_pattern, padded, capture: :all_but_first) do
      [year_str | _] -> String.to_integer(year_str)
      nil -> nil
    end
  end

  defp extract_year_from_ancestors(file_path) do
    parts = Path.split(file_path)
    parent = parts |> Enum.drop(-1) |> List.last()
    grandparent = parts |> Enum.drop(-2) |> List.last()

    extract_premiere_year(parent) || extract_premiere_year(grandparent)
  end

  defp extract_premiere_year(nil), do: nil

  defp extract_premiere_year(dir) do
    # Strip remaster/remux year markers so they aren't mistaken for premiere years
    cleaned = Regex.replace(~r/\(?\s*(19|20)\d{2}\s+remaster(ed)?\s*\)?/i, dir, "")
    extract_year_from_tv_title(cleaned)
  end

  defp extract_episode_title(nil), do: nil
  defp extract_episode_title(""), do: nil

  defp extract_episode_title(raw) do
    cleaned =
      raw
      |> then(&Regex.replace(@quality_bracket_pattern, &1, ""))
      |> then(&Regex.replace(@quality_pattern, &1, ""))
      |> then(&Regex.replace(@release_group_pattern, &1, ""))
      |> String.replace(~r/[._]/, " ")
      |> String.replace(~r/\s+/, " ")
      |> String.trim()
      |> title_case()

    if cleaned != "", do: cleaned
  end

  # ---------------------------------------------------------------------------
  # Season pack parsing
  # ---------------------------------------------------------------------------

  defp parse_season_pack(file_path, [raw_title, raw_season | _]) do
    season = String.to_integer(raw_season)
    title = clean_title(raw_title)

    %Result{
      file_path: file_path,
      title: title,
      year: nil,
      type: :tv,
      season: season,
      episode: nil,
      episode_title: nil
    }
  end

  # ---------------------------------------------------------------------------
  # Movie parsing
  # ---------------------------------------------------------------------------

  defp parse_movie(file_path, candidate, [year_str | _]) do
    year = String.to_integer(year_str)

    title =
      case Regex.run(~r/^(.+?)[\s.\[(]#{year_str}/, candidate, capture: :all_but_first) do
        [raw_title] -> clean_title(raw_title)
        nil -> clean_title(candidate)
      end

    %Result{
      file_path: file_path,
      title: title,
      year: year,
      type: :movie,
      season: nil,
      episode: nil,
      episode_title: nil
    }
  end

  # ---------------------------------------------------------------------------
  # Unknown fallback
  # ---------------------------------------------------------------------------

  defp parse_unknown(file_path, candidate) do
    %Result{
      file_path: file_path,
      title: clean_title(candidate),
      year: nil,
      type: :unknown,
      season: nil,
      episode: nil,
      episode_title: nil
    }
  end

  # ---------------------------------------------------------------------------
  # Title cleaning
  # ---------------------------------------------------------------------------

  defp clean_title(raw, opts \\ []) do
    raw
    |> String.replace(~r/[._꞉]/, " ")
    |> String.replace(~r/\s+/, " ")
    |> then(&Regex.replace(@quality_bracket_pattern, &1, ""))
    |> then(&Regex.replace(@quality_pattern, &1, ""))
    |> then(fn cleaned ->
      if Keyword.get(opts, :strip_release_group, true),
        do: Regex.replace(@release_group_pattern, cleaned, ""),
        else: cleaned
    end)
    |> then(&Regex.replace(~r/\s*\(\d{4}\)\s*$/, &1, ""))
    |> String.trim()
    |> then(&Regex.replace(~r/[-_\s]+$/, &1, ""))
    |> String.trim()
    |> title_case()
  end

  defp title_case(""), do: ""

  defp title_case(str) do
    str
    |> String.split(" ")
    |> Enum.map_join(" ", &capitalize_word/1)
  end

  defp capitalize_word(""), do: ""

  defp capitalize_word(word) do
    {first, rest} = String.split_at(word, 1)
    String.upcase(first) <> rest
  end
end
