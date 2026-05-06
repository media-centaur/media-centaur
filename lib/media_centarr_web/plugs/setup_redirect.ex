defmodule MediaCentarrWeb.Plugs.SetupRedirect do
  @moduledoc """
  First-run gate. While `setup_wizard_dismissed` is false, GETs to the
  redirectable paths below land on `/setup` instead of the requested
  page. The user finishes (or skips) the tour, the flag flips to true,
  and subsequent requests pass through normally.

  Plug-level rather than per-LiveView mount-check: catches the first
  HTTP GET, so there's no flash of unwanted content before the LiveView
  patches over it.

  Redirectable paths are intentionally narrow — only the entry points a
  fresh user would reach. `/setup` itself, `/settings`, `/storybook/*`
  and everything else pass through.
  """

  import Plug.Conn

  alias MediaCentarr.Config

  @redirectable_paths ["/", "/library", "/home"]

  @doc false
  def init(opts), do: opts

  @doc false
  def call(%Plug.Conn{request_path: path} = conn, _opts) do
    # `!` (not `not`) so a missing/nil key — which happens on a dev iex
    # whose :persistent_term predates the addition of this key — is
    # treated the same as an explicit `false`.
    if path in @redirectable_paths and !Config.get(:setup_wizard_dismissed) do
      conn
      |> put_resp_header("location", "/setup")
      |> send_resp(302, "")
      |> halt()
    else
      conn
    end
  end
end
