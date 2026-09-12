defmodule MediaCentaurWeb.Live.ReviewFlow do
  @moduledoc """
  The Review modal's state, shared by every host that renders it — the
  library detail hosts through `EntityModal`'s injected handlers, and
  the title detail hosts through `TitleDetailHost`.

  Assigns: `review_subject` (`Title.t()`, or nil = closed),
  `review_poster_url` (the artwork the modal paints, or nil for the
  icon fallback), `review_sentiment` (`:dislike`, `:like`, `:love`, or
  nil — the choice so far; nil at open) and `review_relay_counts`
  (`{connected, total}` for the modal's relay line). The counts are read
  when the modal opens, not on render: `Connections.status/0` is a
  `GenServer.call`, and the render path runs on every diff.

  The sentiment lives here rather than in the form because the choice
  is clearable: pressing the chosen sentiment again clears it, which a
  radio group cannot do, so each choice is a button and the flow holds
  what is pressed (`choose/2`).

  The poster is the host's to resolve, because only the host knows which
  artwork tier the subject lives in: a library entry's poster is in the
  entity-keyed store (`LiveHelpers.image_url/2`), which the TMDB-identity
  resolver `LiveHelpers.title_poster_url/1` cannot see.

  Send goes through `Activities.review/3` with the chosen sentiment and
  the form's text, neither required; it stores and publishes, and the
  flash names whether a relay was connected at the time, because with
  none the review is real but has gone nowhere yet. Text over 500
  characters is rejected without closing the modal, so the half-written
  review is not lost.

  ## Host contract

  `use MediaCentaurWeb.Live.ReviewFlow` injects the three handlers that
  are identical in every host — `review_cancel`, `review_sentiment` and
  `review_send`, the modal's own controls. What differs is only how the
  modal *opens* (an entity panel's subject, a title detail's title), so
  each host keeps its own opening clause and calls `open/3`. Place the
  `use` among the host's other `handle_event/3` clauses so they stay
  grouped.

  Two modules inject this flow: `EntityModal`, for a title with files,
  and `TitleDetailHost`, for one without. A LiveView may `use` one or
  the other, never both — the injected clauses and the `init/1` seed
  would collide.
  """

  @doc false
  defmacro __using__(_opts) do
    flow = __MODULE__

    quote do
      def handle_event("review_cancel", _params, socket), do: {:noreply, unquote(flow).close(socket)}

      def handle_event("review_sentiment", %{"choice" => choice}, socket),
        do: {:noreply, unquote(flow).choose(socket, choice)}

      def handle_event("review_send", %{"text" => text}, socket),
        do: {:noreply, unquote(flow).submit(socket, text)}
    end
  end

  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [put_flash: 3]

  alias MediaCentaur.Social.Connections
  alias MediaCentaur.Activities
  alias MediaCentaur.Activities.Activity
  alias MediaCentaur.TMDB.Title

  @type socket :: Phoenix.LiveView.Socket.t()

  @doc "Seeds the closed state. Called from the host's mount (or on_mount hook)."
  @spec init(socket()) :: socket()
  def init(socket),
    do:
      assign(socket,
        review_subject: nil,
        review_poster_url: nil,
        review_sentiment: nil,
        review_relay_counts: {0, 0}
      )

  @doc """
  Opens the modal on `title`, painting `poster_url` (nil = icon fallback),
  with no sentiment chosen, and capturing the relay counts it shows.
  """
  @spec open(socket(), Title.t(), String.t() | nil) :: socket()
  def open(socket, %Title{} = title, poster_url) do
    assign(socket,
      review_subject: title,
      review_poster_url: poster_url,
      review_sentiment: nil,
      review_relay_counts: relay_counts()
    )
  end

  @spec close(socket()) :: socket()
  def close(socket),
    do: assign(socket, review_subject: nil, review_poster_url: nil, review_sentiment: nil)

  @doc """
  Presses a sentiment choice (`"dislike"`, `"like"` or `"love"`): the
  chosen one is set, and pressing the one already chosen clears it. An
  unknown word clears it too.
  """
  @spec choose(socket(), String.t()) :: socket()
  def choose(%{assigns: %{review_sentiment: current}} = socket, choice) do
    chosen = parse_sentiment(choice)
    assign(socket, review_sentiment: if(chosen != current, do: chosen))
  end

  @doc """
  Sends the open subject as a review with the chosen sentiment and the
  form's `text`. A no-op when nothing is open. Text over 500 characters
  flashes and leaves the modal open, so the text is not lost.
  """
  @spec submit(socket(), String.t() | nil) :: socket()
  def submit(%{assigns: %{review_subject: %Title{} = title, review_sentiment: sentiment}} = socket, text) do
    case Activities.review(title, sentiment, text) do
      {:ok, _review} ->
        socket |> close() |> put_flash(:info, sent_message())

      {:error, :text_too_long} ->
        put_flash(socket, :error, "Keep the review under 500 characters")

      {:error, _reason} ->
        socket |> close() |> put_flash(:error, "Could not send the review")
    end
  end

  def submit(socket, _text), do: socket

  @spec parse_sentiment(String.t()) :: Activity.sentiment() | nil
  defp parse_sentiment("dislike"), do: :dislike
  defp parse_sentiment("like"), do: :like
  defp parse_sentiment("love"), do: :love
  defp parse_sentiment(_junk), do: nil

  @doc "`{connected, total}` relays — the modal's relay line."
  @spec relay_counts() :: {non_neg_integer(), non_neg_integer()}
  def relay_counts do
    status = Connections.status()
    {Enum.count(status, fn {_url, entry} -> Connections.connected?(entry) end), map_size(status)}
  end

  defp sent_message do
    case relay_counts() do
      {0, _total} -> "Saved — it will send when a relay connects"
      _connected -> "Review shared with your friends"
    end
  end
end
