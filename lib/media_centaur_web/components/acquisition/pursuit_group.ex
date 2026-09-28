defmodule MediaCentaurWeb.Components.Acquisition.PursuitGroup do
  @moduledoc """
  Collapsible group row for N pursuits of the same show in the same
  state. Used on the Downloads page in the Active Pursuits and History
  zones when multiple episodes share a `{title, state}` bucket — without
  grouping, the page becomes a wall of near-identical compact rows.

  The header renders a single dense line:

      [chevron] <Title> · <N> episodes · <severity-colored verb>

  The header is a `disclosure/1` head whose state is the page's
  `DisclosureState` under `id` (`IncomingLive.Logic.pursuit_group_id/1`,
  stable per bucket). When open, the per-episode compact `PursuitRow`
  list renders below it.
  """

  use Phoenix.Component

  import MediaCentaurWeb.Components.Disclosure
  import MediaCentaurWeb.LiveHelpers, only: [banner_hue: 1]

  alias MediaCentaur.Acquisition.ViewModels.PursuitRow, as: PursuitRowVM
  alias MediaCentaurWeb.Components.Acquisition.PursuitRow
  alias MediaCentaurWeb.Components.Acquisition.PursuitStyle

  attr :id, :string, required: true, doc: "the group's disclosure id."
  attr :title, :string, required: true
  attr :state, :atom, required: true
  attr :awaiting?, :boolean, required: true
  attr :count, :integer, required: true
  attr :verb, :string, required: true
  attr :severity, :atom, required: true, values: [:info, :success, :warning, :error]

  attr :vms, :list,
    required: true,
    doc: "List of `PursuitRow.t()` view-models, one per pursuit in the group."

  attr :expanded?, :boolean, default: false

  def pursuit_group(assigns) do
    ~H"""
    <div class="identity-row rounded-lg overflow-hidden" style={"--banner-hue: #{banner_hue(@title)}"}>
      <.disclosure
        id={@id}
        open={@expanded?}
        variant={:bare}
        head_class="w-full px-3 py-2 flex items-baseline gap-3 text-left hover:bg-base-content/[0.03] transition-colors"
        caret_class="size-4 text-base-content/40"
        body_class="divide-y divide-base-content/5 border-t border-base-content/5"
      >
        <:head>
          <span class="min-w-0 flex-1 truncate text-sm font-medium">{@title}</span>
          <span class="flex-shrink-0 text-xs text-base-content/55 tabular-nums">
            {@count} {episode_word(@count)}
          </span>
          <span class={"flex-shrink-0 text-xs truncate max-w-[35%] #{PursuitStyle.severity_text_class(@severity)}"}>
            {@verb}
          </span>
        </:head>
        <PursuitRow.pursuit_row
          :for={%PursuitRowVM{} = vm <- @vms}
          vm={vm}
          density={:compact}
          framed={false}
        />
      </.disclosure>
    </div>
    """
  end

  defp episode_word(1), do: "episode"
  defp episode_word(_), do: "episodes"
end
