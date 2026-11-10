defmodule MediaCentaur.ServiceFlags do
  use Boundary, top_level?: true, check: [in: false, out: false]

  @moduledoc """
  Turns a service start flag on or off the way the product does, for a
  sync test that needs the watchers or a pipeline running.

  The test env is an inert instance (`background_services: false` in
  `config/test.exs`), under which `Settings.Services.start?/1` is false
  whatever the row says. `enable_background_services/0` loads the config of
  an instance that runs background services; `turn_on/2` then persists the
  flag and reconciles its FlagSupervisor synchronously. The sandbox
  restores the app env, the loaded config and the rows at check-in, and the
  FlagSupervisor's check-in reset turns its children off again.

  Call `enable_background_services/0` before any `:persistent_term` config
  override the test makes — it reloads the config.
  """

  alias MediaCentaur.FlagSupervisor
  alias MediaCentaur.Settings.Config
  alias MediaCentaur.Settings.Services

  @spec enable_background_services() :: :ok
  def enable_background_services do
    Application.put_env(:media_centaur, :background_services, true)
    :ok = Config.load!()
  end

  @doc "Persists `flag` on and reconciles `flag_supervisor` now."
  @spec turn_on(Services.service(), FlagSupervisor.server()) :: :ok
  def turn_on(flag, flag_supervisor) do
    Services.set(flag, true)
    FlagSupervisor.reconcile(flag_supervisor)
  end

  @doc "Persists `flag` off and reconciles `flag_supervisor` now."
  @spec turn_off(Services.service(), FlagSupervisor.server()) :: :ok
  def turn_off(flag, flag_supervisor) do
    Services.set(flag, false)
    FlagSupervisor.reconcile(flag_supervisor)
  end
end
