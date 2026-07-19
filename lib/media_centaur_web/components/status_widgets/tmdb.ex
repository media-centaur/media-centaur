defmodule MediaCentaurWeb.Components.StatusWidgets.Tmdb do
  @moduledoc """
  TMDB subsystem Activity widget: integration config + rate-limiter budget.

  Rendered into the health-board drill-in's :activity slot via
  MediaCentaurWeb.StatusLive.ActivityWidgets, invoked with a plain data
  bundle (no change-tracking) from StatusLive.activity_bundle/1 — derive
  with Map.put/3, never assign/3.
  """
  use MediaCentaurWeb, :html

  import MediaCentaurWeb.StatusHelpers
  import MediaCentaurWeb.LiveHelpers, only: [time_ago: 1]
  import MediaCentaurWeb.Components.StatusWidgets.Shared

  @doc "TMDB subsystem Activity widget: external-integration configuration + rate-limiter budget."
  attr :rate_limiter, :map,
    default: nil,
    doc: "TMDB.RateLimiter.status/0 result (%{used, total}), or nil when not started"

  attr :config, :map,
    required: true,
    doc: "status-page config map (tmdb_configured? + related runtime config keys)"

  attr :metadata_stats, :map,
    required: true,
    doc:
      "TMDB.MetadataStats.snapshot/0 — %{last_enriched_at, total, recent} for the enrichment-activity feed"

  attr :low_confidence_count, :integer,
    default: nil,
    doc:
      "pending-review (low-confidence) match count, or nil while the library overview is still loading"

  def tmdb_widget(assigns) do
    ~H"""
    <div class="card glass-inset" data-testid="tmdb-widget">
      <div class="card-body">
        <h2 class="card-title text-lg">External Integrations</h2>

        <div class="space-y-3">
          <div class="flex items-center justify-between">
            <div class="flex items-center gap-2">
              <span class="text-sm font-medium">TMDB</span>
              <.settings_link
                :if={@config[:tmdb_configured]}
                section="tmdb"
                class="text-success text-xs"
              >
                configured
              </.settings_link>
              <.settings_link
                :if={!@config[:tmdb_configured]}
                section="tmdb"
                class="text-error text-xs"
              >
                not configured
              </.settings_link>
            </div>

            <div :if={@rate_limiter} class="flex items-center gap-3 text-sm">
              <span class="font-mono text-base-content/60">
                {@rate_limiter.used}/{@rate_limiter.total} used
              </span>
            </div>

            <span :if={!@rate_limiter} class="text-sm text-base-content/40">
              rate limiter not started
            </span>
          </div>
        </div>

        <div class="mt-4 pt-4 border-t border-base-content/10" data-component="metadata-activity">
          <h3 class="text-xs text-base-content/50 uppercase tracking-wide mb-2">Metadata</h3>

          <p :if={@metadata_stats.last_enriched_at} class="text-xs text-base-content/50">
            Last enriched {time_ago(@metadata_stats.last_enriched_at)} · {@metadata_stats.total} this session
          </p>
          <p :if={!@metadata_stats.last_enriched_at} class="text-xs text-base-content/40">
            No metadata fetched yet this session.
          </p>

          <ul :if={@metadata_stats.recent != []} class="mt-2 space-y-0.5">
            <li
              :for={entry <- @metadata_stats.recent}
              id={enriched_row_id(entry)}
              class="flex items-baseline gap-2 text-xs"
            >
              <span class="text-base-content/40 w-16 shrink-0">
                {metadata_kind_label(entry.kind)}
              </span>
              <span class="truncate text-base-content/70">{format_enriched_title(entry)}</span>
              <span class="ml-auto text-base-content/40 shrink-0">{time_ago(entry.at)}</span>
            </li>
          </ul>

          <.link
            :if={@low_confidence_count && @low_confidence_count > 0}
            navigate={~p"/review"}
            class="mt-2 inline-flex items-center gap-1.5 text-xs text-warning hover:text-warning/80"
            data-component="low-confidence-link"
          >
            <.icon name="hero-question-mark-circle-mini" class="size-3.5 shrink-0" />
            {@low_confidence_count} low-confidence {if @low_confidence_count == 1,
              do: "match",
              else: "matches"} to review
          </.link>
        </div>
      </div>
    </div>
    """
  end

  # Stable iterator id (ADR-012) for a recent-enrichment row. Enrichments are
  # seconds apart, so the microsecond stamp is collision-proof in practice.
  defp enriched_row_id(%{at: %DateTime{} = at}), do: "enriched-#{DateTime.to_unix(at, :microsecond)}"
end
