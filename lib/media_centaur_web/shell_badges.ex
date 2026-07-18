defmodule MediaCentaurWeb.ShellBadges do
  @moduledoc """
  The sidebar's "pending shell work" badges — one concept, three counts:

    * `:diagnostics_unseen` — unseen auto-detected incidents
      (`MediaCentaurWeb.DiagnosticsBadge.count/0`, which owns the
      `diagnostics_seen_at` marker).
    * `:review_pending` — files awaiting identity review
      (`Review.count_pending/0`).
    * `:mapping_pending` — files awaiting an episode-mapping decision
      (`Reconciliation.count_awaiting/0`).

  Replaces the former `DiagnosticsBadge`/`ReviewBadge` on_mount pair,
  which issued the three COUNT queries synchronously on **every**
  navigation (each cross-page navigate is a fresh mount). The counts are
  now a `MediaCentaur.Cache` projection in `:persistent_term`: the
  Worker recomputes on the source events below and broadcasts
  `{:shell_badges_updated}` on `shell:badges`; the on_mount hook is a
  pure read (instant-navigation campaign Phase 3).

  ## The hook's delivery contract

  The hook also owns the session-wide subscription to `review:updates` /
  `reconciliation:updates`. `ReviewLive` and `ReconcileLive` deliberately
  do NOT subscribe themselves — a second `subscribe` from the same
  process would double-deliver every message. Their `handle_info`
  clauses still fire because this hook always returns `{:cont, socket}`.

  ## Test mode

  No Worker runs under ExUnit; `counts/0` falls back to the live
  computation, so hook-mounted pages see fresh-DB semantics. Tests that
  exercise `refresh_cache/0` directly must `reset_cache/0` in `on_exit`
  — a leaked `:persistent_term` snapshot would shadow live counts for
  every later test in the VM.
  """
  @behaviour MediaCentaur.Cache

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1]

  alias MediaCentaur.Reconciliation
  alias MediaCentaur.Review
  alias MediaCentaur.Topics
  alias MediaCentaurWeb.DiagnosticsBadge

  @counts_key {__MODULE__, :counts}

  ## MediaCentaur.Cache callbacks (Worker registered in application.ex)

  @impl MediaCentaur.Cache
  def subscribe do
    Phoenix.PubSub.subscribe(MediaCentaur.PubSub, Topics.review_updates())
    Phoenix.PubSub.subscribe(MediaCentaur.PubSub, Topics.reconciliation_updates())
    Phoenix.PubSub.subscribe(MediaCentaur.PubSub, Topics.error_reports())
    Phoenix.PubSub.subscribe(MediaCentaur.PubSub, Topics.settings_updates())
    :ok
  end

  @impl MediaCentaur.Cache
  def relevant?({:file_added, _id}), do: true
  def relevant?({:file_reviewed, _id}), do: true
  def relevant?({:group_approved, _key, _count}), do: true
  def relevant?({:reconciliation_updated}), do: true
  def relevant?({:buckets_changed, _buckets}), do: true
  # `mark_seen/0` advances the seen-marker via a Settings write.
  def relevant?({:setting_changed, "diagnostics_seen_at", _value}), do: true
  def relevant?(_message), do: false

  @impl MediaCentaur.Cache
  def refresh_cache do
    :persistent_term.put(@counts_key, compute_counts())

    Phoenix.PubSub.broadcast(
      MediaCentaur.PubSub,
      Topics.shell_badges(),
      {:shell_badges_updated}
    )

    :ok
  end

  @doc """
  The three badge counts. Reads the cached snapshot; falls back to the
  live computation when no Worker has primed it (test mode / boot).
  """
  @spec counts() :: %{
          diagnostics_unseen: non_neg_integer(),
          review_pending: non_neg_integer(),
          mapping_pending: non_neg_integer()
        }
  def counts do
    case :persistent_term.get(@counts_key, :unset) do
      :unset -> compute_counts()
      counts -> counts
    end
  end

  @doc false
  # Test-only: clears the cached snapshot so later tests see live counts.
  def reset_cache do
    :persistent_term.erase(@counts_key)
    :ok
  end

  defp compute_counts do
    %{
      diagnostics_unseen: DiagnosticsBadge.count(),
      review_pending: Review.count_pending(),
      mapping_pending: Reconciliation.count_awaiting()
    }
  end

  ## on_mount hook (router live_session :default)

  def on_mount(:default, _params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, Topics.review_updates())
      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, Topics.reconciliation_updates())
      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, Topics.shell_badges())
    end

    socket =
      socket
      |> assign_counts()
      |> attach_hook(:shell_badges, :handle_info, &refresh/2)

    {:cont, socket}
  end

  defp assign_counts(socket) do
    counts = counts()

    socket
    |> assign(:diagnostics_unseen, counts.diagnostics_unseen)
    |> assign(:review_pending, counts.review_pending)
    |> assign(:mapping_pending, counts.mapping_pending)
  end

  # Source events re-read immediately (test mode computes live; in prod
  # the cached value may trail until the Worker's derived broadcast
  # below lands and corrects it).
  defp refresh({:file_added, _id}, socket), do: {:cont, assign_counts(socket)}
  defp refresh({:file_reviewed, _id}, socket), do: {:cont, assign_counts(socket)}
  defp refresh({:group_approved, _key, _count}, socket), do: {:cont, assign_counts(socket)}
  defp refresh({:reconciliation_updated}, socket), do: {:cont, assign_counts(socket)}
  defp refresh({:shell_badges_updated}, socket), do: {:cont, assign_counts(socket)}
  defp refresh(_msg, socket), do: {:cont, socket}
end
