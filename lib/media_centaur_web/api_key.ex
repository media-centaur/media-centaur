defmodule MediaCentaurWeb.ApiKey do
  @moduledoc """
  The one secret a Local API caller presents (`Plugs.LocalApi`).

  Only its SHA-256 digest is stored, in Settings: the key is shown once,
  when `generate/0` returns it, and generating again replaces it. A digest
  without a salt is enough because the key is 256 random bits, not a
  password a guess could reach.
  """

  alias MediaCentaur.Settings

  @setting "local_api_key_digest"

  @doc "Makes a new key, replacing any earlier one, and returns it. The only time it is readable."
  @spec generate() :: String.t()
  def generate do
    key = "mc_" <> Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
    Settings.find_or_create_entry!(%{key: @setting, value: %{"sha256" => digest(key)}})
    key
  end

  @doc "Whether a key has been generated."
  @spec exists?() :: boolean()
  def exists?, do: stored_digest() != nil

  @doc "Whether `candidate` is the current key. False while none exists."
  @spec valid?(String.t()) :: boolean()
  def valid?(candidate) when is_binary(candidate) do
    case stored_digest() do
      nil -> false
      stored -> Plug.Crypto.secure_compare(digest(candidate), stored)
    end
  end

  defp stored_digest do
    case Settings.get_by_key(@setting) do
      %{value: %{"sha256" => stored}} when is_binary(stored) -> stored
      _none -> nil
    end
  end

  defp digest(key), do: :sha256 |> :crypto.hash(key) |> Base.encode16(case: :lower)
end
