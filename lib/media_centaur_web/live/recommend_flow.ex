defmodule MediaCentaurWeb.Live.RecommendFlow do
  @moduledoc """
  The Recommend modal's state, shared by every host that renders it —
  the library detail hosts through `EntityModal`'s injected handlers, and
  the Discovery page for watchlist rows.

  Assigns: `recommend_subject` (`Title.t()`, or nil = closed),
  `recommend_poster_url` (the artwork the modal paints, or nil for the
  icon fallback) and `recommend_relay_counts` (`{connected, total}` for
  the modal's relay line). The counts are read when the modal opens, not
  on render: `Connections.status/0` is a `GenServer.call`, and the render
  path runs on every diff.

  The poster is the host's to resolve, because only the host knows which
  artwork tier the subject lives in: a library entry's poster is in the
  entity-keyed store (`LiveHelpers.image_url/2`), which the TMDB-identity
  resolver `LiveHelpers.title_poster_url/1` cannot see.

  Send goes through `Recommendations.recommend/2`, which stores and
  publishes; the flash names whether a relay was connected at the time,
  because with none the recommendation is real but has gone nowhere yet.
  A note over 500 characters is rejected without closing the modal, so
  the half-written note is not lost.

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
        do: {:noreply, MediaCentaurWeb.Live.RecommendFlow.submit(socket, note)}
    end
  end

  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [put_flash: 3]

  alias MediaCentaur.Social.Connections
  alias MediaCentaur.Recommendations
  alias MediaCentaur.TMDB.Title

  @type socket :: Phoenix.LiveView.Socket.t()

  @doc "Seeds the closed state. Called from the host's mount (or on_mount hook)."
  @spec init(socket()) :: socket()
  def init(socket),
    do: assign(socket, recommend_subject: nil, recommend_poster_url: nil, recommend_relay_counts: {0, 0})

  @doc """
  Opens the modal on `title`, painting `poster_url` (nil = icon fallback)
  and capturing the relay counts it shows.
  """
  @spec open(socket(), Title.t(), String.t() | nil) :: socket()
  def open(socket, %Title{} = title, poster_url) do
    assign(socket,
      recommend_subject: title,
      recommend_poster_url: poster_url,
      recommend_relay_counts: relay_counts()
    )
  end

  @spec close(socket()) :: socket()
  def close(socket), do: assign(socket, recommend_subject: nil, recommend_poster_url: nil)

  @doc """
  Sends the open subject as a recommendation. A no-op when nothing is
  open. A note over 500 characters flashes and leaves the modal open, so
  the note is not lost.
  """
  @spec submit(socket(), String.t() | nil) :: socket()
  def submit(%{assigns: %{recommend_subject: %Title{} = title}} = socket, note) do
    case Recommendations.recommend(title, note) do
      {:ok, _rec} ->
        socket |> close() |> put_flash(:info, sent_message())

      {:error, :note_too_long} ->
        put_flash(socket, :error, "Keep the note under 500 characters")

      {:error, _reason} ->
        socket |> close() |> put_flash(:error, "Could not send the recommendation")
    end
  end

  def submit(socket, _note), do: socket

  @doc "`{connected, total}` relays — the modal's relay line."
  @spec relay_counts() :: {non_neg_integer(), non_neg_integer()}
  def relay_counts do
    status = Connections.status()
    {Enum.count(status, fn {_url, entry} -> Connections.connected?(entry) end), map_size(status)}
  end

  defp sent_message do
    case relay_counts() do
      {0, _total} -> "Saved — it will send when a relay connects"
      _connected -> "Recommended to your friends"
    end
  end
end
