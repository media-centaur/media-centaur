defmodule MediaCentaurWeb.Components.Acquisition.NeedsAttention do
  @moduledoc """
  The Incoming page's problem-only surface (UIDR-016): one home for
  acquisition capability faults, absent entirely while everything is
  healthy.

  Since 2026-08 this is a single **Heads-up glyph**, not a section — a
  severity-tinted triangle sitting at the far right of the zone-tab
  row (owner call: even a quiet section is still a section; awareness
  costs one glyph, details are on demand). Hover or keyboard/gamepad
  focus reveals the details panel; click pins it open. The panel stays
  in the DOM with visibility toggled — the always-in-DOM blur rule.

  Panel content, worst-first:

    * **Search health** (`Search.IndexerHealth`) — Prowlarr unreachable
      or every enabled indexer backed off (error tone), some indexers
      backed off (warning tone).
    * **Storage** — per-drive headroom rows when a drive runs low or
      several drives host media (`DownloadStorage`).

  Deliberately not a notification center: no feed, no dismiss state, no
  history — the glyph appears while a condition is true and vanishes on
  recovery. Durable history lives on the Status page's incident track.
  """

  use Phoenix.Component

  import MediaCentaurWeb.CoreComponents, only: [icon: 1]

  alias MediaCentaur.Search.IndexerHealth
  alias MediaCentaurWeb.Components.Acquisition.DownloadStorage
  alias Phoenix.LiveView.JS

  @doc """
  Whether the glyph renders at all — storage escalated past its calm
  foot line, or search health warrants attention. Silence is the
  healthy state: absent, not a gray glyph.
  """
  def visible?(storage_mode, search_health) do
    storage_mode == :card or IndexerHealth.problem?(search_health)
  end

  attr :drives, :list,
    required: true,
    doc:
      "Media-dir-hosting `Storage.measure_all/0` drive maps (filter via `DownloadStorage.media_dir_drives/1`). Rendered as per-drive rows only when storage has escalated (`DownloadStorage.display_mode/1` == `:card`); pass `[]` otherwise."

  attr :search_health, :any,
    required: true,
    doc:
      "`MediaCentaur.Search.IndexerHealth.t()` or `nil` — the latest search-capability observation. Renders a row only for `:unreachable`, `:blind`, and `:degraded`."

  attr :open, :boolean,
    default: false,
    doc:
      "Initial pinned state — hover/focus reveal the panel transiently either way; click toggles the pin. True mainly for the storybook state matrix."

  def needs_attention(assigns) do
    search_card = search_card(assigns.search_health, DateTime.utc_now(:second))
    rows = DownloadStorage.rows(assigns.drives)

    assigns =
      assigns
      |> assign(:search_card, search_card)
      |> assign(:rows, rows)
      |> assign(:worst_class, worst_class(search_card, rows))

    ~H"""
    <div
      :if={@search_card || @rows != []}
      id="heads-up"
      class="group relative"
      data-component="heads-up-glyph"
      data-pinned={@open || nil}
    >
      <button
        type="button"
        class={["flex cursor-pointer items-center p-1", @worst_class]}
        aria-label="Heads up — hover or press for details"
        phx-click={JS.toggle_attribute({"data-pinned", "true"}, to: "#heads-up")}
        data-nav-item
        tabindex="0"
      >
        <.icon name="hero-exclamation-triangle-mini" class="size-4" />
      </button>

      <%!-- Visibility is opacity + pointer-events, never :if — the glass
            blur must stay composited (always-in-DOM rule). Shown on
            hover, on focus-within (keyboard/gamepad — hover-only would
            hide this from the couch), and while pinned. --%>
      <div class="pointer-events-none absolute left-1/2 top-full z-40 mt-2 w-96 max-w-[85vw] -translate-x-1/2 opacity-0 transition-opacity duration-150 group-focus-within:pointer-events-auto group-focus-within:opacity-100 group-hover:pointer-events-auto group-hover:opacity-100 group-data-[pinned]:pointer-events-auto group-data-[pinned]:opacity-100">
        <div class="glass-surface space-y-3 rounded-xl p-4 text-left">
          <div :if={@search_card} id="needs-attention-search" class="space-y-1">
            <div class="flex items-center gap-1.5 text-sm">
              <.icon
                name="hero-exclamation-triangle-mini"
                class={"size-4 shrink-0 #{@search_card.text_class}"}
              />
              <span class={@search_card.text_class}>{@search_card.title}</span>
            </div>
            <p class="text-xs text-base-content/60">{@search_card.detail}</p>
          </div>

          <div :for={row <- @rows} id={"needs-attention-storage-#{row.id}"} class="space-y-1.5">
            <div class="flex items-baseline justify-between gap-2">
              <span class="flex items-center gap-1.5 truncate text-sm" title={row.mount_point}>
                <.icon :if={row.icon} name={row.icon} class={"size-4 shrink-0 #{row.text_class}"} />
                {row.label}
              </span>
              <span class={["font-mono shrink-0 text-xs", row.text_class]}>
                {row.free_label} free
              </span>
            </div>
            <progress
              class={["progress h-1.5 w-full", row.progress_class]}
              value={row.usage_percent}
              max="100"
            >
            </progress>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # The glyph wears the worst condition's tone: any error outranks
  # warnings; the glyph never renders for all-healthy, so warning is
  # the floor.
  defp worst_class(search_card, rows) do
    error? =
      (search_card != nil and search_card.severity == :error) or
        Enum.any?(rows, &(&1.severity == :error))

    if error?, do: "text-error", else: "text-warning"
  end

  @doc """
  Panel copy for a search-capability fault, or `nil` when search health
  needs no card. Pure — `now` anchors the relative retry phrase.
  """
  def search_card(%IndexerHealth{state: :unreachable}, _now) do
    %{
      title: "Search can't reach Prowlarr",
      detail: "Searches fail or come back empty until it's reachable. Check that Prowlarr is running.",
      text_class: "text-error",
      severity: :error
    }
  end

  def search_card(%IndexerHealth{state: :blind} = health, now) do
    %{
      title: "No indexers are answering searches",
      detail:
        "#{backed_off_phrase(health)} after failed searches. " <>
          "Searches come back empty until #{if length(health.backed_off) == 1, do: "it", else: "one"} retries#{retry_phrase(health.retry_at, now)}.",
      text_class: "text-error",
      severity: :error
    }
  end

  def search_card(%IndexerHealth{state: :degraded} = health, now) do
    %{
      title: "Some indexers aren't answering",
      detail:
        "#{backed_off_phrase(health)} after failed searches — results run thinner than usual until #{if length(health.backed_off) == 1, do: "it", else: "one"} retries#{retry_phrase(health.retry_at, now)}.",
      text_class: "text-warning",
      severity: :warning
    }
  end

  def search_card(_health, _now), do: nil

  defp backed_off_phrase(%IndexerHealth{backed_off: [%{name: name}]}), do: "#{name} is backing off"

  defp backed_off_phrase(%IndexerHealth{backed_off: backed_off}) do
    "#{length(backed_off)} indexers are backing off"
  end

  # "in ~12 min" reads the same in every timezone; Prowlarr's absolute
  # disabledTill is UTC and would mislead a local clock.
  defp retry_phrase(nil, _now), do: ""

  defp retry_phrase(%DateTime{} = retry_at, now) do
    seconds = DateTime.diff(retry_at, now, :second)

    cond do
      seconds <= 60 -> " (within a minute)"
      seconds < 3600 -> " (in ~#{div(seconds, 60)} min)"
      true -> " (in ~#{Float.round(seconds / 3600, 1)} h)"
    end
  end
end
