defmodule MediaCentaur.SelfUpdate.RetentionPolicies do
  @moduledoc """
  Retention policy owned by SelfUpdate: staging directories from
  crashed or abandoned update attempts (each 50MB–1GB) are swept once
  they're old enough that no in-flight attempt can own them.
  """
  @behaviour MediaCentaur.Retention.PolicyProvider

  alias MediaCentaur.Retention.Policy
  alias MediaCentaur.SelfUpdate.StagingSweep

  @impl true
  def policies do
    [
      %Policy{
        key: :upgrade_staging,
        subsystem: :self_update,
        label: "Update staging files",
        description:
          "Leftover update staging folders from interrupted attempts are removed after 2 days.",
        mode: :sweep,
        run: fn -> StagingSweep.sweep() end
      }
    ]
  end
end
