defmodule MediaCentaur.Repo.Migrations.AddWantedTitleToReviewPendingFiles do
  @moduledoc """
  The title a grab of ours asked for, when a file's match contradicts it
  (`Pipeline.Stages.Search`): what the Review row names as the reason it
  waits.
  """
  use Ecto.Migration

  def change do
    alter table(:review_pending_files) do
      add :wanted_title, :string
    end
  end
end
