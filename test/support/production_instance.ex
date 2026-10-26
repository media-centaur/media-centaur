defmodule MediaCentaur.ProductionInstance do
  use Boundary, top_level?: true, check: [in: false, out: false]

  @moduledoc """
  The configuration of a production instance that runs background
  services, for tests of behaviour that only such an instance has (the
  self-update check: `SelfUpdate.enabled?/0`). The suite itself runs as
  an instance without background services (`config/test.exs`), so a test
  that wants the check to run loads this first. Both the app env and the
  loaded config are restored by `GlobalStateSandbox` at check-in, so the
  test module must be `async: false`.

      import MediaCentaur.ProductionInstance
      setup :setup_production_instance

  or, inside one test, `production_instance!()`.
  """

  alias MediaCentaur.Settings.Config

  @doc "Loads the config of a production instance with background services on."
  @spec production_instance!() :: :ok
  def production_instance! do
    Application.put_env(:media_centaur, :environment, :prod)
    Application.put_env(:media_centaur, :background_services, true)
    :ok = Config.load!()
  end

  @doc "`production_instance!/0` as a setup callback."
  @spec setup_production_instance(map()) :: :ok
  def setup_production_instance(_context), do: production_instance!()
end
