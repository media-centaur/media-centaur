defmodule MediaCentaurWeb.DiscoveryLive.RecommendModal do
  @moduledoc """
  The Recommend modal: the title being recommended, an optional note, the
  relay state, Send and Cancel. Persistent — a stray backdrop click must
  not discard a half-written note — so Cancel is the only way out.

  Pure rendering over `MediaCentaurWeb.Live.RecommendFlow`'s assigns;
  `recommend_send` (form submit) and `recommend_cancel` bubble to the
  host, which is `DiscoveryLive` for watchlist rows and any `EntityModal`
  host for the library detail page.
  """
  use MediaCentaurWeb, :html

  import MediaCentaurWeb.Components.Modal, only: [modal: 1]
  import MediaCentaurWeb.Components.TMDB.TitleSummary, only: [title_summary: 1]
  import MediaCentaurWeb.LiveHelpers, only: [title_poster_url: 1]

  alias MediaCentaur.TMDB.Title

  attr :subject, Title, default: nil, doc: "the title being recommended; nil = closed"

  attr :relay_counts, :any,
    required: true,
    doc: "`{connected, total}` from `RecommendFlow.relay_counts/0`, captured when the modal opened"

  def recommend_modal(assigns) do
    ~H"""
    <.modal
      id="recommend-modal"
      open={!is_nil(@subject)}
      dismiss={:persistent}
      size={:sm}
      panel_class="p-6"
      style="z-index: 60;"
    >
      <div :if={@subject} class="space-y-4">
        <h2 class="text-sm font-semibold">Recommend to your friends</h2>
        <.title_summary title={@subject} poster_url={title_poster_url(@subject)} />
        <form id="recommend-form" phx-submit="recommend_send" class="space-y-3">
          <textarea
            name="note"
            rows="3"
            placeholder="Why they should watch it (optional)"
            class="textarea textarea-bordered w-full text-sm"
          ></textarea>
          <p class="text-xs text-base-content/50">{relay_line(@relay_counts)}</p>
          <div class="flex justify-end gap-2">
            <.button
              id="recommend-cancel"
              type="button"
              variant="dismiss"
              size="sm"
              phx-click="recommend_cancel"
            >
              Cancel
            </.button>
            <.button id="recommend-send" type="submit" variant="neutral" size="sm">Send</.button>
          </div>
        </form>
      </div>
    </.modal>
    """
  end

  defp relay_line({_connected, 0}), do: "No relay configured — it will send when you add one"
  defp relay_line({connected, total}), do: "Connected to #{connected} of #{total} relays"
end
