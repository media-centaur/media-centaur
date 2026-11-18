defmodule MediaCentaur.Settings.Services do
  @moduledoc """
  The start flags for optional services (`:start_watchers`,
  `:start_pipeline`, `:start_image_pipeline`, `:start_acquisition`).

  One Settings entry per service under `services:<service>` with the value
  `%{"enabled" => boolean}`. Each service's FlagSupervisor reads its flag
  (`start?/1`) at boot and on its broadcast; the Settings page and
  `Acquisition.AutoGrabService` write them. A service with no entry runs.

  The key carries no environment: one instance owns a database (ADR-084),
  so there is never a second instance on the same rows whose flags must be
  kept apart.

  A row is a preference of an instance that runs background services at
  all. In one started with `background_services = false`
  (`Settings.Config`) `start?/1` answers no for every service, whatever
  the row says — the rows of a copied database must not wake it.
  """

  alias MediaCentaur.Settings
  alias MediaCentaur.Settings.Config

  @type service :: atom()

  @doc "The Settings key for `service`."
  @spec key(service()) :: String.t()
  def key(service) when is_atom(service), do: "services:#{service}"

  @doc "Persists the start flag for `service`."
  @spec set(service(), boolean()) :: Settings.Entry.t()
  def set(service, enabled?) when is_atom(service) and is_boolean(enabled?) do
    Settings.find_or_create_entry!(%{key: key(service), value: %{"enabled" => enabled?}})
  end

  @doc """
  Whether `service` runs in this instance: false when the instance runs no
  background services, else the persisted flag, else true. The one read of
  a service flag: the FlagSupervisors read it at start and on the flag's
  broadcast, the Settings page shows it.
  """
  @spec start?(service()) :: boolean()
  def start?(service) when is_atom(service) do
    Config.get(:background_services) and persisted_flag(service)
  end

  defp persisted_flag(service) do
    case Settings.get_by_key(key(service)) do
      %{value: %{"enabled" => enabled?}} when is_boolean(enabled?) -> enabled?
      _ -> true
    end
  end
end
