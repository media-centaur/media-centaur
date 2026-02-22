defmodule MediaManager.Library.WatchedFile.Changes.ParseFileName do
  @moduledoc """
  Ash change that parses the file path into title, year, type, season,
  and episode attributes using `MediaManager.Parser`.
  """
  use Ash.Resource.Change

  def change(changeset, _opts, _context) do
    file_path = Ash.Changeset.get_attribute(changeset, :file_path)
    extras_dirs = extras_dirs_from_config()
    result = MediaManager.Parser.parse(file_path, extras_dirs: extras_dirs)

    changeset
    |> Ash.Changeset.change_attribute(:parsed_title, result.title)
    |> Ash.Changeset.change_attribute(:parsed_year, result.year)
    |> Ash.Changeset.change_attribute(:parsed_type, result.type)
    |> Ash.Changeset.change_attribute(:season_number, result.season)
    |> Ash.Changeset.change_attribute(:episode_number, result.episode)
    |> maybe_set_extra_search_context(result)
  end

  defp maybe_set_extra_search_context(changeset, %{type: :extra} = result) do
    changeset
    |> Ash.Changeset.change_attribute(:search_title, result.parent_title)
    |> Ash.Changeset.change_attribute(:parsed_year, result.parent_year)
  end

  defp maybe_set_extra_search_context(changeset, _result), do: changeset

  defp extras_dirs_from_config do
    case MediaManager.Config.get(:extras_dirs) do
      dirs when is_list(dirs) -> Enum.map(dirs, &String.downcase/1)
      _ -> nil
    end
  end
end
