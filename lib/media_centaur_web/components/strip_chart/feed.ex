defmodule MediaCentaurWeb.Components.StripChart.Feed do
  @moduledoc """
  The LiveView side of a strip chart: the window in the URL, one frame
  the moment the chart becomes active, a frame every ten seconds while it
  stays active and the tab is visible, nothing otherwise.

  A tenant attaches in `mount/3`:

      socket =
        Feed.attach(socket,
          id: "traffic",
          frame: &TrafficFrame.build/1,
          active?: &(&1["subsystem"] == "http")
        )

  and renders `<.strip_chart id="traffic" window={Feed.window(assigns, "traffic")} …>`.

  `frame` receives the window and returns the frame map; `active?`
  receives the URL params (it runs in a `handle_params` hook, before the
  tenant's own callback) and says whether the chart is on screen.

  ## Frame

  Pushed as `strip_chart:frame`. Columnar, fixed length per strip,
  zero-filled; `mean_ms`/`worst_ms` are `nil` in bars without requests.

      %{
        id: "traffic", window: "1h", bucket_seconds: 60,
        schema: %{
          bars: [%{key: "failed", label: "failed", tone: "error"},
                 %{key: "went_out", label: "went out", tone: "solid"},
                 %{key: "cached", label: "from cache", tone: "muted"}],
          bars_total_label: "requests",
          line: %{key: "mean_ms", worst_key: "worst_ms", label: "mean latency", unit: "ms"}
        },
        strips: [
          %{id: "tmdb", label: "TMDB", dot: "ok",
            figures: [[%{text: "189 requests"}, %{text: "5 failed", tone: "error"}], …],
            t: [unix, …], failed: [...], went_out: [...], cached: [...],
            mean_ms: [...], worst_ms: [...]}
        ]
      }

  `schema.line` may be omitted. Bars are drawn back to front in the
  order given, each as a full-height series from the baseline, so the
  hook stacks them with two additions per bar and no cumulative
  bookkeeping here. `figures` is a list of lines, each a list of
  `%{text, tone}` segments the hook joins with " · ".

  ## Events from the hook

  `strip_chart:visibility` `%{"id", "visible"}` on `visibilitychange`;
  `strip_chart:window` `%{"id", "window"}` from the pills. Both are
  handled here and halted.

  The tick interval is `:strip_chart_tick_ms` in the application env
  (10 s; the test config shortens it).
  """
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1, push_event: 3, push_patch: 2]

  alias MediaCentaur.TimeSeries.Window

  defmodule State do
    @moduledoc false
    @enforce_keys [:id, :window, :frame, :active?]
    defstruct [:id, :window, :frame, :active?, :uri, :timer, active: false, visible?: true]
  end

  @assign :strip_chart_feeds

  @spec attach(Phoenix.LiveView.Socket.t(), keyword()) :: Phoenix.LiveView.Socket.t()
  def attach(socket, opts) do
    id = Keyword.fetch!(opts, :id)

    state = %State{
      id: id,
      window: Keyword.get(opts, :default_window, :"1h"),
      frame: Keyword.fetch!(opts, :frame),
      active?: Keyword.fetch!(opts, :active?)
    }

    socket
    |> put(state)
    |> attach_hook({:strip_chart_params, id}, :handle_params, &on_params(&1, &2, &3, id))
    |> attach_hook({:strip_chart_event, id}, :handle_event, &on_event(&1, &2, &3, id))
    |> attach_hook({:strip_chart_info, id}, :handle_info, &on_info(&1, &2, id))
  end

  @doc "The current window of the feed `id`, from assigns."
  @spec window(map(), String.t()) :: Window.t()
  def window(assigns, id), do: Map.fetch!(assigns[@assign], id).window

  @doc "Parses `window` from params, falling back to `default`."
  @spec window_from_params(map(), Window.t()) :: Window.t()
  def window_from_params(params, default) do
    case Window.parse(params["window"]) do
      {:ok, window} -> window
      :error -> default
    end
  end

  @doc "The request path of `uri` with `window` set in its query."
  @spec with_window(String.t(), Window.t()) :: String.t()
  def with_window(uri, window) do
    parsed = URI.parse(uri)

    query =
      (parsed.query || "")
      |> URI.decode_query()
      |> Map.put("window", Atom.to_string(window))
      |> URI.encode_query()

    "#{parsed.path}?#{query}"
  end

  # --- hooks ---

  defp on_params(params, uri, socket, id) do
    state = fetch(socket, id)
    active = state.active?.(params)
    window = window_from_params(params, :"1h")
    state = %{state | uri: uri, active: active, window: window}
    {:cont, socket |> put(state) |> resync(id)}
  end

  defp on_event("strip_chart:window", %{"id" => id, "window" => label}, socket, id) do
    state = fetch(socket, id)

    case Window.parse(label) do
      {:ok, window} -> {:halt, push_patch(socket, to: with_window(state.uri, window))}
      :error -> {:halt, socket}
    end
  end

  defp on_event("strip_chart:visibility", %{"id" => id, "visible" => visible}, socket, id) do
    state = %{fetch(socket, id) | visible?: visible == true}
    {:halt, socket |> put(state) |> resync(id)}
  end

  defp on_event(_event, _params, socket, _id), do: {:cont, socket}

  defp on_info({:strip_chart_tick, id}, socket, id) do
    socket = put(socket, %{fetch(socket, id) | timer: nil})
    {:halt, resync(socket, id)}
  end

  defp on_info(_message, socket, _id), do: {:cont, socket}

  # Push a frame and (re)arm when the chart is active, visible and connected;
  # otherwise make sure no timer is pending.
  defp resync(socket, id) do
    state = fetch(socket, id)
    socket = cancel(socket, state)

    if state.active and state.visible? and connected?(socket) do
      frame = state.window |> state.frame.() |> Map.put(:id, id)
      timer = Process.send_after(self(), {:strip_chart_tick, id}, tick_ms())

      socket
      |> push_event("strip_chart:frame", frame)
      |> put(%{fetch(socket, id) | timer: timer})
    else
      socket
    end
  end

  defp cancel(socket, %State{timer: nil}), do: socket

  defp cancel(socket, %State{timer: timer} = state) do
    Process.cancel_timer(timer)
    put(socket, %{state | timer: nil})
  end

  defp tick_ms, do: Application.get_env(:media_centaur, :strip_chart_tick_ms, 10_000)

  defp fetch(socket, id), do: Map.fetch!(socket.assigns[@assign] || %{}, id)

  defp put(socket, %State{id: id} = state) do
    feeds = Map.put(socket.assigns[@assign] || %{}, id, state)
    assign(socket, @assign, feeds)
  end
end
