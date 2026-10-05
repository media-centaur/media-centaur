defmodule MediaCentaurWeb.Components.Detail.FinishPrompt do
  @moduledoc """
  The row the title detail shows after a movie was finished in mpv
  (UIDR-052): "You finished <title>", then Review, the primary delete
  and Done. Review and Delete are the modal's own acts — `review_open`
  and `DeleteAllButton`'s `delete_all_prompt` — so the host handles
  them as it does from the action row and the Manage panel; Done sends
  `finish_prompt_done`.

  Its zone, `detail_finish`, is the detail overlay's entry region while
  it is drawn, so a modal opened by a finished movie lands the cursor
  here.
  """

  use MediaCentaurWeb, :html

  alias MediaCentaurWeb.Components.Detail.DeleteAllButton

  attr :name, :string, required: true, doc: "the finished movie's title."

  attr :review?, :boolean,
    required: true,
    doc:
      "whether Review is offered — the same rule as the action row's pencil: the friend network on and a TMDB identity."

  attr :files, :list, required: true, doc: "as `DeleteAllButton`'s `files`."
  attr :files_status, :atom, values: [:loading, :loaded, :failed], default: :loaded
  attr :delete_confirm, :any, default: nil, doc: "as `DeleteAllButton`'s."
  attr :deleting, :any, default: nil, doc: "as `DeleteAllButton`'s."

  def finish_prompt(assigns) do
    ~H"""
    <div
      id="finish-prompt"
      class="glass-inset rounded-xl px-4 py-3 flex flex-wrap items-center gap-2"
      data-nav-zone="detail_finish"
    >
      <span class="text-sm text-base-content/80 mr-auto">
        You finished <span class="font-semibold">{@name}</span>
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
      <DeleteAllButton.delete_all_button
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
