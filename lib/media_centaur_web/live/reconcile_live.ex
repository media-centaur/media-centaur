defmodule MediaCentaurWeb.ReconcileLive do
  @moduledoc """
  The episode-mapping review surface (reconciliation campaign) — the second
  review dimension. Identity ("which show?") is settled upstream; this page
  answers "which episode?" for files whose release numbering doesn't match
  TMDB's canonical episode list (the cour / absolute-numbering case).

  Master/detail: the left list is every show with files waiting; the right
  pane renders the engine's recommended file→episode mapping (each row a
  per-file episode picker), plus the alternative interpretations as
  collapsed chips the user can adopt. Confirming links the files to their
  canonical episodes — never fabricating a phantom season.

  View logic lives in `MediaCentaurWeb.ReconcileView` ([ADR-030]); this
  module is thin wiring. `resolve_show/1` is called synchronously on
  selection — the awaiting queue is a small admin surface; if it grows,
  move the TMDB-backed spine assembly to `assign_async`.
  """
  use MediaCentaurWeb, :live_view

  alias MediaCentaur.Reconciliation
  alias MediaCentaur.Reconciliation.ShowReview
  alias MediaCentaurWeb.ReconcileView

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Reconciliation.subscribe()

    {:ok,
     socket
     |> assign(loaded?: false, selected_tmdb: nil, review: nil, targets: %{}, episode_options: [])
     |> assign(shows: [])}
  end

  @impl true
  def handle_params(_params, _uri, socket), do: {:noreply, ensure_loaded(socket)}

  defp ensure_loaded(%{assigns: %{loaded?: true}} = socket), do: socket
  defp ensure_loaded(socket), do: socket |> load() |> assign(:loaded?, true)

  defp load(socket) do
    shows = ReconcileView.show_summaries(Reconciliation.list_awaiting())
    selected = pick_selected(shows, socket.assigns.selected_tmdb)

    socket
    |> assign(shows: shows)
    |> select(selected)
  end

  # Keep the current selection if it still has pending files; else first show.
  defp pick_selected(shows, current) do
    tmdb_ids = Enum.map(shows, & &1.tmdb_id)

    cond do
      current in tmdb_ids -> current
      shows == [] -> nil
      true -> hd(shows).tmdb_id
    end
  end

  defp select(socket, nil) do
    assign(socket, selected_tmdb: nil, review: nil, targets: %{}, episode_options: [])
  end

  defp select(socket, tmdb_id) do
    review = Reconciliation.resolve_show(tmdb_id)

    socket
    |> assign(selected_tmdb: tmdb_id)
    |> assign(review: review)
    |> assign(targets: ReconcileView.initial_targets(review.resolution))
    |> assign(episode_options: ReconcileView.episode_options(review.spine))
  end

  @impl true
  def handle_event("select_show", %{"tmdb" => tmdb}, socket) do
    {:noreply, select(socket, String.to_integer(tmdb))}
  end

  def handle_event("override", %{"file" => id, "target" => value}, socket) do
    {:noreply, assign(socket, targets: Map.put(socket.assigns.targets, id, value))}
  end

  def handle_event("use_interpretation", %{"model" => model}, socket) do
    interpretation =
      Enum.find(socket.assigns.review.resolution.alternatives, &(to_string(&1.model) == model))

    targets =
      if interpretation,
        do: ReconcileView.targets_from_placements(interpretation.placements),
        else: socket.assigns.targets

    {:noreply, assign(socket, targets: targets)}
  end

  def handle_event("confirm", _params, socket) do
    review = socket.assigns.review
    targets = ReconcileView.included_targets(socket.assigns.targets)

    {:noreply, socket |> apply_confirm(review, targets) |> load()}
  end

  def handle_event("dismiss_all", _params, socket) do
    for file <- socket.assigns.review.awaiting_files, do: Reconciliation.dismiss_awaiting(file)

    {:noreply,
     socket
     |> put_flash(:info, "Dismissed #{length(socket.assigns.review.awaiting_files)} file(s).")
     |> load()}
  end

  @impl true
  def handle_info({:reconciliation_updated}, socket), do: {:noreply, load(socket)}
  def handle_info(_message, socket), do: {:noreply, socket}

  defp apply_confirm(socket, _review, targets) when map_size(targets) == 0 do
    put_flash(socket, :error, "Pick an episode for at least one file first.")
  end

  defp apply_confirm(socket, review, targets) do
    case Reconciliation.confirm(review, targets) do
      {:ok, %{linked: linked, failed: 0}} ->
        put_flash(socket, :info, "Linked #{linked} file(s) to their episodes.")

      {:ok, %{linked: linked, failed: failed}} ->
        put_flash(socket, :info, "Linked #{linked} file(s); #{failed} couldn't be linked.")

      {:error, :series_not_in_library} ->
        put_flash(socket, :error, "This show isn't in your library yet — import it first.")
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.console_mount socket={@socket} />
    <Layouts.app
      flash={@flash}
      current_path="/reconcile"
      acquisition_ready={assigns[:acquisition_ready] || false}
      diagnostics_unseen={assigns[:diagnostics_unseen] || 0}
    >
      <div
        class="flex flex-col h-full gap-4"
        data-page-behavior="reconcile"
        data-nav-default-zone="reconcile-list"
      >
        <div>
          <h1 class="text-xl font-semibold">Episode mapping</h1>
          <p class="text-sm text-base-content/50">
            Files whose release numbering doesn't line up with the episode list. Confirm where each one belongs.
          </p>
        </div>

        <div
          :if={@shows == []}
          class="glass-surface rounded-xl p-8 text-center"
          data-nav-zone="reconcile-list"
        >
          <p class="text-base-content/70">
            When a download labels its episodes in a numbering we can't place on the show's episode list
            (a separately-numbered cour, absolute numbering), the files land here instead of inventing a
            season for them. You map them to the right episodes by hand.
          </p>
        </div>

        <div :if={@shows != []} class="flex gap-4 flex-1 min-h-0">
          <div class="w-72 shrink-0 overflow-y-auto thin-scrollbar" data-nav-zone="reconcile-list">
            <button
              :for={show <- @shows}
              id={"reconcile-show-#{show.tmdb_id}"}
              type="button"
              phx-click="select_show"
              phx-value-tmdb={show.tmdb_id}
              data-nav-item
              tabindex="0"
              class={[
                "w-full text-left glass-inset rounded-lg p-3 mb-2 cursor-pointer transition-colors",
                @selected_tmdb == show.tmdb_id && "ring-1 ring-primary"
              ]}
            >
              <div class="font-medium truncate">{show.title}</div>
              <div class="text-xs text-base-content/50">{show.count} file(s) waiting</div>
            </button>
          </div>

          <div class="flex-1 min-h-0 overflow-y-auto thin-scrollbar" data-nav-zone="reconcile-detail">
            <.detail
              :if={@review}
              review={@review}
              targets={@targets}
              episode_options={@episode_options}
            />
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :review, ShowReview, required: true

  attr :targets, :map,
    required: true,
    doc: ~s{select state — awaiting-file id => encoded "season-episode" value (or "skip")}

  attr :episode_options, :list,
    required: true,
    doc: "ReconcileView.episode_options/1 output — {label, value} tuples for the per-file picker"

  defp detail(assigns) do
    assigns =
      assign(assigns,
        rows: ReconcileView.file_rows(assigns.review, assigns.targets),
        recommended: assigns.review.resolution.recommended,
        alternatives: assigns.review.resolution.alternatives
      )

    ~H"""
    <div class="space-y-4">
      <div class="flex items-start justify-between gap-4">
        <div>
          <h2 class="text-lg font-semibold">{@review.series_title || "Unknown show"}</h2>
          <p :if={@recommended} class="text-sm text-base-content/50">
            {@recommended.rationale}
          </p>
        </div>
        <div class="flex gap-2 shrink-0">
          <.button variant="action" size="sm" phx-click="confirm" data-nav-item tabindex="0">
            Confirm matches
          </.button>
          <.button variant="dismiss" size="sm" phx-click="dismiss_all" data-nav-item tabindex="0">
            Dismiss all
          </.button>
        </div>
      </div>

      <div class="glass-surface rounded-xl p-3 space-y-2">
        <div
          :for={row <- @rows}
          id={"reconcile-row-#{row.id}"}
          class="glass-inset rounded-lg p-3 flex items-center gap-3"
        >
          <div class="min-w-0 flex-1">
            <div class="truncate-left text-sm font-mono" title={row.file_path}>
              <bdo dir="ltr">{row.file_path}</bdo>
            </div>
            <div class="text-xs text-base-content/40">release labelled {row.claimed}</div>
          </div>
          <.icon name="hero-arrow-right-mini" class="size-4 text-base-content/30 shrink-0" />
          <form phx-change="override" class="shrink-0">
            <input type="hidden" name="file" value={row.id} />
            <select
              name="target"
              data-nav-item
              tabindex="0"
              class="select select-sm bg-base-100/40 border-base-content/20 max-w-64"
            >
              <option
                :for={{label, value} <- @episode_options}
                value={value}
                selected={value == row.target_value}
              >
                {label}
              </option>
            </select>
          </form>
        </div>
      </div>

      <div :if={@alternatives != []} class="space-y-2">
        <h3 class="text-sm font-medium uppercase tracking-wider text-base-content/50">
          Other interpretations
        </h3>
        <div
          :for={alt <- @alternatives}
          class="glass-inset rounded-lg p-3 flex items-center justify-between gap-3"
        >
          <div class="min-w-0">
            <div class="text-sm font-medium">
              {ReconcileView.humanize_model(alt.model)}
              <span class="text-base-content/40 font-normal">
                · {ReconcileView.confidence_pct(alt.confidence)}
              </span>
            </div>
            <div class="text-xs text-base-content/50 truncate">{alt.rationale}</div>
          </div>
          <.button
            variant="neutral"
            size="xs"
            phx-click="use_interpretation"
            phx-value-model={alt.model}
            data-nav-item
            tabindex="0"
          >
            Use these
          </.button>
        </div>
      </div>
    </div>
    """
  end
end
