defmodule MediaManager.Parser do
  @moduledoc """
  Parses media file paths to extract title, year, type, season, and episode information.
  Pure module — no GenServer, no DB.
  """

  defmodule Result do
    @enforce_keys [:file_path, :title, :type]
    defstruct [:file_path, :title, :year, :type, :season, :episode, :episode_title]

    @type t :: %__MODULE__{
            file_path: String.t(),
            title: String.t(),
            year: integer() | nil,
            type: :movie | :tv | :unknown,
            season: integer() | nil,
            episode: integer() | nil,
            episode_title: String.t() | nil
          }
  end

  @generic_names ~w(movie video episode file index sample)

  @media_extensions ~w(.mkv .mp4 .avi .mov .wmv .m4v .flv .ts .m2ts .iso .webm .mpg .mpeg)

  # Quality tokens that signal the end of the meaningful title/episode portion
  @quality_pattern ~r/\b(2160p|1080p|720p|480p|4K|UHD|BluRay|BDRip|BDRemux|BDMux|WEB-DL|WEBRip|WEB|HDTV|DVDRip|Blu-ray|REMASTERED|REPACK|PROPER|COMPLETE|HYBRID|LIMITED|AMZN|ATVP|CRAV|HULU|iCMAL|iTA|ENG|ITA|FRE|DUAL)\b.*$/i

  @quality_bracket_pattern ~r/[\[(][^\])]*(1080|720|2160|BluRay|WEB|x26|HEVC|HDR|DDP|AAC|YTS|TGx)[^\])]*[\])]/i

  @release_group_pattern ~r/-[A-Z0-9][A-Z0-9.]*$/

  @url_prefix_pattern ~r/^www\.\S+\s+-\s+/i

  # SxxExx pattern — captures show name, season, episode, optional episode title
  @tv_pattern ~r/^(.+?)[.\s_-]*[Ss](\d{1,2})[Ee](\d{1,2})(?:-[Ee]?\d{1,2})?(?:[.\s_-]+(.+?))?$/i

  # Season-only pack pattern (no episode number)
  @season_pack_pattern ~r/^(.+?)[.\s_-]*[Ss](\d{1,2})[.\s_-]/i

  # Year pattern for movies: 4 digits between 1900–2099 with surrounding separators
  @year_pattern ~r/[\s.\[(]((19|20)\d{2})[\s.)\]]/

  # Year pattern for TV: includes parentheses as valid delimiters
  @year_in_tv_title_pattern ~r/[\s._\[(]((19|20)\d{2})[\s._\])]/

  @spec parse(String.t()) :: Result.t()
  def parse(file_path) do
    candidate = candidate_name(file_path)
    candidate = strip_url_prefix(candidate)

    cond do
      match = Regex.run(@tv_pattern, candidate, capture: :all_but_first) ->
        parse_tv(file_path, candidate, match)

      match = Regex.run(@season_pack_pattern, candidate, capture: :all_but_first) ->
        parse_season_pack(file_path, match)

      match = Regex.run(@year_pattern, candidate, capture: :all_but_first) ->
        parse_movie(file_path, candidate, match)

      true ->
        parse_unknown(file_path, candidate)
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
      # File is inside a "Season N" directory → use grandparent (show name) + file base
      parent && Regex.match?(~r/^Season\s+\d+$/i, parent) ->
        show_name = grandparent || base
        show_name <> " " <> base

      # Generic or very short lowercase base → use parent directory
      generic_base?(base) && parent ->
        parent

      true ->
        base
    end
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
  # TV episode parsing
  # ---------------------------------------------------------------------------

  defp parse_tv(file_path, _candidate, [raw_title, raw_season, raw_episode | rest]) do
    season = String.to_integer(raw_season)
    episode = String.to_integer(raw_episode)
    raw_episode_title = List.first(rest)

    year = extract_year_from_tv_title(raw_title)
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
    cleaned = raw_title |> strip_year_tokens() |> clean_title()

    if cleaned == "" do
      # Title was blank — use show directory name
      file_path
      |> Path.split()
      |> Enum.drop(-1)
      |> List.last()
      |> then(fn dir ->
        if dir && Regex.match?(~r/^Season\s+\d+$/i, dir) do
          file_path |> Path.split() |> Enum.drop(-2) |> List.last()
        else
          dir
        end
      end)
      |> then(&if(&1, do: clean_title(&1), else: ""))
    else
      cleaned
    end
  end

  # Strip year tokens (with optional surrounding parens/brackets/separators) anywhere in string
  defp strip_year_tokens(str) do
    Regex.replace(~r/\s*[\[(]?(19|20)\d{2}[\])]?\s*/, str, " ")
    |> String.trim()
  end

  defp extract_year_from_tv_title(raw_title) do
    # Pad with space so the leading delimiter character class can match at position 0
    padded = " " <> raw_title <> " "

    case Regex.run(@year_in_tv_title_pattern, padded, capture: :all_but_first) do
      [year_str | _] -> String.to_integer(year_str)
      nil -> nil
    end
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

    if cleaned == "", do: nil, else: cleaned
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

  defp clean_title(raw) do
    raw
    |> String.replace(~r/[._]/, " ")
    |> String.replace(~r/\s+/, " ")
    |> then(&Regex.replace(@quality_bracket_pattern, &1, ""))
    |> then(&Regex.replace(@quality_pattern, &1, ""))
    |> then(&Regex.replace(@release_group_pattern, &1, ""))
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
    |> Enum.map(&capitalize_word/1)
    |> Enum.join(" ")
  end

  defp capitalize_word(""), do: ""

  defp capitalize_word(word) do
    {first, rest} = String.split_at(word, 1)
    String.upcase(first) <> rest
  end
end
