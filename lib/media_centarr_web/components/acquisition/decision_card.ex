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

  def decision_card(assigns) do
    ~H"""
    <section class="glass-surface rounded-xl p-5 space-y-4 border-warning/40">
      <div class="space-y-1">
        <h3 class="text-sm font-medium uppercase tracking-wider text-warning">
          Decision needed
        </h3>
        <p class="text-sm text-base-content/80">{@vm.prompt}</p>
      </div>

      <%= cond do %>
        <% @vm.loading? -> %>
          <div class="flex items-center gap-2 text-sm text-base-content/60">
            <.icon name="hero-arrow-path" class="size-4 animate-spin" /> Searching for alternatives…
          </div>
        <% @vm.alternatives == [] -> %>
          <div class="text-sm text-base-content/60">
            No alternatives are currently available. You can mark this pursuit as exhausted or wait — Prowlarr may surface new releases later.
          </div>
        <% true -> %>
          <ul class="space-y-2">
            <li :for={alt <- @vm.alternatives}>
              <.alternative_row pursuit_id={@vm.pursuit_id} alt={alt} />
            </li>
          </ul>
      <% end %>
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
