defmodule MediaCentaur.Settings.Services do
  @moduledoc """
  The per-environment start flags for optional services (`:start_watchers`,
  `:start_pipeline`, `:start_acquisition`).

  One Settings entry per `{env, service}` under `services:<env>:<service>`
  with the value `%{"enabled" => boolean}`. `MediaCentaur.Application` reads
  them at boot, the Settings page and `Acquisition.AutoGrabService` write
  them. The environment segment keeps a dev and a production install on the
  same machine from sharing a flag.
  """

  alias MediaCentaur.Settings

  @type service :: atom()

  @doc "The Settings key for `service` in the running environment."
  @spec key(service()) :: String.t()
  def key(service) when is_atom(service), do: "services:#{environment()}:#{service}"

  @doc "Persists the start flag for `service`."
  @spec set(service(), boolean()) :: Settings.Entry.t()
  def set(service, enabled?) when is_atom(service) and is_boolean(enabled?) do
    Settings.find_or_create_entry!(%{key: key(service), value: %{"enabled" => enabled?}})
  end

  @doc "The persisted start flag for `service`, or `default` when none is stored."
  @spec enabled?(service(), boolean()) :: boolean()
  def enabled?(service, default) when is_atom(service) and is_boolean(default) do
    case Settings.get_by_key(key(service)) do
      %{value: %{"enabled" => enabled?}} when is_boolean(enabled?) -> enabled?
      _ -> default
    end
  end

  defp environment, do: Application.get_env(:media_centaur, :environment, :dev)
end
