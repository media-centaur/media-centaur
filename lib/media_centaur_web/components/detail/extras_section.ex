defmodule MediaCentaurWeb.Components.Detail.ExtrasSection do
  @moduledoc """
  The "Extras" block of the detail modal's content list — a muted
  header over a row per bonus item, each with a play target and a
  watched toggle.

  One component for both owners: the entity-level extras rendered after
  a content list (the caller pre-filters season-owned ones via
  `Detail.Logic.entity_extras/1`) and a season's own extras rendered
  inside its accordion (which pass the tighter `pt-2` spacing).
  Tolerates `nil` / `Ecto.Association.NotLoaded` extras so callers
  don't have to guard preload state.
  """

  use MediaCentaurWeb, :html

  Module.register_attribute(__MODULE__, :storybook_status, persist: true)
  Module.register_attribute(__MODULE__, :storybook_reason, persist: true)

  @storybook_status :skip
  @storybook_reason "Rendered by the detail_panel story's extras-bearing variations; row chrome pinned by the PlayableRow stories. A standalone story would duplicate those fixtures verbatim."

  alias MediaCentaurWeb.Components.Detail.PlayableRow

  attr :extras, :any,
    default: [],
    doc:
      "`[MediaCentaur.Library.Extra.t()]` — also accepts `nil` / `%Ecto.Association.NotLoaded{}` (renders nothing)."

  attr :extra_progress_by_id, :map,
    default: %{},
    doc: "`%{Ecto.UUID.t() => WatchProgress.t()}` keyed by extra id."

  attr :entity_id, :string, required: true
  attr :on_play, :string, required: true
  attr :class, :any, default: "pt-3", doc: "spacing above the block — seasons pass `pt-2`."

  def extras_section(assigns) do
    assigns = assign(assigns, :extras, normalize(assigns.extras))

    ~H"""
    <div :if={@extras != []} class={@class}>
      <span class="text-xs font-medium text-base-content/50 uppercase tracking-wide">Extras</span>
      <.extra_row
        :for={extra <- @extras}
        extra={extra}
        progress={Map.get(@extra_progress_by_id, extra.id)}
        entity_id={@entity_id}
        on_play={@on_play}
      />
    </div>
    """
  end

  defp normalize(extras) when is_list(extras), do: extras
  defp normalize(_extras), do: []

  attr :extra, :map, required: true, doc: "`MediaCentaur.Library.Extra.t()` (Ecto schema)."

  attr :progress, :map,
    default: nil,
    doc: "`MediaCentaur.Library.WatchProgress.t() | nil` for this extra."

  attr :entity_id, :string, required: true
  attr :on_play, :string, required: true

  defp extra_row(assigns) do
    state = PlayableRow.state_from_progress(assigns.progress)
    assigns = assign(assigns, :state, state)

    ~H"""
    <div class="py-0.5 pr-3" data-role="extra-row">
      <div
        class={[
          "flex items-center gap-2 text-sm cursor-pointer hover:bg-base-content/5 rounded-lg p-2 -mx-2",
          @state == :watched && "opacity-60"
        ]}
        phx-click={@on_play}
        phx-value-id={@extra.id}
        data-nav-item
        tabindex="0"
      >
        <.icon name="hero-film-mini" class="size-4 text-base-content/40 flex-shrink-0" />
        <span class="flex-1 min-w-0 truncate text-base-content/70">{@extra.name || "—"}</span>
        <PlayableRow.watched_toggle
          event="toggle_extra_watched"
          state={@state}
          progress={@progress}
          phx-value-entity-id={@entity_id}
          phx-value-extra-id={@extra.id}
        />
      </div>
      <PlayableRow.progress_underline :if={@state == :current} progress={@progress} class="ml-6" />
    </div>
    """
  end
end
