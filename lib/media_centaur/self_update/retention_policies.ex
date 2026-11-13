defmodule MediaCentaur.SelfUpdate.RetentionPolicies do
  @moduledoc """
  Retention policies owned by SelfUpdate: staging directories from
  crashed or abandoned update attempts (each 50MB–1GB) are swept once
  they're old enough that no in-flight attempt can own them, and the
  database snapshots taken before an update migrates are kept to the
  newest few.
  """
  @behaviour MediaCentaur.Retention.PolicyProvider

  alias MediaCentaur.Retention.Policy
  alias MediaCentaur.SelfUpdate.{DatabaseSnapshot, StagingSweep}

  @impl true
  def policies do
    [
      %Policy{
        key: :upgrade_staging,
        subsystem: :self_update,
        label: "Update staging files",
        description: "Removed 2 days after an interrupted update.",
        mode: :sweep,
        run: fn -> StagingSweep.sweep() end
      },
      %Policy{
        key: :database_snapshots,
        subsystem: :self_update,
        label: "Database snapshots",
        description:
          "A copy of the database is taken before an update changes it. The newest 3 are kept.",
        mode: :sweep,
        run: fn -> DatabaseSnapshot.sweep(DatabaseSnapshot.directory(database_path())) end
      }
    ]
  end

  defp database_path do
    :media_centaur |> Application.fetch_env!(MediaCentaur.Repo) |> Keyword.fetch!(:database)
  end
end
