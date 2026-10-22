defmodule MediaCentaurWeb.PairingController do
  @moduledoc """
  The pairing page: the one page an unpaired device on the LAN sees
  (`Plugs.RemoteAccess` sends it here and lets `/pair` through). `GET`
  renders the form — a name for the device and the code Settings →
  Players shows; `POST` offers both to `Players.pair/2`. A match writes
  the new player's id into the signed session as `"player_id"`, beside
  ADR-078's `"profile_id"`, and sends the device home, where the gate now
  admits it. A miss or a bad name re-renders the form with the reason.

  The host has nothing to pair — the gate admits it by address — so a
  loopback `GET` goes home.
  """

  use MediaCentaurWeb, :controller

  alias MediaCentaur.Players
  alias MediaCentaur.Settings.Config.BindAddress

  def show(conn, _params) do
    if BindAddress.loopback?(conn.remote_ip),
      do: redirect(conn, to: ~p"/"),
      else: render_form(conn, "", nil)
  end

  def create(conn, %{"pairing" => %{"name" => name, "code" => code}}) do
    case Players.pair(String.trim(code), name) do
      {:ok, player} ->
        conn
        |> put_session("player_id", player.id)
        |> redirect(to: ~p"/")

      {:error, reason} ->
        render_form(conn, name, reason)
    end
  end

  def create(conn, _params), do: render_form(conn, "", :invalid_code)

  defp render_form(conn, name, reason) do
    conn
    |> assign(:page_title, "Pair this device")
    |> render(:pair, name: name, reason: reason)
  end
end
