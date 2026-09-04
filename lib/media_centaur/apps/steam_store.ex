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

  Requests go through `MediaCentaur.HttpClient` with the response cache
  attached: Steam's answer for an app is the same for everyone, so a
  repeat lookup within its `max-age` costs nothing.
  """

  alias MediaCentaur.HttpClient

  @appdetails "https://store.steampowered.com/api/appdetails"

  @spec current_banner_url(integer()) :: String.t() | nil
  def current_banner_url(app_id) do
    client = HttpClient.new(__MODULE__, upstream: :steam, cache: true, retry: false)

    with {:ok, %{status: 200, body: body}} <-
           Req.get(client, url: @appdetails, params: [appids: app_id, filters: "basic"]),
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
end
