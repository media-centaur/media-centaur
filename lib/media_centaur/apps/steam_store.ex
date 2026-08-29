defmodule MediaCentaur.Apps.SteamStore do
  @moduledoc """
  Resolves the *current* store header URL for a Steam app via the
  storefront `appdetails` API.

  Needed because every guessable artwork source goes stale for titles
  on Steam's hash-addressed asset pipeline: the flat CDN path
  (`apps/<appid>/header.jpg`) froze at the migration, and the local
  librarycache copy is only as fresh as the Steam client's last
  refresh. Only the API reports the current content-hash URL
  (observed: appid 2141910 serving three different vintages across the
  three sources). No equivalent API field exists for the library
  poster (`library_600x900.jpg`), so this module is banner-only.

  HTTP client seam mirrors `MediaCentaur.ImageFiles`: a per-process
  override (`:steam_store_http_client` in the process dict) wins over
  the Application env, so async tests stub independently; test config
  pins the no-op client so no test can reach the network.
  """

  @appdetails "https://store.steampowered.com/api/appdetails"

  @spec current_banner_url(integer()) :: String.t() | nil
  def current_banner_url(app_id) do
    with {:ok, %{status: 200, body: body}} <-
           http_client().get("#{@appdetails}?appids=#{app_id}&filters=basic"),
         {:ok, decoded} <- decode(body),
         %{"success" => true, "data" => %{"header_image" => url}} when is_binary(url) <-
           decoded[to_string(app_id)] do
      url
    else
      _miss -> nil
    end
  rescue
    _transport -> nil
  end

  # Req decodes JSON bodies by content-type; raw binaries cover stubbed
  # clients and any upstream content-type drift.
  defp decode(body) when is_map(body), do: {:ok, body}
  defp decode(body) when is_binary(body), do: JSON.decode(body)
  defp decode(_other), do: :error

  defp http_client do
    Process.get(:steam_store_http_client) ||
      Application.get_env(:media_centaur, :steam_store_http_client, Req)
  end
end
