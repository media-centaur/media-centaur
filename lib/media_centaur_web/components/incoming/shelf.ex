defmodule MediaCentaurWeb.Components.Incoming.Shelf do
  @moduledoc """
  The Coming-up shelf — the Incoming page's forecast band (DDR-015).

  An agenda list: one vertical column of compact date-led rows in
  nearness order, each built from a `Card` view-model the LiveView
  composes out of `UpcomingFeed.shelf_items/2`. A row reads
  date → poster thumb → title/subtitle → status pill; an under-pursuit
  row's pill carries the percent and anchors down to
  `#pursuit-<pursuit_id>` — the same object's other zoom level. When
  the cap hides titles, a "Show all N" action row follows the last
  entry (the ledger's "Show earlier" idiom, applied to the shelf).
  Tracked titles with nothing scheduled are rows of the same anatomy
  behind a quiet "Not scheduled yet · N" hairline toggle (UIDR-017),
  collapsed by default — the ledger's grow-in-place idiom, applied to
  bookkeeping. Expanded, the empty date slot renders a muted em-dash
  so the columns stay aligned, and the row opens the same title modal
  as any dated row. An empty forecast with no stragglers renders
  nothing at all — no dead panel; the omnibox above is the standing
  track affordance.

  Every row is `phx-click="select_event"` and a nav item; the zone is
  `coming_up_list` (a vertical MENU instance — the home pages keep the
  horizontal `coming_up` SHELF). Desktop rendering rules apply
  (UIDR-012): eager+sync art, stable iterator ids, no entrance
  animations.
  """

  use Phoenix.Component

  import MediaCentaurWeb.Components.Incoming.StatusPill, only: [status_pill: 1]
  import MediaCentaurWeb.LiveHelpers, only: [sized_image_url: 2]
  import MediaCentaurWeb.CoreComponents, only: [icon: 1]

  defmodule Card do
    @moduledoc """
    One shelf row — the display contract the `IncomingLive.View`
    builder maps `UpcomingFeed.Event`s into.

    `key` is the stable DOM identity (`shelf-<key>`); `status` is the
    `StatusPill` union or `nil` for a plain dated row (the honest
    acquisition-off degradation); `percent` and `pursuit_id` only
    matter for `:in_pursuit` rows. `kind: :title` marks a row that
    represents the bare tracked title (a straggler) rather than a
    scheduled event — `date_label` is nil and the date slot renders
    the muted em-dash.
    """

    @enforce_keys [:key, :item_id, :title, :kind]
    defstruct [
      :key,
      :item_id,
      :pursuit_id,
      :title,
      :subtitle,
      :date_label,
      :status,
      :percent,
      :art_url,
      :kind,
      :episode_count
    ]

    @type t :: %__MODULE__{
            key: String.t(),
            item_id: term(),
            pursuit_id: Ecto.UUID.t() | nil,
            title: String.t(),
            subtitle: String.t() | nil,
            date_label: String.t() | nil,
            status:
              :armed
              | :in_pursuit
              | :in_theaters
              | :tracked
              | :searching
              | :landed
              | :failed
              | :cancelled
              | nil,
            percent: integer() | nil,
            art_url: String.t() | nil,
            kind: :episode | :movie | :season_drop | :title,
            episode_count: pos_integer() | nil
          }
  end

  attr :cards, :list, required: true, doc: "`Card.t()` rows, nearness-first."

  attr :overflow_count, :integer,
    default: 0,
    doc: "Titles beyond the visible rows — gates the horizon's \"Show all\" expansion."

  attr :stragglers, :list,
    default: [],
    doc: "`Card.t()` rows (kind `:title`) — tracked titles with nothing scheduled."

  attr :stragglers_expanded?, :boolean,
    default: false,
    doc: "Whether the \"Not scheduled yet\" section shows its rows (collapsed by default)."

  def shelf(assigns) do
    ~H"""
    <%!-- No section header: with tabs the view is already named "Coming
          up", and on the forecast-only page the date-led rows speak for
          themselves. Centered at a readable measure — the column sits
          under the centered omnibox and tabs, and titles don't drift
          from their status pills on media-center-wide screens. --%>
    <section
      :if={@cards != [] || @stragglers != []}
      data-component="incoming-shelf"
      class="mx-auto w-full max-w-3xl space-y-4"
    >
      <div data-nav-zone="coming_up_list" class="flex flex-col">
        <.shelf_row :for={card <- @cards} card={card} />
        <.horizon_action
          overflow_count={@overflow_count}
          total_count={@overflow_count + length(@cards)}
        />
        <%!-- The divider IS the toggle — collapsed by default, the
              count says what it hides ("Not scheduled yet · 3");
              expanding grows the list in place, the same idiom as the
              horizon's "Show all N". Indented to start under the date
              column so, expanded, the label sits by the em-dashes it
              explains. --%>
        <button
          :if={@stragglers != []}
          type="button"
          class="mt-3 mb-1 flex w-full cursor-pointer items-center gap-3 rounded-lg px-2 py-1 text-left transition-colors hover:bg-base-content/[0.04]"
          data-component="shelf-unscheduled-divider"
          phx-click="toggle_stragglers"
          data-nav-item
          tabindex="0"
        >
          <span class="w-24 shrink-0"></span>
          <span class="inline-flex items-center gap-1 text-[10px] font-medium uppercase tracking-wider text-base-content/35 whitespace-nowrap">
            <.icon
              name="hero-chevron-right-mini"
              class={"size-3 transition-transform#{if @stragglers_expanded?, do: " rotate-90"}"}
            /> Not scheduled yet · {length(@stragglers)}
          </span>
          <span class="h-px flex-1 bg-base-content/10"></span>
        </button>
        <.shelf_row :for={card <- @stragglers} :if={@stragglers_expanded?} card={card} />
      </div>
    </section>
    """
  end

  attr :card, Card, required: true

  def shelf_row(assigns) do
    ~H"""
    <article
      id={"shelf-#{@card.key}"}
      class="flex cursor-pointer items-center gap-3 rounded-lg px-2 py-1.5 transition-colors hover:bg-base-content/[0.04]"
      role="button"
      phx-click="select_event"
      phx-value-item-id={@card.item_id}
      data-nav-item
      tabindex="0"
    >
      <%!-- Always rendered so the date column keeps the rows aligned;
            an undated (straggler) row shows a dimmer em-dash — "no
            date, on purpose", not a layout gap. --%>
      <span
        :if={@card.date_label}
        class="w-24 shrink-0 text-xs font-medium text-base-content/55"
      >
        {@card.date_label}
      </span>
      <span :if={!@card.date_label} class="w-24 shrink-0 text-xs font-medium text-base-content/30">
        —
      </span>

      <div class="glass-inset relative h-12 w-8 shrink-0 overflow-hidden rounded-md border border-base-content/10">
        <img
          :if={@card.art_url}
          src={sized_image_url(@card.art_url, 160)}
          alt=""
          class="h-full w-full object-cover"
          loading="eager"
          decoding="sync"
        />
        <div
          :if={!@card.art_url}
          class="absolute inset-0 flex items-center justify-center bg-gradient-to-br from-base-content/[0.07] to-transparent"
        >
          <span class="select-none text-sm font-extrabold tracking-tighter text-base-content/15">
            {initial(@card.title)}
          </span>
        </div>
      </div>

      <div class="min-w-0 flex-1">
        <div class="truncate text-sm font-semibold">{@card.title}</div>
        <div :if={subtitle_line(@card)} class="truncate text-xs text-base-content/50">
          {subtitle_line(@card)}
        </div>
      </div>

      <span :if={@card.status} class="shrink-0">
        <.status_pill status={@card.status} percent={@card.percent} anchor={pill_anchor(@card)} />
      </span>
    </article>
    """
  end

  attr :overflow_count, :integer, required: true
  attr :total_count, :integer, required: true, doc: "Visible + hidden titles — the \"Show all N\" label."

  # "Show all N" grows the list in place when the cap hides titles.
  # Without overflow there's nothing to afford and the row doesn't
  # render — an affordance-shaped element must afford something.
  defp horizon_action(assigns) do
    ~H"""
    <%!-- Same row footprint as a real entry so the action reads as the
          list's next slot, not a different object. --%>
    <button
      :if={@overflow_count > 0}
      type="button"
      data-component="shelf-horizon"
      class="flex cursor-pointer items-center gap-3 rounded-lg px-2 py-2 text-left text-xs font-medium text-primary/85 transition-colors hover:bg-base-content/[0.04] hover:text-primary"
      phx-click="expand_shelf"
      data-nav-item
      tabindex="0"
    >
      <span class="w-24 shrink-0"></span>
      <.icon name="hero-plus-circle" class="size-4 shrink-0 text-base-content/30" />
      Show all {@total_count}
    </button>
    """
  end

  defp pill_anchor(%Card{status: :in_pursuit, pursuit_id: pursuit_id}) when not is_nil(pursuit_id) do
    "#pursuit-#{pursuit_id}"
  end

  defp pill_anchor(%Card{}), do: nil

  defp initial(title) do
    case String.first(title || "") do
      nil -> "?"
      first -> String.upcase(first)
    end
  end

  defp subtitle_line(%Card{kind: :season_drop, subtitle: subtitle, episode_count: count})
       when is_integer(count) do
    case subtitle do
      nil -> "All #{count} episodes at once"
      subtitle -> "#{subtitle} · all #{count} episodes at once"
    end
  end

  defp subtitle_line(%Card{subtitle: subtitle}), do: subtitle
end
