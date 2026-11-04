defmodule MediaCentaurWeb.Live.ReviewModal do
  @moduledoc """
  The Review modal: what the reader is saying about one title. The
  title strip (poster, name, type and year — "· you reviewed it 3w ago"
  when editing), the headline sentence "You ___ this" whose blank fills
  with the pressed sentiment's glyph and verb (`SocialWords.own_verb/1`,
  so the modal and the Feed agree), the sentiments as the house
  segmented control with their glyphs, the words rendered from the held
  text (`ReviewFlow.State.text`, through `review_change`) with the
  counter once 100 remain, and the footer: the audience line or Remove
  review at the left, Cancel and Share — Save when editing — at the
  right. Nothing is required: Share with nothing chosen and nothing
  written says only that you reviewed the title.

  Persistent — a stray backdrop click must not discard half-written
  text — so Cancel is the only way out. A pointer user who clicked
  Review lands in the text box; keyboard and gamepad keep focus with the
  input system, which reaches the box as a nav item and types in it in
  its editing mode.

  The verdict element carries the sentiment in its id, so a change
  replaces it and its pop keyframe runs once; typing patches around it.

  Pure rendering over `ReviewFlow.State`; its events bubble to the
  `TitleDetailHost` host.
  """
  use MediaCentaurWeb, :html

  import MediaCentaurWeb.Components.Modal, only: [modal: 1]
  import MediaCentaurWeb.LiveHelpers, only: [sized_image_url: 2]

  alias MediaCentaur.Activities.Activity
  alias MediaCentaur.Format
  alias MediaCentaurWeb.Components.Title.Flag
  alias MediaCentaurWeb.Components.Title.SocialWords
  alias MediaCentaurWeb.Live.ReviewFlow
  alias MediaCentaurWeb.Live.ReviewFlow.State

  attr :state, State, required: true, doc: "`ReviewFlow`'s `:review` assign; a nil subject is closed"

  def review_modal(assigns) do
    assigns = assign(assigns, :editing?, State.editing?(assigns.state))

    ~H"""
    <.modal
      id="review-modal"
      open={!is_nil(@state.subject)}
      dismiss={:persistent}
      on_close="review_cancel"
      size={:sm}
      panel_class="p-6"
      raised
    >
      <div :if={@state.subject} class="space-y-4">
        <.title_strip state={@state} editing?={@editing?} />
        <.headline sentiment={@state.sentiment} />
        <form id="review-form" phx-change="review_change" phx-submit="review_send" class="space-y-3">
          <%!-- Pressing the pressed choice again clears it: the flow's
                rule (`ReviewFlow`), not the control's. --%>
          <.segmented_control
            id="review-sentiment"
            label="Sentiment"
            options={
              Enum.map(Activity.sentiments(), &{&1, sentiment_word(&1), Flag.glyph(&1, :outline)})
            }
            selected={@state.sentiment}
            event="review_sentiment"
          />
          <%!-- Rendered from the held text so any re-render carries the
                words. Opening the modal is itself the act of writing, so
                the cursor starts in the box for a pointer user
                (`MouseAutofocus`); for keyboard and gamepad the box is a
                nav item the input system edits (ADR-053). --%>
          <textarea
            id="review-text"
            name="text"
            rows="4"
            maxlength="500"
            placeholder="…and in your words, if you want"
            class="textarea textarea-bordered w-full text-sm"
            phx-debounce="150"
            phx-hook="MouseAutofocus"
            data-nav-item
            tabindex="0"
          >{@state.text}</textarea>
          <p id="review-counter" class="h-3.5 text-right text-[11px] text-base-content/55">
            {ReviewFlow.counter(@state.text)}
          </p>
          <div class="flex items-center gap-2">
            <button
              :if={@editing?}
              id="review-remove"
              type="button"
              class="cursor-pointer text-xs text-base-content/55 transition-colors hover:text-error"
              phx-click="review_remove"
              data-nav-item
              tabindex="0"
            >
              Remove review
            </button>
            <p
              :if={!@editing? && @state.audience}
              id="review-audience"
              class="text-xs text-base-content/55"
            >
              {@state.audience}
            </p>
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

  attr :state, State, required: true
  attr :editing?, :boolean, required: true

  # Poster, name, type · year, and when editing the age of the review.
  defp title_strip(assigns) do
    ~H"""
    <div class="flex items-center gap-3" data-component="review-strip">
      <span class="flex h-[72px] w-12 flex-shrink-0 items-center justify-center overflow-hidden rounded-md bg-base-content/10">
        <img
          :if={@state.poster_url}
          src={sized_image_url(@state.poster_url, 160)}
          alt=""
          class="h-full w-full object-cover"
          loading="eager"
          decoding="sync"
        />
        <.icon
          :if={!@state.poster_url}
          name={if @state.subject.media_type == :movie, do: "hero-film-mini", else: "hero-tv-mini"}
          class="size-5 text-base-content/25"
        />
      </span>
      <div class="min-w-0">
        <h2 class="truncate text-sm font-semibold">{@state.subject.name}</h2>
        <p class="text-xs text-base-content/55">
          {if @state.subject.media_type == :movie, do: "Movie", else: "TV"}<span :if={
            @state.subject.year
          }> · {@state.subject.year}</span><span
            :if={@editing?}
            id="review-reviewed-at"
          > · you reviewed it {Format.relative_ago(@state.existing.acted_at)}</span>
        </p>
      </div>
    </div>
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
