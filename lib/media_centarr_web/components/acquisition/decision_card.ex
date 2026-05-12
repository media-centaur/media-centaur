defmodule MediaCentarrWeb.Components.Acquisition.DecisionCard do
  @moduledoc """
  Renders the alternatives picker shown on a pursuit detail page when its
  state is `:needs_decision`. Each alternative carries a "Try this one"
  button that the LiveView wires to `Acquisition.pick_alternative/3`
  (which submits to Prowlarr and routes through `Commands.PickTarget`).
  """

  use Phoenix.Component

  import MediaCentarrWeb.CoreComponents, only: [button: 1, icon: 1]

  alias MediaCentarr.Acquisition.ViewModels.{Alternative, DecisionCard}

  attr :vm, DecisionCard, required: true

  attr :on_cancel, :string,
    default: nil,
    doc:
      "Event to fire when the user clicks Cancel pursuit. When set, a Cancel button " <>
        "renders in the action row alongside Search Prowlarr again. The Decision card " <>
        "is the single home for all decision-related actions in `needs_decision` — the " <>
        "Activity card is suppressed in that state by the modal."

  def decision_card(assigns) do
    ~H"""
    <%!-- Single card carrying everything decision-related for a pursuit
          in `needs_decision`. The Activity card is suppressed in this
          state by the modal renderer, so this card owns the heading,
          prompt, alternatives (or empty state), and all actions —
          Cancel pursuit and Search Prowlarr again live together in one
          action row instead of being scattered across two cards. --%>
    <section class="glass-surface rounded-xl p-5 space-y-4 border-warning/40">
      <p class="text-sm text-base-content/80">{@vm.prompt}</p>

      <%= cond do %>
        <% @vm.loading? -> %>
          <div class="flex items-center gap-2 text-sm text-base-content/60">
            <.icon name="hero-arrow-path" class="size-4 animate-spin" /> Searching for alternatives…
          </div>
        <% @vm.alternatives == [] -> %>
          <p class="text-sm text-base-content/60">
            No alternatives are currently available. Search Prowlarr again to look for new releases.
          </p>
        <% true -> %>
          <ul class="space-y-2">
            <li :for={alt <- @vm.alternatives}>
              <.alternative_row pursuit_id={@vm.pursuit_id} alt={alt} />
            </li>
          </ul>
      <% end %>

      <%!-- Unified action row. Cancel is always available; Search again
            shows only in the empty-alternatives branch (no point
            "searching again" while we already are or when results just
            arrived). Loading state shows neither — wait for the search
            to settle first. --%>
      <div
        :if={!@vm.loading? && (@on_cancel || @vm.alternatives == [])}
        class="flex justify-end gap-2 pt-1"
      >
        <.button :if={@on_cancel} variant="dismiss" size="sm" phx-click={@on_cancel}>
          Cancel pursuit
        </.button>
        <.button
          :if={@vm.alternatives == []}
          variant="action"
          size="sm"
          phx-click="refresh_alternatives"
        >
          <.icon name="hero-arrow-path-mini" class="size-4" /> Search Prowlarr again
        </.button>
      </div>
    </section>
    """
  end

  attr :pursuit_id, :string, required: true
  attr :alt, Alternative, required: true

  defp alternative_row(assigns) do
    ~H"""
    <div class="glass-inset rounded-lg p-3 flex items-center gap-3">
      <div class="min-w-0 flex-1 space-y-1">
        <div class="text-sm truncate">{@alt.title}</div>
        <div class="flex items-center gap-2 text-xs text-base-content/60">
          <span>{@alt.indexer}</span>
          <span :if={@alt.quality}>· {@alt.quality}</span>
          <span :if={@alt.size_bytes}>· {format_size(@alt.size_bytes)}</span>
          <span :if={@alt.seeders}>· {@alt.seeders} seeders</span>
        </div>
      </div>
      <.button
        variant="action"
        size="sm"
        phx-click="pick_alternative"
        phx-value-pursuit-id={@pursuit_id}
        phx-value-guid={@alt.guid}
        phx-value-label={@alt.title}
      >
        Try this one
      </.button>
    </div>
    """
  end

  defp format_size(bytes) when is_integer(bytes) and bytes >= 1_000_000_000 do
    "#{Float.round(bytes / 1_000_000_000, 1)} GB"
  end

  defp format_size(bytes) when is_integer(bytes) and bytes >= 1_000_000 do
    "#{div(bytes, 1_000_000)} MB"
  end

  defp format_size(bytes) when is_integer(bytes), do: "#{bytes} B"
  defp format_size(_), do: ""
end
