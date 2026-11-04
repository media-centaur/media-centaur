defmodule MediaCentaurWeb.Live.ReviewFlow do
  @moduledoc """
  The Review modal's state, shared by every `TitleDetailHost` host.

  One assign, `:review`, a `ReviewFlow.State`: the `subject` (`Title.t()`,
  nil = closed), the `poster_url` the modal paints, the `sentiment`
  pressed so far, the `text` as typed (held here so a re-render — a
  sentiment press, a relay broadcast — never empties the box; the
  textarea renders from it through `review_change`), the `existing` own
  review when the modal opened on a title the reader already reviewed
  (then it is editing: prefilled, Save, Remove review), the
  `relay_counts` and the `audience` line, both read once at open:
  `Connections.status/0` is a `GenServer.call` and the render path runs
  on every diff.

  The sentiment lives here rather than in the form because the choice
  is clearable: pressing the chosen sentiment again clears it, which a
  radio group cannot do (`choose/2`).

  The poster is the host's to resolve, because only the host knows which
  artwork tier the subject lives in; the own review is the host's too
  (`Title.Logic.own_review/1` over the detail's rows).

  Send goes through `Activities.review/3`, which replaces the reader's
  row for the title; the flash says shared, updated, or saved for a
  relay to come. Text over 500 characters is rejected without closing,
  so the words are not lost. Remove goes through `Activities.delete/1`.

  ## Host contract

  `use MediaCentaurWeb.Live.ReviewFlow` injects the handlers identical
  in every host — `review_cancel`, `review_sentiment`, `review_change`,
  `review_send`, `review_remove`. The host keeps its own opening clause
  and calls `open/4`. Only `TitleDetailHost` injects this flow.
  """

  @doc false
  defmacro __using__(_opts) do
    flow = __MODULE__

    quote do
      def handle_event("review_cancel", _params, socket), do: {:noreply, unquote(flow).close(socket)}

      def handle_event("review_sentiment", %{"choice" => choice}, socket),
        do: {:noreply, unquote(flow).choose(socket, choice)}

      def handle_event("review_change", %{"text" => text}, socket),
        do: {:noreply, unquote(flow).change(socket, text)}

      def handle_event("review_send", %{"text" => text}, socket),
        do: {:noreply, unquote(flow).submit(socket, text)}

      def handle_event("review_remove", _params, socket), do: {:noreply, unquote(flow).remove(socket)}
    end
  end

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3]

  alias MediaCentaur.Activities
  alias MediaCentaur.Activities.Activity
  alias MediaCentaur.Social
  alias MediaCentaur.Social.Connections
  alias MediaCentaur.Social.Person
  alias MediaCentaur.TMDB.Title
  alias MediaCentaurWeb.Components.Title.SocialWords

  defmodule State do
    @moduledoc "The Review modal's state — see `MediaCentaurWeb.Live.ReviewFlow`."

    alias MediaCentaur.Activities.Activity
    alias MediaCentaur.TMDB.Title

    defstruct subject: nil,
              poster_url: nil,
              sentiment: nil,
              text: "",
              existing: nil,
              relay_counts: {0, 0},
              audience: nil

    @type t :: %__MODULE__{
            subject: Title.t() | nil,
            poster_url: String.t() | nil,
            sentiment: Activity.sentiment() | nil,
            text: String.t(),
            existing: Activity.t() | nil,
            relay_counts: {non_neg_integer(), non_neg_integer()},
            audience: String.t() | nil
          }

    @doc "Whether the modal is editing a review the reader already made."
    @spec editing?(t()) :: boolean()
    def editing?(%__MODULE__{existing: existing}), do: existing != nil
  end

  @type socket :: Phoenix.LiveView.Socket.t()

  @limit 500
  @counter_from 100

  @doc "Seeds the closed state. Called from the host's mount."
  @spec init(socket()) :: socket()
  def init(socket), do: assign(socket, :review, %State{})

  @doc """
  Opens the modal on `title`, painting `poster_url` (nil = icon fallback).
  `existing` is the reader's own review on the title or nil: with one the
  modal opens as editing, its sentiment pressed and its words in the box.
  """
  @spec open(socket(), Title.t(), String.t() | nil, Activity.t() | nil) :: socket()
  def open(socket, %Title{} = title, poster_url, existing) do
    status = Connections.status()

    assign(socket, :review, %State{
      subject: title,
      poster_url: poster_url,
      sentiment: existing && existing.sentiment,
      text: (existing && existing.text) || "",
      existing: existing,
      relay_counts: relay_counts(status),
      audience: audience_line(Map.values(Social.visible_people()), status)
    })
  end

  @spec close(socket()) :: socket()
  def close(socket), do: assign(socket, :review, %State{})

  @doc """
  Presses a sentiment choice (`"dislike"`, `"like"` or `"love"`): the
  chosen one is set, and pressing the one already chosen clears it. An
  unknown word clears it too.
  """
  @spec choose(socket(), String.t()) :: socket()
  def choose(%{assigns: %{review: %State{sentiment: current} = state}} = socket, choice) do
    chosen = parse_sentiment(choice)
    assign(socket, :review, %{state | sentiment: if(chosen != current, do: chosen)})
  end

  @doc "Holds the text as typed, so the next render carries it."
  @spec change(socket(), String.t()) :: socket()
  def change(%{assigns: %{review: %State{} = state}} = socket, text) when is_binary(text),
    do: assign(socket, :review, %{state | text: text})

  @doc """
  Sends the open subject as a review with the chosen sentiment and the
  form's `text`. A no-op when nothing is open. Text over 500 characters
  flashes and leaves the modal open, so the text is not lost.
  """
  @spec submit(socket(), String.t() | nil) :: socket()
  def submit(%{assigns: %{review: %State{subject: %Title{} = title} = state}} = socket, text) do
    case Activities.review(title, state.sentiment, text) do
      {:ok, _review} ->
        message = sent_message(State.editing?(state), relay_counts(Connections.status()))
        socket |> close() |> put_flash(:info, message)

      {:error, :text_too_long} ->
        put_flash(socket, :error, "Keep the review under #{@limit} characters")

      {:error, _reason} ->
        socket |> close() |> put_flash(:error, "Could not send the review")
    end
  end

  def submit(socket, _text), do: socket

  @doc "Withdraws the review being edited (`Activities.delete/1`) and closes. A no-op when not editing."
  @spec remove(socket()) :: socket()
  def remove(%{assigns: %{review: %State{existing: %Activity{id: id}}}} = socket) do
    case Activities.delete(id) do
      {:ok, _activity} -> socket |> close() |> put_flash(:info, "Review removed")
      {:error, _reason} -> socket |> close() |> put_flash(:error, "Could not remove the review")
    end
  end

  def remove(socket), do: socket

  @doc """
  The footer's audience line: who will see the review when a relay is
  connected (the people minus the reader, `SocialWords.audience/1`; nil
  when no one is followed), else why no one will yet.
  """
  @spec audience_line([Person.t()], %{optional(String.t()) => map()}) :: String.t() | nil
  def audience_line(_people, status) when map_size(status) == 0,
    do: "Add a relay in Settings to share it"

  def audience_line(people, status) do
    if Enum.any?(status, fn {_url, entry} -> Connections.connected?(entry) end) do
      case Enum.reject(people, & &1.own?) do
        [] -> nil
        friends -> SocialWords.audience(friends)
      end
    else
      "Friends see it once a relay connects"
    end
  end

  @doc ~s(The counter under the box: "N left" once 100 or fewer remain, else nil.)
  @spec counter(String.t()) :: String.t() | nil
  def counter(text) when is_binary(text) do
    left = @limit - String.length(text)
    if left <= @counter_from, do: "#{left} left"
  end

  @doc "The flash after a send: shared, updated, or saved until a relay connects."
  @spec sent_message(boolean(), {non_neg_integer(), non_neg_integer()}) :: String.t()
  def sent_message(_editing?, {0, _total}), do: "Saved — it shares when a relay connects"
  def sent_message(true, _counts), do: "Review updated"
  def sent_message(false, _counts), do: "Review shared with your friends"

  @spec parse_sentiment(String.t()) :: Activity.sentiment() | nil
  defp parse_sentiment("dislike"), do: :dislike
  defp parse_sentiment("like"), do: :like
  defp parse_sentiment("love"), do: :love
  defp parse_sentiment(_junk), do: nil

  defp relay_counts(status),
    do: {Enum.count(status, fn {_url, entry} -> Connections.connected?(entry) end), map_size(status)}
end
