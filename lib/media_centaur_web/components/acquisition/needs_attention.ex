defmodule MediaCentaurWeb.Components.Acquisition.NeedsAttention do
  @moduledoc """
  The Incoming page's problem-only section (UIDR-016): one home for
  acquisition capability faults, absent entirely while everything is
  healthy.

  Generalizes the former Storage section — same slot, same half-wide
  glass cards, same bookkeeping voice (the 2026-07-11 owner call: never
  a page-wide alarm band). Card kinds, worst-first:

    * **Search health** (`Search.IndexerHealth`) — Prowlarr unreachable
      or every enabled indexer backed off (error tone), some indexers
      backed off (warning tone).
    * **Storage** — per-drive headroom cards when a drive runs low or
      several drives host media (`DownloadStorage`).

  Deliberately not a notification center: no feed, no dismiss state, no
  history — a card appears while its condition is true and vanishes on
  recovery. Durable history lives on the Status page's incident track.
  """

  use Phoenix.Component

  import MediaCentaurWeb.CoreComponents, only: [icon: 1]

  alias MediaCentaur.Search.IndexerHealth
  alias MediaCentaurWeb.Components.Acquisition.DownloadStorage

  @doc """
  Whether the section renders at all — storage escalated past its calm
  header subtitle, or search health warrants attention. Silence is the
  healthy state: absent, not empty.
  """
  def visible?(storage_mode, search_health) do
    storage_mode == :card or IndexerHealth.problem?(search_health)
  end

  attr :drives, :list,
    required: true,
    doc:
      "Media-dir-hosting `Storage.measure_all/0` drive maps (filter via `DownloadStorage.media_dir_drives/1`). Rendered as per-drive cards only when storage has escalated (`DownloadStorage.display_mode/1` == `:card`); pass `[]` otherwise."

  attr :search_health, :any,
    required: true,
    doc:
      "`MediaCentaur.Search.IndexerHealth.t()` or `nil` — the latest search-capability observation. Renders a card only for `:unreachable`, `:blind`, and `:degraded`."

  def needs_attention(assigns) do
    assigns =
      assigns
      |> assign(:search_card, search_card(assigns.search_health, DateTime.utc_now(:second)))
      |> assign(:rows, DownloadStorage.rows(assigns.drives))

    ~H"""
    <%!-- An open section like its neighbors (Coming up / Recently landed),
          not one boxed panel: each condition gets its own half-wide glass
          card — bookkeeping voice, never a page-wide alarm band
          (UIDR-016). --%>
    <section
      :if={@search_card || @rows != []}
      class="space-y-3"
      data-component="needs-attention"
    >
      <h3 class="text-sm font-medium uppercase tracking-wider text-base-content/50">
        Needs attention
      </h3>

      <div class="grid gap-3 sm:grid-cols-2">
        <div
          :if={@search_card}
          id="needs-attention-search"
          class="glass-surface rounded-xl px-4 py-3 space-y-1"
        >
          <div class="flex items-center gap-1.5 text-sm">
            <.icon
              name="hero-exclamation-triangle-mini"
              class={"size-4 shrink-0 #{@search_card.text_class}"}
            />
            <span class={@search_card.text_class}>{@search_card.title}</span>
          </div>
          <p class="text-xs text-base-content/60">{@search_card.detail}</p>
        </div>

        <div
          :for={row <- @rows}
          id={"needs-attention-storage-#{row.id}"}
          class="glass-surface rounded-xl px-4 py-3 space-y-1.5"
        >
          <div class="flex items-baseline justify-between gap-2">
            <span class="flex items-center gap-1.5 truncate text-sm" title={row.mount_point}>
              <.icon :if={row.icon} name={row.icon} class={"size-4 shrink-0 #{row.text_class}"} />
              {row.label}
            </span>
            <span class={["text-xs font-mono shrink-0", row.text_class]}>
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
    </section>
    """
  end

  @doc """
  Card copy for a search-capability fault, or `nil` when search health
  needs no card. Pure — `now` anchors the relative retry phrase.
  """
  def search_card(%IndexerHealth{state: :unreachable}, _now) do
    %{
      title: "Search can't reach Prowlarr",
      detail: "Searches fail or come back empty until it's reachable. Check that Prowlarr is running.",
      text_class: "text-error"
    }
  end

  def search_card(%IndexerHealth{state: :blind} = health, now) do
    %{
      title: "No indexers are answering searches",
      detail:
        "#{backed_off_phrase(health)} after failed searches. " <>
          "Searches come back empty until #{if length(health.backed_off) == 1, do: "it", else: "one"} retries#{retry_phrase(health.retry_at, now)}.",
      text_class: "text-error"
    }
  end

  def search_card(%IndexerHealth{state: :degraded} = health, now) do
    %{
      title: "Some indexers aren't answering",
      detail:
        "#{backed_off_phrase(health)} after failed searches — results run thinner than usual until #{if length(health.backed_off) == 1, do: "it", else: "one"} retries#{retry_phrase(health.retry_at, now)}.",
      text_class: "text-warning"
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
