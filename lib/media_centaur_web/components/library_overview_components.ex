defmodule MediaCentaurWeb.LibraryOverviewComponents do
  @moduledoc """
  Function components for the "Your library" overview at the top of `/status`
  (the library-state altitude that sits above the operational health board).

  Four cards, each fed a slice of the `MediaCentaur.Status.LibraryOverview`
  view-model (plus, for storage, the page's already-measured drive assigns):

    * `glance_card/1` — counts, size on disk, recently-added strip
    * `pending_work_card/1` — review backlog + in-flight acquisitions
    * `completeness_card/1` — artwork / metadata / season gaps
    * `storage_outlook_card/1` — per-drive headroom + at-risk warning

  Presentation only. Counting/aggregation lives in `MediaCentaur.Status` and
  the pure helpers in `MediaCentaurWeb.StatusHelpers`. Color is reserved for
  signal: gap counters and at-risk warnings go amber only when there is
  something to act on. Lives under `lib/media_centaur_web/`, inside the
  `MediaCentaurWeb` boundary.
  """
  use MediaCentaurWeb, :html

  import MediaCentaurWeb.LiveHelpers, only: [sized_image_url: 2]

  import MediaCentaurWeb.StatusHelpers,
    only: [
      format_bytes_iec: 1,
      gap_count_class: 1,
      storage_severity: 1,
      storage_progress_class: 1,
      storage_text_class: 1
    ]

  alias MediaCentaur.Status.LibraryOverview

  @doc "At-a-glance counts + size + recently-added poster strip."
  attr :overview, LibraryOverview, required: true

  def glance_card(assigns) do
    ~H"""
    <div class="glass-surface rounded-xl p-4 space-y-4" data-component="overview-glance">
      <div class="grid grid-cols-2 @xl:grid-cols-4 gap-4">
        <.stat label="Movies" value={@overview.movie_count} />
        <.stat label="Shows" value={@overview.show_count} />
        <.stat label="Episodes" value={@overview.episode_count} />
        <.stat label="On disk" value={format_bytes_iec(@overview.total_size_bytes)} />
      </div>

      <div :if={@overview.recently_added != []} class="space-y-2">
        <h3 class="text-xs font-medium uppercase tracking-wider text-base-content/50">
          Recently added
        </h3>
        <div class="flex gap-2 overflow-x-auto thin-scrollbar pb-1">
          <.link
            :for={item <- @overview.recently_added}
            id={"overview-recent-#{item.id}"}
            navigate={~p"/"}
            class="card-hover relative aspect-[2/3] w-16 shrink-0 rounded overflow-hidden glass-inset block"
            title={item.name}
          >
            <img
              :if={item.poster_url}
              src={sized_image_url(item.poster_url, 160)}
              alt={item.name}
              class="absolute inset-0 w-full h-full object-cover"
              loading="eager"
              decoding="sync"
            />
            <div :if={!item.poster_url} class="absolute inset-x-1 bottom-1">
              <div class="text-[10px] font-semibold text-white text-on-image truncate">
                {item.name}
              </div>
            </div>
          </.link>
        </div>
      </div>
    </div>
    """
  end

  @doc "Pending review backlog and in-flight acquisitions, each linking to its surface."
  attr :overview, LibraryOverview, required: true

  def pending_work_card(assigns) do
    ~H"""
    <div class="glass-surface rounded-xl p-4 space-y-3" data-component="overview-pending">
      <h3 class="text-sm font-medium uppercase tracking-wider text-base-content/50">
        Pending work
      </h3>

      <.work_row
        href={~p"/review"}
        icon="hero-clipboard-document-list"
        count={@overview.pending_review_count}
        singular="file awaiting review"
        plural="files awaiting review"
        empty="No files awaiting review"
        tone={if @overview.pending_review_count > 0, do: "text-warning", else: "text-base-content/40"}
      />

      <.work_row
        href={~p"/incoming"}
        icon="hero-arrow-down-tray"
        count={@overview.in_flight_count}
        singular="acquisition in flight"
        plural="acquisitions in flight"
        empty="No acquisitions in flight"
        tone="text-base-content/70"
      />
    </div>
    """
  end

  @doc "Library quality gaps: missing artwork, missing metadata, incomplete seasons."
  attr :overview, LibraryOverview, required: true

  def completeness_card(assigns) do
    ~H"""
    <div class="glass-surface rounded-xl p-4 space-y-3" data-component="overview-completeness">
      <h3 class="text-sm font-medium uppercase tracking-wider text-base-content/50">
        Completeness gaps
      </h3>

      <p
        :if={LibraryOverview.no_gaps?(@overview)}
        class="flex items-center gap-2 text-sm text-base-content/60"
      >
        <.icon name="hero-check-circle" class="size-4 text-success/70" /> No gaps found
      </p>

      <div :if={!LibraryOverview.no_gaps?(@overview)} class="space-y-2">
        <.gap_row
          href={~p"/settings"}
          icon="hero-photo"
          label="Missing artwork"
          count={@overview.missing_artwork_count}
        />
        <.gap_row
          icon="hero-tag"
          label="Missing metadata"
          count={@overview.missing_metadata_count}
        />
        <.gap_row
          icon="hero-rectangle-stack"
          label="Incomplete seasons"
          count={@overview.incomplete_season_count}
        />
      </div>
    </div>
    """
  end

  @doc "Per-drive headroom and a consolidated drive-offline at-risk warning."
  attr :drives, :list,
    required: true,
    doc: "Storage.measure_all/0 drive maps (roles/used_bytes/total_bytes/usage_percent)"

  attr :at_risk, :map,
    default: nil,
    doc:
      "summarized at-risk warning from StatusHelpers.summarize_at_risk/4 " <>
        "(%{file_count, purge_in_days}) or nil when nothing is at risk"

  def storage_outlook_card(assigns) do
    ~H"""
    <div class="glass-surface rounded-xl p-4 space-y-3" data-component="overview-storage">
      <h3 class="text-sm font-medium uppercase tracking-wider text-base-content/50">
        Storage outlook
      </h3>

      <p :if={@drives == []} class="text-sm text-base-content/40">Measuring storage…</p>

      <div :for={drive <- @drives} class="space-y-1">
        <div class="flex items-baseline justify-between gap-2">
          <span class="text-sm truncate">{drive_label(drive)}</span>
          <span class="text-xs font-mono text-base-content/60 shrink-0">
            {format_bytes_iec(drive.used_bytes)} / {format_bytes_iec(drive.total_bytes)}
          </span>
        </div>
        <div class="flex items-center gap-2">
          <progress
            class={["progress h-1.5 flex-1", storage_progress_class(storage_severity(drive))]}
            value={drive.usage_percent}
            max="100"
          >
          </progress>
          <span class={[
            "text-xs font-mono w-10 text-right shrink-0",
            storage_text_class(storage_severity(drive))
          ]}>
            {drive.usage_percent}%
          </span>
        </div>
      </div>

      <div
        :if={@at_risk}
        class="flex items-center gap-2 text-xs text-warning"
        data-component="overview-at-risk"
      >
        <.icon name="hero-exclamation-triangle-mini" class="size-4 shrink-0" />
        <span>
          {@at_risk.file_count} {pluralize(@at_risk.file_count, "file", "files")} at risk
          <span :if={@at_risk.purge_in_days > 0}>
            — purge in {@at_risk.purge_in_days} {pluralize(@at_risk.purge_in_days, "day", "days")}
          </span>
          <span :if={@at_risk.purge_in_days == 0} class="text-error font-medium">
            — purge eligible now
          </span>
        </span>
      </div>
    </div>
    """
  end

  # --- private render helpers ---

  attr :label, :string, required: true
  attr :value, :any, required: true, doc: "an integer count or a preformatted string (e.g. size)"

  defp stat(assigns) do
    ~H"""
    <div>
      <div class="text-2xl font-semibold tabular-nums">{@value}</div>
      <div class="text-xs uppercase tracking-wider text-base-content/50">{@label}</div>
    </div>
    """
  end

  attr :href, :string, required: true
  attr :icon, :string, required: true
  attr :count, :integer, required: true
  attr :singular, :string, required: true
  attr :plural, :string, required: true
  attr :empty, :string, required: true
  attr :tone, :string, required: true

  defp work_row(assigns) do
    ~H"""
    <.link navigate={@href} class="flex items-center gap-3 group">
      <.icon name={@icon} class="size-5 shrink-0 text-base-content/55" />
      <span :if={@count == 0} class="text-sm text-base-content/40">{@empty}</span>
      <span :if={@count > 0} class="text-sm">
        <span class={["font-semibold tabular-nums", @tone]}>{@count}</span>
        <span class="text-base-content/70">{pluralize(@count, @singular, @plural)}</span>
      </span>
      <.icon
        name="hero-chevron-right-mini"
        class="size-4 ml-auto text-base-content/30 group-hover:text-primary"
      />
    </.link>
    """
  end

  attr :href, :string, default: nil
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :count, :integer, required: true

  defp gap_row(%{href: nil} = assigns) do
    ~H"""
    <div class="flex items-center gap-3">
      <.icon name={@icon} class="size-5 shrink-0 text-base-content/55" />
      <span class="text-sm text-base-content/70">{@label}</span>
      <span class={["text-sm font-semibold tabular-nums ml-auto", gap_count_class(@count)]}>
        {@count}
      </span>
    </div>
    """
  end

  defp gap_row(assigns) do
    ~H"""
    <.link navigate={@href} class="flex items-center gap-3 group">
      <.icon name={@icon} class="size-5 shrink-0 text-base-content/55" />
      <span class="text-sm text-base-content/70">{@label}</span>
      <span class={["text-sm font-semibold tabular-nums ml-auto", gap_count_class(@count)]}>
        {@count}
      </span>
      <.icon
        name="hero-chevron-right-mini"
        class="size-4 text-base-content/30 group-hover:text-primary"
      />
    </.link>
    """
  end

  defp drive_label(%{roles: [_ | _] = roles}) do
    Enum.map_join(roles, " · ", & &1.label)
  end

  defp drive_label(%{mount_point: mount_point}), do: mount_point
  defp drive_label(_drive), do: "Drive"

  defp pluralize(1, singular, _plural), do: singular
  defp pluralize(_count, _singular, plural), do: plural
end
