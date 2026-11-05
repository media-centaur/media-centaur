defmodule MediaCentaur.Repo.Migrations.AddCancelledDetailToAcquisitionTargets do
  @moduledoc """
  A release attempt carries its own ending. Beside `cancelled_reason`, the
  download client's words for why the release was abandoned (SABnzbd's fail
  message) — which until now lived only on the `auto_cancelled` event's
  payload, with no link back to the target (campaign `pursuit-window.md`,
  M4). Forward-only: earlier rows stay nil.
  """
  use Ecto.Migration

  def change do
    alter table(:acquisition_targets) do
      add :cancelled_detail, :string
    end
  end
end
