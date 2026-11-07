defmodule MediaCentaurWeb.Plugs.KeepSession do
  @moduledoc """
  Keeps the session cookie alive: on every page load that carries a
  session, the cookie is written again, so its expiry (`max_age` in the
  endpoint's session options) counts from the last visit, not from the
  last time the session changed.

  The session holds who is watching (`"profile_id"`, ADR-078) and which
  paired player a device is (`"player_id"`). Without an expiry the
  browser dropped the cookie when it closed, so every reboot opened on
  the picker; with a fixed expiry it would lapse a year after the last
  switch. Browsers cap a cookie's lifetime at 400 days, so the renewal
  is what makes the choice last.
  """

  import Plug.Conn

  @doc false
  def init(opts), do: opts

  @doc false
  def call(conn, _opts) do
    if get_session(conn) == %{} do
      conn
    else
      configure_session(conn, renew: true)
    end
  end
end
