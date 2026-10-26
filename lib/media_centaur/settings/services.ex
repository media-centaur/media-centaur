defmodule MediaCentaur.Settings.Services do
  @moduledoc """
  The per-environment start flags for optional services (`:start_watchers`,
  `:start_pipeline`, `:start_acquisition`).

  One Settings entry per `{env, service}` under `services:<env>:<service>`
  with the value `%{"enabled" => boolean}`. `MediaCentaur.Application` reads
  them at boot, the Settings page and `Acquisition.AutoGrabService` write
  them. The environment segment keeps a dev and a production install on the
  same machine from sharing a flag.

  A row is a preference of an instance that runs background services at
  all. In one started with `background_services = false`
  (`Settings.Config`) `enabled?/2` answers no for every service, whatever
  the row says — the rows of a copied database must not wake it.
  """

  alias MediaCentaur.Settings
  alias MediaCentaur.Settings.Config

  @type service :: atom()

  @doc "The Settings key for `service` in the running environment."
  @spec key(service()) :: String.t()
  def key(service) when is_atom(service), do: "services:#{environment()}:#{service}"

  @doc "Persists the start flag for `service`."
  @spec set(service(), boolean()) :: Settings.Entry.t()
  def set(service, enabled?) when is_atom(service) and is_boolean(enabled?) do
    Settings.find_or_create_entry!(%{key: key(service), value: %{"enabled" => enabled?}})
  end

  @doc """
  Whether `service` runs in this instance: false when the instance runs
  no background services, else the persisted flag, else `default`.
  """
  @spec enabled?(service(), boolean()) :: boolean()
  def enabled?(service, default) when is_atom(service) and is_boolean(default) do
    Config.get(:background_services) and persisted_flag(service, default)
  end

  defp persisted_flag(service, default) do
    case Settings.get_by_key(key(service)) do
      %{value: %{"enabled" => enabled?}} when is_boolean(enabled?) -> enabled?
      _ -> default
    end
  end

  defp environment, do: Application.get_env(:media_centaur, :environment, :dev)
end
