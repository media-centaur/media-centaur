defmodule MediaCentaur.Retention.ObanPolicy do
  @moduledoc """
  Describes the `oban_jobs` retention handled by `Oban.Plugins.Pruner`
  (configured in `config/config.exs`). The plugin deletes finished jobs
  continuously on its own cadence, so this policy is `:external` — it
  exists so the Status page states the window, read live from the Oban
  config to stay truthful.
  """
  @behaviour MediaCentaur.Retention.PolicyProvider

  alias MediaCentaur.Retention.Policy

  @impl true
  def policies do
    [
      %Policy{
        key: :oban_jobs,
        subsystem: :system,
        label: "Background jobs",
        description: "Finished jobs are deleted after #{pruner_max_age_days()} days.",
        mode: :external
      }
    ]
  end

  defp pruner_max_age_days do
    :media_centaur
    |> Application.fetch_env!(Oban)
    |> Keyword.get(:plugins, [])
    |> Enum.find_value(7, fn
      {Oban.Plugins.Pruner, opts} -> div(Keyword.fetch!(opts, :max_age), 86_400)
      _other -> nil
    end)
  end
end
