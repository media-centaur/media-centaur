defmodule MediaCentaurWeb.Live.RecommendFlow do
  @moduledoc """
  The Recommend modal's state, shared by every host that renders it —
  the library detail hosts through `EntityModal`'s injected handlers, and
  the Discovery page for watchlist rows.

  Assigns: `recommend_subject` (`Title.t()`, or nil = closed) and
  `recommend_relay_counts` (`{connected, total}` for the modal's relay
  line). The counts are read when the modal opens, not on render:
  `Connections.status/0` is a `GenServer.call`, and the render path runs
  on every diff.

  Send goes through `Recommendations.recommend/2`, which stores and
  publishes; the flash names whether a relay was connected at the time,
  because with none the recommendation is real but has gone nowhere yet.

  ## Host contract

  `use MediaCentaurWeb.Live.RecommendFlow` injects the two handlers that
  are identical in every host — `recommend_cancel` and `recommend_send`,
  the modal's own controls. What differs is only how the modal *opens*
  (an entity panel's subject, a watchlist row's title), so each host
  keeps its own opening clause and calls `open/2`. Place the `use` among
  the host's other `handle_event/3` clauses so they stay grouped.
  """

  @doc false
  defmacro __using__(_opts) do
    quote do
      def handle_event("recommend_cancel", _params, socket),
        do: {:noreply, MediaCentaurWeb.Live.RecommendFlow.close(socket)}

      def handle_event("recommend_send", %{"note" => note}, socket),
        do: {:noreply, MediaCentaurWeb.Live.RecommendFlow.send(socket, note)}
    end
  end

  import Kernel, except: [send: 2]
  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [put_flash: 3]

  alias MediaCentaur.Friends.Connections
  alias MediaCentaur.Recommendations
  alias MediaCentaur.TMDB.Title

  @type socket :: Phoenix.LiveView.Socket.t()

  @doc "Seeds the closed state. Called from the host's mount (or on_mount hook)."
  @spec init(socket()) :: socket()
  def init(socket), do: assign(socket, recommend_subject: nil, recommend_relay_counts: {0, 0})

  @doc "Opens the modal on `title`, capturing the relay counts it shows."
  @spec open(socket(), Title.t()) :: socket()
  def open(socket, %Title{} = title),
    do: assign(socket, recommend_subject: title, recommend_relay_counts: relay_counts())

  @spec close(socket()) :: socket()
  def close(socket), do: assign(socket, recommend_subject: nil)

  @doc "Sends the open subject as a recommendation. A no-op when nothing is open."
  @spec send(socket(), String.t() | nil) :: socket()
  def send(%{assigns: %{recommend_subject: %Title{} = title}} = socket, note) do
    case Recommendations.recommend(title, note) do
      {:ok, _rec} ->
        socket |> close() |> put_flash(:info, sent_message())

      {:error, _reason} ->
        socket |> close() |> put_flash(:error, "Could not send the recommendation")
    end
  end

  def send(socket, _note), do: socket

  @doc "`{connected, total}` relays — the modal's relay line."
  @spec relay_counts() :: {non_neg_integer(), non_neg_integer()}
  def relay_counts do
    status = Connections.status()
    {Enum.count(status, fn {_url, %{state: state}} -> state == :connected end), map_size(status)}
  end

  defp sent_message do
    case relay_counts() do
      {0, _total} -> "Saved — it will send when a relay connects"
      _connected -> "Recommended to your friends"
    end
  end
end
