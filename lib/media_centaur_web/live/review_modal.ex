defmodule MediaCentaurWeb.Live.ReviewModal do
  @moduledoc """
  The Review modal: what the reader is saying about one title. The
  title strip (poster, name, type and year — "· you reviewed it 3w ago"
  when editing), the headline sentence "You ___ this" whose blank fills
  with the pressed sentiment's glyph and verb (`SocialWords.own_verb/1`,
  so the modal and the Feed agree), the sentiments as the house
  segmented control with their glyphs, the words rendered from the held
  text (`ReviewFlow.State.text`, through `review_change`) with the
  counter once 100 remain, and the footer: Remove review at the left
  when editing, Cancel and Share — Save when editing — at the right. Nothing is required: Share with nothing chosen and nothing
  written says only that you reviewed the title.

  Persistent — a stray backdrop click must not discard half-written
  text — so Cancel is the only way out. A pointer user who clicked
  Review lands in the text box; keyboard and gamepad keep focus with the
  input system, which reaches the box as a nav item and types in it in
  its editing mode.

  The verdict element carries the sentiment in its id, so a change
  replaces it and its pop keyframe runs once; typing patches around it.

  Remove review takes the arm gesture (`ArmGesture`, the host's
  `armed_gesture`): the first press arms it, the second withdraws.

  For keyboard and gamepad the modal is the `review` overlay (config.js):
  three regions stacked — the sentiments (`review_choice`, LEFT and RIGHT
  along them), the words (`review_text`), the footer (`review_footer`,
  LEFT and RIGHT along its buttons). No region declares a `back` edge, so
  BACK is Cancel from anywhere.

  Pure rendering over `ReviewFlow.State`; its events bubble to the
  `TitleDetailHost` host.
  """
  use MediaCentaurWeb, :html

  import MediaCentaurWeb.Components.Modal, only: [modal: 1]
  import MediaCentaurWeb.Components.TMDB.TitleSummary, only: [title_summary: 1]

  alias MediaCentaur.Activities.Activity
  alias MediaCentaur.Format
  alias MediaCentaurWeb.Components.Title.Flag
  alias MediaCentaurWeb.Components.Title.SocialWords
  alias MediaCentaurWeb.Live.ArmGesture
  alias MediaCentaurWeb.Live.ReviewFlow
  alias MediaCentaurWeb.Live.ReviewFlow.State

  attr :state, State, required: true, doc: "`ReviewFlow`'s `:review` assign; a nil subject is closed"
  attr :armed_gesture, :any, required: true, doc: "the host's `ArmGesture` slot, for Remove review"

  def review_modal(assigns) do
    assigns = assign(assigns, :editing?, State.editing?(assigns.state))

    ~H"""
    <%!-- Nested in the detail's overlay: BACK pushes `review_cancel` and the
          cursor returns to the detail beneath instead of the page behind it
          (the input system's `data-detail-nested` contract). --%>
    <.modal
      id="review-modal"
      open={!is_nil(@state.subject)}
      dismiss={:persistent}
      on_close="review_cancel"
      size={:sm}
      panel_class="p-6"
      raised
      data-detail-nested="true"
      data-nav-overlay={@state.subject && "review"}
    >
      <div :if={@state.subject} class="space-y-4">
        <%!-- The identity block without the overview: it is on the detail
              behind the modal. When editing, the age of the review rides the
              identity line as a marker. --%>
        <div data-component="review-strip">
          <.title_summary title={@state.subject} poster_url={@state.poster_url} overview={false}>
            <:markers :if={@editing?}>
              <span class="shrink-0 text-xs text-base-content/55">
                · you reviewed it {Format.relative_ago(@state.existing.acted_at)}
              </span>
            </:markers>
          </.title_summary>
        </div>
        <.headline sentiment={@state.sentiment} />
        <form id="review-form" phx-change="review_change" phx-submit="review_send" class="space-y-3">
          <%!-- Pressing the pressed choice again clears it: the flow's
                rule (`ReviewFlow`), not the control's. --%>
          <div data-nav-zone="review_choice">
            <.segmented_control
              id="review-sentiment"
              label="Sentiment"
              options={
                Enum.map(Activity.sentiments(), &{&1, sentiment_word(&1), Flag.glyph(&1, :outline)})
              }
              selected={@state.sentiment}
              event="review_sentiment"
            />
          </div>
          <%!-- Rendered from the held text so any re-render carries the
                words. Opening the modal is itself the act of writing, so
                the cursor starts in the box for a pointer user
                (`MouseAutofocus`); for keyboard and gamepad the box is a
                nav item the input system edits (ADR-053). --%>
          <div data-nav-zone="review_text">
            <textarea
              id="review-text"
              name="text"
              rows="4"
              maxlength={ReviewFlow.limit()}
              placeholder="…and in your words, if you want"
              class="textarea textarea-bordered w-full text-sm"
              phx-debounce="150"
              phx-hook="MouseAutofocus"
              data-nav-item
              tabindex="0"
            >{@state.text}</textarea>
          </div>
          <p id="review-counter" class="h-3.5 text-right text-[11px] text-base-content/55">
            {ReviewFlow.counter(@state.text)}
          </p>
          <div class="flex items-center gap-2" data-nav-zone="review_footer">
            <.armed_button
              :if={@editing?}
              id="review-remove"
              type="button"
              armed={ArmGesture.armed?(@armed_gesture, "review_remove")}
              event="review_remove"
              armed_label="Press again to remove"
              variant="dismiss"
              class="text-base-content/55 hover:text-error"
            >
              Remove review
            </.armed_button>
            <span class="flex-1"></span>
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
              variant="primary"
              size="sm"
              data-nav-item
              tabindex="0"
            >
              {if @editing?, do: "Save", else: "Share"}
            </.button>
          </div>
        </form>
      </div>
    </.modal>
    """
  end

  attr :sentiment, :atom, required: true

  # "You ___ this": the blank until a sentiment is pressed, then its
  # glyph and the reader's verb.
  defp headline(assigns) do
    ~H"""
    <p id="review-headline" class="review-headline">
      You
      <span :if={is_nil(@sentiment)} id="review-blank" class="review-blank" aria-hidden="true"></span>
      <span :if={@sentiment} id={"review-verdict-#{@sentiment}"} class="review-verdict">
        <.icon name={Flag.glyph(@sentiment, :solid)} class="review-verdict-glyph" />
        {SocialWords.own_verb(@sentiment)}
      </span>
      this
    </p>
    """
  end

  defp sentiment_word(:dislike), do: "Dislike"
  defp sentiment_word(:like), do: "Like"
  defp sentiment_word(:love), do: "Love"
end
