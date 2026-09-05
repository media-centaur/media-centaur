defmodule MediaCentaurWeb.DiscoveryLive.RecommendModal do
  @moduledoc """
  The Recommend modal: the title being recommended, the sentiment as two
  pennants (like preselected, love the stronger word) — the choice is a
  preview of exactly what the friend will see — an optional note, the
  relay state, Send and Cancel. Persistent — a stray backdrop click must
  not discard a half-written note — so Cancel is the only way out.

  Pure rendering over `MediaCentaurWeb.Live.RecommendFlow`'s assigns;
  `recommend_send` (form submit) and `recommend_cancel` bubble to the
  host, which is `DiscoveryLive` for watchlist rows and any `EntityModal`
  host for the library detail page.
  """
  use MediaCentaurWeb, :html

  import MediaCentaurWeb.Components.Discovery.RecommendationPennant,
    only: [recommendation_pennants: 1]

  import MediaCentaurWeb.Components.Modal, only: [modal: 1]
  import MediaCentaurWeb.Components.TMDB.TitleSummary, only: [title_summary: 1]

  alias MediaCentaur.Activities.Activity
  alias MediaCentaur.TMDB.Title

  attr :subject, Title, default: nil, doc: "the title being recommended; nil = closed"

  attr :poster_url, :string,
    default: nil,
    doc:
      "resolved by the host from the subject's artwork tier (`RecommendFlow`); nil shows the icon fallback"

  attr :relay_counts, :any,
    required: true,
    doc: "`{connected, total}` from `RecommendFlow.relay_counts/0`, captured when the modal opened"

  def recommend_modal(assigns) do
    ~H"""
    <.modal
      id="recommend-modal"
      open={!is_nil(@subject)}
      dismiss={:persistent}
      on_close="recommend_cancel"
      size={:sm}
      panel_class="p-6"
      raised
    >
      <div :if={@subject} class="space-y-4">
        <h2 class="text-sm font-semibold">Recommend to your friends</h2>
        <.title_summary title={@subject} poster_url={@poster_url} />
        <form id="recommend-form" phx-submit="recommend_send" class="space-y-3">
          <%!-- The radio is visually hidden; the label is the nav item and
                a click on it checks the radio, which is what Select sends. --%>
          <fieldset class="flex items-center gap-3" aria-label="How much">
            <label
              :for={sentiment <- Activity.sentiments()}
              id={"recommend-sentiment-#{sentiment}"}
              class="pennant-choice"
              data-nav-item
              tabindex="0"
            >
              <input
                type="radio"
                name="sentiment"
                value={sentiment}
                checked={sentiment == :like}
                class="sr-only"
              />
              <.recommendation_pennants
                recommendations={[preview(sentiment)]}
                label={sentiment_word(sentiment)}
              />
            </label>
          </fieldset>
          <textarea
            name="note"
            rows="3"
            maxlength="500"
            placeholder="Why they should watch it (optional)"
            class="textarea textarea-bordered w-full text-sm"
          ></textarea>
          <p class="text-xs text-base-content/55">{relay_line(@relay_counts)}</p>
          <div class="flex justify-end gap-2">
            <.button
              id="recommend-cancel"
              type="button"
              variant="dismiss"
              size="sm"
              phx-click="recommend_cancel"
              data-nav-item
              tabindex="0"
            >
              Cancel
            </.button>
            <.button
              id="recommend-send"
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

  # The choice shows the pennant the friend will see, worded as the
  # choice itself rather than as the sender's name.
  defp preview(sentiment),
    do: %{activity: %Activity{kind: :recommendation, sentiment: sentiment}, nickname: nil, own?: true}

  defp sentiment_word(:like), do: "Like"
  defp sentiment_word(:love), do: "Love"

  defp relay_line({_connected, 0}), do: "No relay configured — it will send when you add one"
  defp relay_line({connected, total}), do: "Connected to #{connected} of #{total} relays"
end
