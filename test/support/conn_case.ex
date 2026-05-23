defmodule MediaCentaurWeb.ConnCase do
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
  by setting `use MediaCentaurWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint MediaCentaurWeb.Endpoint

      use MediaCentaurWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import MediaCentaurWeb.ConnCase
    end
  end

  setup tags do
    MediaCentaur.DataCase.setup_sandbox(tags)
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

  @doc """
  Polls `render(view)` until the rendered HTML matches `matcher`, or `timeout`
  ms elapses (then `flunk/1`). Returns the matching HTML.

  `matcher` is either a substring or a 1-arity predicate over the HTML. This is
  the deterministic replacement for a fixed `Process.sleep` before asserting on
  async-derived render output (ADR-049, sleep hygiene): a fixed sleep guesses
  the settle time and either flakes (too short) or wastes wall-clock (too
  long); this waits exactly as long as the content needs and fails loudly if it
  never appears.

  Use it when the asserted content is *produced* by async work — a debounced
  reload, a `start_async` result, a PubSub-driven re-render. Do **not** use it
  to prove a *negative* (that something never renders): a poll that succeeds on
  the first tick proves nothing, so keep a bounded `Process.sleep` + `refute`
  for absence checks.
  """
  @render_until_poll_ms 10
  def render_until(view, matcher, timeout \\ 1_000)

  def render_until(view, substring, timeout) when is_binary(substring) do
    render_until(view, &String.contains?(&1, substring), timeout)
  end

  def render_until(view, predicate, timeout) when is_function(predicate, 1) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_render_until(view, predicate, deadline)
  end

  defp do_render_until(view, predicate, deadline) do
    html = Phoenix.LiveViewTest.render(view)

    cond do
      predicate.(html) ->
        html

      System.monotonic_time(:millisecond) >= deadline ->
        ExUnit.Assertions.flunk("render_until/3 timed out before the rendered HTML matched")

      true ->
        Process.sleep(@render_until_poll_ms)
        do_render_until(view, predicate, deadline)
    end
  end
end
