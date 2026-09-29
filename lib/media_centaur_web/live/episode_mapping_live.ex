defmodule MediaCentaurWeb.EpisodeMappingLive do
  @moduledoc """
  The episode-mapping surface, the Review tab "Episode mapping". Identity ("which show?") is settled upstream; this page
  answers "which episode?" for files whose release numbering doesn't match
  TMDB's canonical episode list (the cour / absolute-numbering case).

  Master/detail: the left list is every show with files waiting; the right
  pane renders the engine's recommended file→episode mapping (each row a
  per-file episode picker), plus the alternative interpretations as
  collapsed chips the user can adopt. Confirming links the files to their
  canonical episodes — never fabricating a phantom season.

  View logic lives in `MediaCentaurWeb.EpisodeMappingView` ([ADR-030]); this
  module is thin wiring. `EpisodeMapping.resolve_show/1` assembles the
  spine from TMDB's episode list, so it runs in `start_async/3`.
  """
  use MediaCentaurWeb, :live_view

  require MediaCentaur.Log, as: Log

  import MediaCentaurWeb.Components.DismissedFiles
  import MediaCentaurWeb.Components.ReviewTabs

  alias MediaCentaur.EpisodeMapping
  alias MediaCentaur.EpisodeMapping.ShowReview
  alias MediaCentaurWeb.Live.ArmGesture
  alias MediaCentaurWeb.Live.DisclosureState
  alias MediaCentaurWeb.EpisodeMappingView

  @impl true
  def mount(_params, _session, socket) do
    socket = assign(socket, page_title: "Review")

    # No EpisodeMapping.subscribe() here — MediaCentaurWeb.ShellBadges
    # (default live_session on_mount) already subscribes every LiveView to
    # episode_mapping:updates; a second subscribe would double-deliver each
    # message.
    {:ok,
     socket
     |> assign(loaded?: false, selected_tmdb: nil, review: nil, targets: %{}, episode_options: [])
     |> assign(shows: [], dismissed: [])}
  end

  @impl true
  def handle_params(_params, _uri, socket), do: {:noreply, ensure_loaded(socket)}

  defp ensure_loaded(%{assigns: %{loaded?: true}} = socket), do: socket
  defp ensure_loaded(socket), do: socket |> load() |> assign(:loaded?, true)

  defp load(socket) do
    shows = EpisodeMappingView.show_summaries(EpisodeMapping.list_awaiting())
    selected = pick_selected(shows, socket.assigns.selected_tmdb)

    dismissed =
      for file <- EpisodeMapping.list_dismissed(),
          do: %{id: file.id, path: Path.relative_to(file.file_path, file.media_dir)}

    socket
    |> assign(shows: shows, dismissed: dismissed)
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

  # The spine is TMDB's episode list, read through the store (which may ask
  # TMDB), so the show resolves off the LiveView process (ADR-044) and
  # lands in `handle_async({:resolve_show, _}, ...)`.
  defp select(socket, tmdb_id) do
    socket
    |> assign(selected_tmdb: tmdb_id)
    |> start_async({:resolve_show, tmdb_id}, fn -> EpisodeMapping.resolve_show(tmdb_id) end)
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
        do: EpisodeMappingView.targets_from_placements(interpretation.placements),
        else: socket.assigns.targets

    {:noreply, assign(socket, targets: targets)}
  end

  def handle_event("confirm", _params, socket) do
    review = socket.assigns.review
    targets = EpisodeMappingView.included_targets(socket.assigns.targets)

    {:noreply, socket |> apply_confirm(review, targets) |> load()}
  end

  # Dismissing every awaiting file has no undo, so it takes the arm
  # gesture (MC0027 tier 2): the first click arms, the second fires.
  def handle_event("dismiss_all", _params, socket) do
    case ArmGesture.press(socket, "dismiss_all") do
      {:armed, socket} ->
        {:noreply, socket}

      {:fire, socket} ->
        files = socket.assigns.review.awaiting_files
        for file <- files, do: EpisodeMapping.dismiss_awaiting(file)

        {:noreply,
         socket
         |> put_flash(:info, "Dismissed #{length(files)} file(s).")
         |> load()}
    end
  end

  def handle_event("restore", %{"id" => id}, socket) do
    case EpisodeMapping.restore_awaiting(id) do
      {:ok, _restored} ->
        {:noreply, load(socket)}

      {:error, _reason} ->
        {:noreply, socket |> put_flash(:error, "Could not restore the file") |> load()}
    end
  end

  @impl true
  def handle_async({:resolve_show, tmdb_id}, {:ok, review}, socket) do
    if socket.assigns.selected_tmdb == tmdb_id do
      {:noreply,
       socket
       |> assign(review: review)
       |> assign(targets: EpisodeMappingView.initial_targets(review.resolution))
       |> assign(episode_options: EpisodeMappingView.episode_options(review.spine))}
    else
      {:noreply, socket}
    end
  end

  def handle_async({:resolve_show, tmdb_id}, {:exit, reason}, socket) do
    Log.warning(:pipeline, "episode mapping — resolving tmdb:#{tmdb_id} failed: #{inspect(reason)}")
    {:noreply, put_flash(socket, :error, "Couldn't load the show's episodes")}
  end

  @impl true
  def handle_info({:episode_mapping_updated}, socket), do: {:noreply, load(socket)}
  def handle_info(_message, socket), do: {:noreply, socket}

  defp apply_confirm(socket, _review, targets) when map_size(targets) == 0 do
    put_flash(socket, :error, "Pick an episode for at least one file first.")
  end

  defp apply_confirm(socket, review, targets) do
    case EpisodeMapping.confirm(review, targets) do
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
    <Layouts.app
      show_discovery={@show_discovery}
      show_apps={@show_apps}
      flash={@flash}
      current_path="/episode-mapping"
      badges={assigns[:badges] || %MediaCentaurWeb.ShellBadges.Counts{}}
    >
      <div
        class="flex flex-col h-full gap-4"
        data-page-behavior="episode-mapping"
        data-nav-default-zone="episode-mapping"
      >
        <.page_header title="Review" />

        <.review_tabs
          active={:mapping}
          identity_count={@badges.review_pending}
          mapping_count={@badges.mapping_pending}
        />

        <p :if={@shows != []} class="text-sm text-base-content/55">
          Files of a known show that name no episode, or number it differently from the episode list.
          Confirm where each one belongs.
        </p>

        <div :if={@shows == []} class="space-y-4" data-nav-zone="episode-mapping-list">
          <.empty_state icon="hero-queue-list" headline="Episodes we could not place land here">
            When a file of a known show names no episode, or numbers it in a way the show's
            episode list doesn't have — a separately-numbered cour, absolute numbering — it
            waits here instead of inventing a season for it. You map it to the right episode.
          </.empty_state>
          <.dismissed_files
            id="episode-mapping-dismissed"
            open={DisclosureState.open?(@disclosures, "episode-mapping-dismissed")}
            files={@dismissed}
            hint={dismissed_hint()}
          />
        </div>

        <div :if={@shows != []} class="flex gap-4 flex-1 min-h-0">
          <div
            class="w-72 shrink-0 overflow-y-auto thin-scrollbar"
            data-nav-zone="episode-mapping-list"
          >
            <button
              :for={show <- @shows}
              id={"episode-mapping-show-#{show.tmdb_id}"}
              type="button"
              phx-click="select_show"
              phx-value-tmdb={show.tmdb_id}
              data-nav-item
              tabindex="0"
              class={[
                "w-full text-left glass-inset rounded-lg p-3 mb-2 cursor-pointer border border-transparent transition-colors",
                @selected_tmdb == show.tmdb_id && "bg-primary/12 !border-primary/25"
              ]}
            >
              <div class="font-medium truncate">{show.title}</div>
              <div class="text-xs text-base-content/55">{show.count} file(s) waiting</div>
            </button>
            <.dismissed_files
              id="episode-mapping-dismissed"
              open={DisclosureState.open?(@disclosures, "episode-mapping-dismissed")}
              files={@dismissed}
              hint={dismissed_hint()}
              class="mt-2"
            />
          </div>

          <div
            class="flex-1 min-h-0 overflow-y-auto thin-scrollbar"
            data-nav-zone="episode-mapping-detail"
          >
            <.detail
              :if={@review && @review.tmdb_id == @selected_tmdb}
              dismiss_all_armed={ArmGesture.armed?(@armed_gesture, "dismiss_all")}
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

  defp dismissed_hint, do: "Dismissed files are skipped on every scan. Restore one to map it again."

  attr :review, ShowReview, required: true
  attr :dismiss_all_armed, :boolean, default: false, doc: "Dismiss all is one click from firing."

  attr :targets, :map,
    required: true,
    doc: ~s{select state — awaiting-file id => encoded "season-episode" value (or "skip")}

  attr :episode_options, :list,
    required: true,
    doc: "EpisodeMappingView.episode_options/1 output — {label, value} tuples for the per-file picker"

  defp detail(assigns) do
    assigns =
      assign(assigns,
        rows: EpisodeMappingView.file_rows(assigns.review, assigns.targets),
        recommended: assigns.review.resolution.recommended,
        alternatives: assigns.review.resolution.alternatives
      )

    ~H"""
    <div class="space-y-4">
      <div class="flex items-start justify-between gap-4">
        <div>
          <h2 class="text-lg font-semibold">{@review.series_title || "Unknown show"}</h2>
          <p :if={@recommended} class="text-sm text-base-content/55">
            {@recommended.rationale}
          </p>
        </div>
        <div class="flex gap-2 shrink-0">
          <.button variant="action" size="sm" phx-click="confirm" data-nav-item tabindex="0">
            Confirm matches
          </.button>
          <.armed_button
            armed={@dismiss_all_armed}
            event="dismiss_all"
            armed_label="Click again to dismiss all"
            variant="dismiss"
          >
            Dismiss all
          </.armed_button>
        </div>
      </div>

      <div class="glass-surface rounded-xl p-3 space-y-2">
        <div
          :for={row <- @rows}
          id={"episode-mapping-row-#{row.id}"}
          class="glass-inset rounded-lg p-3 flex items-center gap-3"
        >
          <div class="min-w-0 flex-1">
            <div class="truncate-left text-sm font-mono" title={row.file_path}>
              <bdo dir="ltr">{row.file_path}</bdo>
            </div>
            <div class="text-xs text-base-content/55">release labelled {row.claimed}</div>
          </div>
          <.icon name="hero-arrow-right-mini" class="size-4 text-base-content/30 shrink-0" />
          <form id={"override-#{row.id}"} phx-change="override" class="shrink-0">
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
        <h3 class="text-sm font-medium uppercase tracking-wider text-base-content/55">
          Other interpretations
        </h3>
        <div
          :for={alt <- @alternatives}
          class="glass-inset rounded-lg p-3 flex items-center justify-between gap-3"
        >
          <div class="min-w-0">
            <div class="text-sm font-medium">
              {EpisodeMappingView.humanize_model(alt.model)}
              <span class="text-base-content/55 font-normal">
                · {EpisodeMappingView.confidence_pct(alt.confidence)}
              </span>
            </div>
            <div class="text-xs text-base-content/55 truncate">{alt.rationale}</div>
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
