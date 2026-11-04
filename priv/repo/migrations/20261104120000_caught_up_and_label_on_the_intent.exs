defmodule MediaCentaur.Repo.Migrations.CaughtUpAndLabelOnTheIntent do
  @moduledoc """
  The title intent gains the two facts only the person can state about a
  title (campaign `discovery.md`, M16): the **caught-up point**
  (`caught_up_season`, `caught_up_episode` — a series only) and the
  **label** (`title_name`, `title_year` — the name and year the record was
  acted on with, painted when the TMDB store holds no snapshot). The
  tracking item loses `dismiss_released_before`, a column nothing ever
  wrote: the point is the one representation of "I have seen up to here".

  The data move — an unlinked tracked series' start point out of the
  item's library-watermark columns onto its intent, and the labels from
  the store — is the data migration of the same name.

  `down/0` restores the dead column empty and drops the four.
  """
  use Ecto.Migration

  def up do
    alter table(:title_intents) do
      add :caught_up_season, :integer
      add :caught_up_episode, :integer
      add :title_name, :string
      add :title_year, :string
    end

    alter table(:release_tracking_items) do
      remove :dismiss_released_before
    end
  end

  def down do
    alter table(:release_tracking_items) do
      add :dismiss_released_before, :date
    end

    alter table(:title_intents) do
      remove :caught_up_season
      remove :caught_up_episode
      remove :title_name
      remove :title_year
    end
  end
end
