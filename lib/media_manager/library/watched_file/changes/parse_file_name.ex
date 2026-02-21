defmodule MediaManager.Library.WatchedFile.Changes.ParseFileName do
  @moduledoc """
  Ash change that parses the file path into title, year, type, season,
  and episode attributes using `MediaManager.Parser`.
  """
  use Ash.Resource.Change

  def change(changeset, _opts, _context) do
    file_path = Ash.Changeset.get_attribute(changeset, :file_path)
    result = MediaManager.Parser.parse(file_path)

    changeset
    |> Ash.Changeset.change_attribute(:parsed_title, result.title)
    |> Ash.Changeset.change_attribute(:parsed_year, result.year)
    |> Ash.Changeset.change_attribute(:parsed_type, result.type)
    |> Ash.Changeset.change_attribute(:season_number, result.season)
    |> Ash.Changeset.change_attribute(:episode_number, result.episode)
  end
end
