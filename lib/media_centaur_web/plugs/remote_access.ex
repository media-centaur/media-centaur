defmodule MediaCentaurWeb.Plugs.RemoteAccess do
  @moduledoc """
  The gate on HTTP requests. Sits in the endpoint after `Plug.Session`
  and before `ImageServer` and the router, so a device that is not the
  host and not paired reaches no page and no artwork; the static bundle
  (`Plug.Static`, earlier) stays open, since the pairing page needs it.

  `MediaCentaurWeb.RemoteAccess.admit/2` judges; this plug only carries
  the verdict: admitted requests get `:player` assigned (the player id,
  `Playback.player/0`), an unpaired `GET` is sent to the pairing page, and
  any other unpaired request is refused with 403. `/pair` itself is open,
  or no device could ever pair.
  """

  @behaviour Plug

  import Plug.Conn

  alias MediaCentaurWeb.RemoteAccess

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{path_info: ["pair" | _rest]} = conn, _opts), do: conn

  def call(conn, _opts) do
    conn = fetch_session(conn)

    case RemoteAccess.admit(conn.remote_ip, get_session(conn, "player_id")) do
      {:ok, player} -> assign(conn, :player, player)
      :unpaired -> refuse(conn)
    end
  end

  # A GET is a device looking for a page, so it is sent to the one page it
  # may see; anything else is refused outright.
  defp refuse(%Plug.Conn{method: "GET"} = conn) do
    conn
    |> put_resp_header("location", "/pair")
    |> send_resp(302, "")
    |> halt()
  end

  defp refuse(conn) do
    conn
    |> send_resp(403, "This device is not paired with Media Centaur.")
    |> halt()
  end
end
