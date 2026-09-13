defmodule MediaCentaurWeb.SettingsLive.ConnectionState do
  @moduledoc """
  What a connection row shows for one integration (UIDR-041 §1, §7):
  the owner's `%IntegrationHealth.Status{}` projected with the config
  map's address and credential presence, and a pending detection when
  Detect from Prowlarr found values that are not saved. Pure; the row
  component draws it, `SettingsLive` builds it.

  `state` is the row's vocabulary: `:not_configured` when the
  integration lacks its settings, `:not_tested` when it has them and no
  result (`:unknown` at the owner), `:pending` while a verify is in
  flight, `:ok` / `:error` for a result, and `:detected` while a
  detection waits for review. The state word per integration lives here
  so no template spells it.
  """

  alias MediaCentaur.IntegrationHealth.Status

  @type state :: :not_configured | :not_tested | :pending | :ok | :error | :detected

  @type t :: %__MODULE__{
          id: Status.id(),
          state: state(),
          state_label: String.t(),
          tested_at: DateTime.t() | nil,
          address: String.t() | nil,
          credential: String.t() | nil,
          prefill: map()
        }

  @enforce_keys [:id, :state, :state_label]
  defstruct [:id, :state, :state_label, :tested_at, :address, :credential, prefill: %{}]

  @doc """
  The row for `status`, reading the address and credential presence from
  the Settings page's config map. A `detected` map (type, url, username)
  overrides the state and prefills the edit form.
  """
  @spec build(Status.t(), map(), map() | nil) :: t()
  def build(%Status{id: id} = status, config, nil) do
    state = state(status)

    %__MODULE__{
      id: id,
      state: state,
      state_label: label(id, state),
      tested_at: if(state in [:ok, :error], do: status.last_tested_at),
      address: address(id, config),
      credential: credential(id, config)
    }
  end

  def build(%Status{id: id}, _config, detected) when is_map(detected) do
    %__MODULE__{
      id: id,
      state: :detected,
      state_label: "Detected from Prowlarr, not saved",
      address: detected[:url],
      prefill: detected
    }
  end

  defp state(%Status{configured?: false}), do: :not_configured
  defp state(%Status{test_state: :unknown}), do: :not_tested
  defp state(%Status{test_state: state}), do: state

  defp label(_id, :not_configured), do: "Not configured"
  defp label(_id, :not_tested), do: "Not tested"
  defp label(_id, :pending), do: "Testing…"
  defp label(_id, :ok), do: "Connected"
  defp label(:download_client, :error), do: "Unreachable or auth failed"
  defp label(:usenet_download_client, :error), do: "Unreachable or bad API key"
  defp label(_id, :error), do: "Unreachable"

  defp address(:tmdb, _config), do: nil
  defp address(:prowlarr, config), do: config[:prowlarr_url]
  defp address(:download_client, config), do: config[:download_client_url]
  defp address(:usenet_download_client, config), do: config[:usenet_download_client_url]

  defp credential(:tmdb, config), do: if(config[:tmdb_api_key_configured?], do: "API key set")

  defp credential(:prowlarr, config), do: if(config[:prowlarr_api_key_configured?], do: "API key set")

  defp credential(:usenet_download_client, config),
    do: if(config[:usenet_download_client_api_key_configured?], do: "API key set")

  defp credential(:download_client, config) do
    [
      present(config[:download_client_username]),
      if(config[:download_client_password_configured?], do: "password set")
    ]
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> nil
      parts -> Enum.join(parts, " · ")
    end
  end

  defp present(""), do: nil
  defp present(value), do: value
end
