defmodule MediaCentaurWeb.ReviewBadge do
  @moduledoc """
  Discovery badge for the sidebar Review entry: how much human review work
  is waiting, split across the two review dimensions — identity ("which
  show?", `Review.count_pending/0`) and episode mapping ("which episode?",
  `Reconciliation.count_awaiting/0`). The entry only renders when either
  count is non-zero, so the counts double as the visibility switch.

  Provides an `on_mount` hook that assigns `:review_pending` and
  `:mapping_pending` app-wide and live-refreshes them on the
  `review:updates` / `reconciliation:updates` PubSub broadcasts.

  The hook owns the session-wide subscription to both topics. `ReviewLive`
  and `ReconcileLive` deliberately do NOT subscribe themselves — a second
  `subscribe` from the same process would double-deliver every message.
  Their `handle_info` clauses still fire because this hook always returns
  `{:cont, socket}`.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1]

  alias MediaCentaur.Reconciliation
  alias MediaCentaur.Review
  alias MediaCentaur.Topics

  def on_mount(:default, _params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, Topics.review_updates())
      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, Topics.reconciliation_updates())
    end

    socket =
      socket
      |> assign_counts()
      |> attach_hook(:review_badge, :handle_info, &refresh/2)

    {:cont, socket}
  end

  defp assign_counts(socket) do
    socket
    |> assign(:review_pending, Review.count_pending())
    |> assign(:mapping_pending, Reconciliation.count_awaiting())
  end

  defp refresh({:file_added, _id}, socket), do: {:cont, assign_counts(socket)}
  defp refresh({:file_reviewed, _id}, socket), do: {:cont, assign_counts(socket)}
  defp refresh({:group_approved, _key, _count}, socket), do: {:cont, assign_counts(socket)}
  defp refresh({:reconciliation_updated}, socket), do: {:cont, assign_counts(socket)}
  defp refresh(_msg, socket), do: {:cont, socket}
end
