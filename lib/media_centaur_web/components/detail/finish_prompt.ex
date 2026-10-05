defmodule MediaCentaurWeb.Components.Detail.FinishPrompt do
  @moduledoc """
  The row the title detail shows after a title was finished in mpv
  (UIDR-052), in one of two kinds (`Detail.Logic.finish_prompt/3`):

    * `:finished` — "You finished <title>", then Review, the delete and
      Done. The delete is the primary delete, or for a movie in a
      collection that movie's files only (`delete_target`).
    * `:caught_up` — a show still airing whose latest episode was
      finished: "You're caught up on <title>", then Review, the Track
      release dates switch (`TrackingControls.track_switch/1`) and Done.
      No delete: more episodes are coming.

  Review, Delete and the switch are the modal's own acts —
  `review_open`, `DeleteAllButton`'s `delete_all_prompt` and `set_rung`
  — so the host handles them as it does elsewhere on the detail; Done
  sends `finish_prompt_done`.

  Its zone, `detail_finish`, is the detail overlay's entry region while
  it is drawn, so a modal opened by a finished movie lands the cursor
  here.
  """

  use MediaCentaurWeb, :html

  alias MediaCentaurWeb.Components.Detail.DeleteAllButton
  alias MediaCentaurWeb.Components.Title.TrackingControls

  attr :name, :string, required: true, doc: "the finished title's name."

  attr :kind, :atom,
    values: [:finished, :caught_up],
    default: :finished,
    doc: "finished (the delete) or caught up on a show still airing (the Track switch)."

  attr :review?, :boolean,
    required: true,
    doc:
      "whether Review is offered — the same rule as the action row's pencil: the friend network on and a TMDB identity."

  attr :files, :list, required: true, doc: "as `DeleteAllButton`'s `files`."
  attr :files_status, :atom, values: [:loading, :loaded, :failed], default: :loaded
  attr :delete_confirm, :any, default: nil, doc: "as `DeleteAllButton`'s."
  attr :deleting, :any, default: nil, doc: "as `DeleteAllButton`'s."

  attr :delete_target, :any,
    default: :all,
    doc: "as `DeleteAllButton`'s `target`: `:all`, or `{:member, id}` for a movie in a collection."

  attr :ref, :string, default: nil, doc: "the title's `TitleRef.param/1`, for the Track switch."
  attr :rung, :atom, default: nil, doc: "the title's rung, for the Track switch."

  def finish_prompt(assigns) do
    ~H"""
    <div
      id="finish-prompt"
      class="glass-inset rounded-xl px-4 py-3 flex flex-wrap items-center gap-2"
      data-nav-zone="detail_finish"
    >
      <span :if={@kind == :finished} class="text-sm text-base-content/80 mr-auto">
        You finished <span class="font-semibold">{@name}</span>
      </span>
      <span :if={@kind == :caught_up} class="text-sm text-base-content/80 mr-auto">
        You're caught up on <span class="font-semibold">{@name}</span>
      </span>
      <.button
        :if={@review?}
        id="finish-prompt-review"
        variant="secondary"
        size="sm"
        phx-click="review_open"
        data-nav-item
        tabindex="0"
      >
        <.icon name="hero-pencil-square-mini" class="size-4" /> Review
      </.button>
      <TrackingControls.track_switch
        :if={@kind == :caught_up and @ref != nil}
        id="finish-prompt-track"
        ref={@ref}
        rung={@rung}
        media_type={:tv_series}
      />
      <DeleteAllButton.delete_all_button
        :if={@kind == :finished}
        target={@delete_target}
        files={@files}
        files_status={@files_status}
        delete_confirm={@delete_confirm}
        deleting={@deleting}
      />
      <.button
        id="finish-prompt-done"
        variant="dismiss"
        size="sm"
        phx-click="finish_prompt_done"
        data-nav-item
        tabindex="0"
      >
        Done
      </.button>
    </div>
    """
  end
end
