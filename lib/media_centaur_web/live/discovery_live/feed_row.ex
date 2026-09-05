defmodule MediaCentaurWeb.DiscoveryLive.FeedRow do
  @moduledoc """
  One recommendation on the Feed, sent by a friend or by this identity:
  the shared `title_summary/1` identity block, marked with who sent it
  (`You` for an own row, `from <nickname>` otherwise) and when, the
  sender's note in place of the TMDB overview, and the one action the
  title's state allows — the library detail when the library already
  owns it, a quiet "On watchlist" when it is already saved, otherwise
  Add to watchlist. An own row carries the same action as a received one
  — the title can be in the library or on the watchlist just the same —
  plus Delete, which withdraws the recommendation from every relay.

  Pure rendering; `feed_add_to_watchlist` and `feed_delete` bubble to
  `DiscoveryLive`, which owns both the decoration and the write.
  """
  use MediaCentaurWeb, :html

  import MediaCentaurWeb.Components.TMDB.TitleSummary, only: [title_summary: 1]

  alias MediaCentaur.Format

  attr :row, :map,
    required: true,
    doc:
      "a `Recommendations.list_feed/0` row (`:recommendation`, `:nickname`, `:own?`) decorated by `DiscoveryLive` with `:poster_url`, `:library_owner_id` and `:on_watchlist?`."

  def feed_row(assigns) do
    assigns = assign(assigns, :recommendation, assigns.row.recommendation)

    ~H"""
    <div
      id={"feed-#{@recommendation.id}"}
      class="glass-surface flex w-full items-start gap-4 rounded-xl px-4 py-3"
      data-component="feed-row"
    >
      <.title_summary title={@recommendation.title} poster_url={@row.poster_url}>
        <:markers>
          <span class="shrink-0 text-xs text-base-content/55">
            <%= if @row.own? do %>
              You · {Format.relative_ago(@recommendation.recommended_at)}
            <% else %>
              from {@row.nickname} · {Format.relative_ago(@recommendation.recommended_at)}
            <% end %>
          </span>
        </:markers>
        <:secondary :if={@recommendation.note}>{@recommendation.note}</:secondary>
      </.title_summary>

      <span class="flex shrink-0 items-center gap-3 self-center">
        <.action row={@row} recommendation={@recommendation} />
        <button
          :if={@row.own?}
          type="button"
          class="cursor-pointer text-xs text-base-content/55 transition-colors hover:text-base-content/60"
          phx-click="feed_delete"
          phx-value-id={@recommendation.id}
          data-nav-item
          tabindex="0"
        >
          Delete
        </button>
      </span>
    </div>
    """
  end

  attr :row, :map, required: true, doc: "the decorated feed row — see `feed_row/1`."

  attr :recommendation, :any,
    required: true,
    doc: "`Recommendations.Recommendation.t()` — the row's record, hoisted for readability."

  # The row's one action, honest per state: the library detail when the
  # title is already owned, nothing to do when it is already saved, and
  # otherwise the only move the feed offers.
  defp action(%{row: %{library_owner_id: owner_id}} = assigns) when not is_nil(owner_id) do
    ~H"""
    <.link
      navigate={"/library?selected=#{@row.library_owner_id}"}
      class="inline-flex items-center gap-1 text-xs font-medium text-primary/70 transition-colors hover:text-primary"
      data-nav-item
      tabindex="0"
    >
      In library <.icon name="hero-chevron-right-mini" class="size-3.5" />
    </.link>
    """
  end

  defp action(%{row: %{on_watchlist?: true}} = assigns) do
    ~H"""
    <span class="text-xs text-base-content/55">On watchlist</span>
    """
  end

  defp action(assigns) do
    ~H"""
    <button
      type="button"
      class="inline-flex cursor-pointer items-center gap-1 text-xs font-medium text-primary/70 transition-colors hover:text-primary"
      phx-click="feed_add_to_watchlist"
      phx-value-id={@recommendation.id}
      data-nav-item
      tabindex="0"
    >
      Add to watchlist <.icon name="hero-chevron-right-mini" class="size-3.5" />
    </button>
    """
  end
end
