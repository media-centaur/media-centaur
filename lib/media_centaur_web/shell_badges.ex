defmodule MediaCentaurWeb.ShellBadges do
  @moduledoc """
  The sidebar's "pending shell work" badges — one concept, four counts:

    * `:diagnostics_unseen` — unseen auto-detected incidents
      (`MediaCentaurWeb.DiagnosticsBadge.count/0`, which owns the
      `diagnostics_seen_at` marker).
    * `:review_pending` — files awaiting identity review
      (`Review.count_pending/0`).
    * `:mapping_pending` — files awaiting an episode-mapping decision
      (`Reconciliation.count_awaiting/0`).
    * `:status_errors` — live error/critical buckets, i.e. exactly the
      condition that turns a Status-page tile red
      (`HealthBoard.tile_state/1` over `ErrorReports.list_buckets/0`).
      Drives the persistent red dot on the Status nav icon. Distinct from
      `:diagnostics_unseen`: that is a *discovery* badge (new since last
      visit, cleared by `mark_seen`), this is a *current-condition* dot
      that stays until the underlying errors are resolved or dismissed.

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
  computation, so hook-mounted pages see fresh-DB semantics. A test that
  exercises `refresh_cache/0` leaves a `:persistent_term` snapshot behind;
  `GlobalStateSandbox` erases it before the next sync test.
  """
  @behaviour MediaCentaur.Cache

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1]

  alias MediaCentaur.ErrorReports
  alias MediaCentaur.Reconciliation
  alias MediaCentaur.Review
  alias MediaCentaur.Review.Events.FileAdded
  alias MediaCentaur.Review.Events.FileReviewed
  alias MediaCentaur.Review.Events.GroupApproved
  alias MediaCentaur.Topics
  alias MediaCentaurWeb.DiagnosticsBadge
  alias MediaCentaurWeb.StatusLive.HealthBoard

  @counts_key {__MODULE__, :counts}

  ## MediaCentaur.Cache callbacks (Worker registered in application.ex)

  @impl MediaCentaur.Cache
  def subscribe do
    Topics.subscribe(Topics.review_updates())
    Topics.subscribe(Topics.reconciliation_updates())
    Topics.subscribe(Topics.error_reports())
    Topics.subscribe(Topics.settings_updates())
    :ok
  end

  @impl MediaCentaur.Cache
  def relevant?({:file_added, %FileAdded{}}), do: true
  def relevant?({:file_reviewed, %FileReviewed{}}), do: true
  def relevant?({:group_approved, %GroupApproved{}}), do: true
  def relevant?({:reconciliation_updated}), do: true
  def relevant?({:buckets_changed, _buckets}), do: true
  # `mark_seen/0` advances the seen-marker via a Settings write.
  def relevant?({:setting_changed, "diagnostics_seen_at", _value}), do: true
  def relevant?(_message), do: false

  @impl MediaCentaur.Cache
  def refresh_cache do
    :persistent_term.put(@counts_key, compute_counts())

    Topics.publish(
      Topics.shell_badges(),
      {:shell_badges_updated}
    )

    :ok
  end

  @doc """
  The four badge counts. Reads the cached snapshot; falls back to the
  live computation when no Worker has primed it (test mode / boot).
  """
  @spec counts() :: %{
          diagnostics_unseen: non_neg_integer(),
          review_pending: non_neg_integer(),
          mapping_pending: non_neg_integer(),
          status_errors: non_neg_integer()
        }
  def counts do
    case :persistent_term.get(@counts_key, :unset) do
      :unset -> compute_counts()
      counts -> counts
    end
  end

  @doc false
  # Test-only: clears the cached snapshot so later tests see live counts.
  defp compute_counts do
    %{
      diagnostics_unseen: DiagnosticsBadge.count(),
      review_pending: Review.count_pending(),
      mapping_pending: Reconciliation.count_awaiting(),
      # HealthBoard.tile_state/1 is the canonical "tile turns red" rule —
      # reused here so the nav dot lights iff a Status-page tile is red.
      status_errors: HealthBoard.tile_state(ErrorReports.list_buckets()).error_count
    }
  end

  ## on_mount hook (router live_session :default)

  def on_mount(:default, _params, _session, socket) do
    if connected?(socket) do
      Topics.subscribe(Topics.review_updates())
      Topics.subscribe(Topics.reconciliation_updates())
      Topics.subscribe(Topics.shell_badges())
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
    |> assign(:status_errors, counts.status_errors)
  end

  # Source events re-read immediately (test mode computes live; in prod
  # the cached value may trail until the Worker's derived broadcast
  # below lands and corrects it).
  defp refresh({:file_added, %FileAdded{}}, socket), do: {:cont, assign_counts(socket)}
  defp refresh({:file_reviewed, %FileReviewed{}}, socket), do: {:cont, assign_counts(socket)}
  defp refresh({:group_approved, %GroupApproved{}}, socket), do: {:cont, assign_counts(socket)}
  defp refresh({:reconciliation_updated}, socket), do: {:cont, assign_counts(socket)}
  defp refresh({:shell_badges_updated}, socket), do: {:cont, assign_counts(socket)}
  defp refresh(_msg, socket), do: {:cont, socket}
end
