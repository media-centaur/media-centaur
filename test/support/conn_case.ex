defmodule MediaCentarrWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use MediaCentarrWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint MediaCentarrWeb.Endpoint

      use MediaCentarrWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import MediaCentarrWeb.ConnCase
    end
  end

  setup tags do
    MediaCentarr.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc """
  Mounts a LiveView like `Phoenix.LiveViewTest.live/2`, then drains its
  `start_async` operations via `render_async/1` before returning.

  Owned-async view loads (ADR-049) run a `Task.start_link` doing a DB read.
  If a test mounts the view but never awaits, that task can still be
  in-flight when the test process exits — it then dies mid-query and emits
  a sandbox `DBConnection` error that pollutes a later test (the Category-B
  flake class). Draining at mount makes the load deterministic and keeps
  every spawned task inside the test's own lifecycle.

  Returns `{:ok, view, html}` on a successful mount (html is the
  post-drain render) and passes any other result (e.g. a `live_redirect`
  `{:error, _}`) straight through.
  """
  # Generous enough to drain a multi-read view load (e.g. SettingsLive's
  # capability probes ≈100ms) without flaking; far below any genuine hang.
  @live_async_drain_ms 2_000

  defmacro live_async!(conn, path) do
    drain_ms = @live_async_drain_ms

    quote do
      case Phoenix.LiveViewTest.live(unquote(conn), unquote(path)) do
        {:ok, view, _html} ->
          {:ok, view, Phoenix.LiveViewTest.render_async(view, unquote(drain_ms))}

        other ->
          other
      end
    end
  end
end
