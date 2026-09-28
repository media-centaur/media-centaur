defmodule MediaCentaurWeb.Live.ReviewModal do
  @moduledoc """
  The Review modal: the title being reviewed, the sentiment as the
  house segmented control — Dislike, Like, Love, none pressed at open,
  the pressed one pressed again to clear — the optional text, the relay state, Send and
  Cancel. Nothing is required: Send with nothing chosen and nothing
  written is a review that says only that you reviewed the title.
  Persistent — a stray backdrop click must not discard half-written
  text — so Cancel is the only way out. A pointer user who clicked
  Review lands in the text box; keyboard and gamepad keep focus with
  the input system.

  Pure rendering over `MediaCentaurWeb.Live.ReviewFlow`'s assigns;
  `review_sentiment` (a choice), `review_send` (form submit) and
  `review_cancel` bubble to the host: any `TitleDetailHost` host, for a
  title with files or without.
  """
  use MediaCentaurWeb, :html

  import MediaCentaurWeb.Components.Modal, only: [modal: 1]
  import MediaCentaurWeb.Components.TMDB.TitleSummary, only: [title_summary: 1]

  alias MediaCentaur.Activities.Activity
  alias MediaCentaur.TMDB.Title

  attr :subject, Title, default: nil, doc: "the title being reviewed; nil = closed"

  attr :poster_url, :string,
    default: nil,
    doc:
      "resolved by the host from the subject's artwork tier (`ReviewFlow`); nil shows the icon fallback"

  attr :sentiment, :atom,
    default: nil,
    values: [nil, :dislike, :like, :love],
    doc: "the choice pressed so far (`ReviewFlow`'s `review_sentiment`); nil = none"

  attr :relay_counts, :any,
    required: true,
    doc: "`{connected, total}` from `ReviewFlow.relay_counts/0`, captured when the modal opened"

  def review_modal(assigns) do
    ~H"""
    <.modal
      id="review-modal"
      open={!is_nil(@subject)}
      dismiss={:persistent}
      on_close="review_cancel"
      size={:sm}
      panel_class="p-6"
      raised
    >
      <div :if={@subject} class="space-y-4">
        <h2 class="text-sm font-semibold">Share a review</h2>
        <.title_summary title={@subject} poster_url={@poster_url} />
        <form id="review-form" phx-submit="review_send" class="space-y-3">
          <%!-- Pressing the pressed choice again clears it: the flow's
                rule (`ReviewFlow`), not the control's. --%>
          <.segmented_control
            id="review-sentiment"
            label="Sentiment"
            options={Enum.map(Activity.sentiments(), &{&1, sentiment_word(&1)})}
            selected={@sentiment}
            event="review_sentiment"
          />
          <%!-- Opening the modal is itself the act of writing, so the
                cursor starts in the box. Pointer only: for keyboard and
                gamepad the input system owns focus (ADR-053), which is
                what `MouseAutofocus` gates on. --%>
          <textarea
            id="review-text"
            name="text"
            rows="3"
            maxlength="500"
            placeholder="What did you think? (optional)"
            class="textarea textarea-bordered w-full text-sm"
            phx-hook="MouseAutofocus"
          ></textarea>
          <p class="text-xs text-base-content/55">{relay_line(@relay_counts)}</p>
          <div class="flex justify-end gap-2">
            <.button
              id="review-cancel"
              type="button"
              variant="dismiss"
              size="sm"
              phx-click="review_cancel"
              data-nav-item
              tabindex="0"
            >
              Cancel
            </.button>
            <.button
              id="review-send"
              type="submit"
              variant="neutral"
              size="sm"
              data-nav-item
              tabindex="0"
            >
              Send
            </.button>
          </div>
        </form>
      </div>
    </.modal>
    """
  end

  defp sentiment_word(:dislike), do: "Dislike"
  defp sentiment_word(:like), do: "Like"
  defp sentiment_word(:love), do: "Love"

  defp relay_line({_connected, 0}), do: "No relay configured — it will send when you add one"
  defp relay_line({connected, total}), do: "Connected to #{connected} of #{total} relays"
end
