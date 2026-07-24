defmodule MediaCentaurWeb.Components.Incoming.Shelf do
  @moduledoc """
  The Coming-up shelf — the Incoming page's forecast band (DDR-015).

  A single row of large 2:3 poster cards in nearness order, each built
  from a `Card` view-model the LiveView composes out of
  `UpcomingFeed.shelf_items/2`. After the last card sits the dashed
  horizon terminus — a ghost card with the same footprint as a real
  one, carrying only the action: "Track something" (opens the track
  modal), or "Show all N" when the cap hides titles (the ledger's
  "Show earlier" idiom, applied to the shelf). Tracked titles with nothing
  scheduled fold into a quiet one-line disclosure under the shelf — no
  dead panel when there are none.

  The row shrinks its cards rather than wrapping (six cards fit at
  1600px); every card is `phx-click="select_event"` and a nav item.
  An under-pursuit card renders a 2px progress hairline and its status
  pill anchors down to `#pursuit-<pursuit_id>` — the same object's
  other zoom level. Desktop rendering rules apply (ADR-012): eager+sync
  art, stable iterator ids, no entrance animations.
  """

  use Phoenix.Component

  import MediaCentaurWeb.Components.Incoming.StatusPill, only: [status_pill: 1]
  import MediaCentaurWeb.CoreComponents, only: [icon: 1]

  defmodule Card do
    @moduledoc """
    One shelf card — the display contract the `IncomingLive.View`
    builder maps `UpcomingFeed.Event`s into.

    `key` is the stable DOM identity (`shelf-<key>`); `status` is the
    `StatusPill` union or `nil` for a plain dated card (the honest
    acquisition-off degradation); `percent` and `pursuit_id` only
    matter for `:in_pursuit` cards.
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
            kind: :episode | :movie | :season_drop,
            episode_count: pos_integer() | nil
          }
  end

  attr :cards, :list, required: true, doc: "`Card.t()` rows, nearness-first."

  attr :overflow_count, :integer,
    default: 0,
    doc: "Titles beyond the visible cards — gates the terminus' \"Show all\" expansion."

  attr :stragglers, :list,
    default: [],
    doc: "`UpcomingFeed.Straggler.t()` rows — tracked titles with nothing scheduled."

  attr :tmdb_ready, :boolean,
    default: false,
    doc: "Gates the terminus' \"Track something\" affordance (opens the track modal)."

  def shelf(assigns) do
    ~H"""
    <section data-component="incoming-shelf" class="space-y-4">
      <h3 class="text-sm font-medium uppercase tracking-wider text-base-content/50">
        Coming up
      </h3>

      <%!-- An expanded shelf wraps into rows; capped it stays one line
            (six cards fit at 1600px, shrinking not wrapping). --%>
      <div data-nav-zone="coming_up" class="flex flex-wrap gap-5">
        <.shelf_card :for={card <- @cards} card={card} />
        <.horizon_terminus
          overflow_count={@overflow_count}
          total_count={@overflow_count + length(@cards)}
          tmdb_ready={@tmdb_ready}
        />
      </div>

      <.stragglers_disclosure :if={@stragglers != []} stragglers={@stragglers} />
    </section>
    """
  end

  attr :card, Card, required: true

  def shelf_card(assigns) do
    assigns = assign(assigns, :hairline?, hairline?(assigns.card))

    ~H"""
    <article
      id={"shelf-#{@card.key}"}
      class="min-w-0 max-w-48 flex-1 cursor-pointer space-y-2.5"
      role="button"
      phx-click="select_event"
      phx-value-item-id={@card.item_id}
      data-nav-item
      tabindex="0"
    >
      <div class={["relative", @card.kind == :season_drop && stacked_class()]}>
        <div class="glass-inset relative aspect-[2/3] overflow-hidden rounded-xl border border-base-content/10">
          <img
            :if={@card.art_url}
            src={@card.art_url}
            alt=""
            class="h-full w-full object-cover"
            loading="eager"
            decoding="sync"
          />
          <div
            :if={!@card.art_url}
            class="absolute inset-0 flex items-center justify-center bg-gradient-to-br from-base-content/[0.07] to-transparent"
          >
            <span class="select-none text-6xl font-extrabold tracking-tighter text-base-content/10">
              {initial(@card.title)}
            </span>
          </div>

          <div class="absolute inset-0 bg-gradient-to-t from-base-300/70 to-transparent to-45%" />

          <span
            :if={@card.date_label}
            class="absolute left-2 top-2 whitespace-nowrap rounded-full border border-base-content/15 bg-base-300/80 px-2 py-0.5 text-[11px] font-semibold"
          >
            {@card.date_label}
          </span>

          <span
            :if={@card.status}
            class={["absolute right-2", (@hairline? && "bottom-3") || "bottom-2"]}
          >
            <.status_pill status={@card.status} percent={@card.percent} anchor={pill_anchor(@card)} />
          </span>

          <div :if={@hairline?} class="absolute inset-x-0 bottom-0 h-0.5 bg-base-content/15">
            <div class="h-full bg-info" style={"width: #{@card.percent}%"} />
          </div>
        </div>
      </div>

      <div class="min-w-0">
        <div class="truncate text-sm font-semibold">{@card.title}</div>
        <div :if={subtitle_line(@card)} class="truncate text-xs text-base-content/50">
          {subtitle_line(@card)}
        </div>
      </div>
    </article>
    """
  end

  attr :overflow_count, :integer, required: true
  attr :total_count, :integer, required: true, doc: "Visible + hidden titles — the \"Show all N\" label."
  attr :tmdb_ready, :boolean, required: true

  defp horizon_terminus(assigns) do
    # The terminus offers at most one action. Overflow wins ("Show all N"
    # grows the shelf in place); otherwise, with TMDB configured, the
    # track affordance. With neither, there's nothing to afford and the
    # ghost doesn't render — an affordance-shaped element must afford
    # something.
    action =
      cond do
        assigns.overflow_count > 0 ->
          %{event: "expand_shelf", label: "Show all #{assigns.total_count}"}

        assigns.tmdb_ready ->
          %{event: "open_track_modal", label: "Track something"}

        true ->
          nil
      end

    assigns = assign(assigns, :action, action)

    ~H"""
    <%!-- Same footprint as a real card (max-w-48 flex-1) so the ghost
          reads as the shelf's next slot, not a different object. The whole
          dashed card is the click target — icon and label are one button,
          not a decorative icon beside a text link. --%>
    <article
      :if={@action}
      aria-label="End of forecast"
      class="min-w-0 max-w-48 flex-1"
      data-component="shelf-horizon"
    >
      <button
        type="button"
        class="flex aspect-[2/3] w-full cursor-pointer flex-col items-center justify-center gap-2.5 rounded-xl border-[1.5px] border-dashed border-base-content/15 px-3 text-center text-xs text-primary/85 transition-colors hover:border-primary/40 hover:text-primary"
        phx-click={@action.event}
        data-nav-item
        tabindex="0"
      >
        <.icon name="hero-plus-circle" class="size-6 text-base-content/25" />
        {@action.label}
      </button>
    </article>
    """
  end

  attr :stragglers, :list, required: true, doc: "Non-empty `Straggler.t()` rows."

  defp stragglers_disclosure(assigns) do
    ~H"""
    <details class="text-xs text-base-content/40" data-component="shelf-stragglers">
      <summary class="cursor-pointer list-none transition-colors hover:text-base-content/70">
        <span class="inline-flex items-center gap-1">
          <.icon
            name="hero-chevron-right-mini"
            class="size-3 transition-transform [details[open]_&]:rotate-90"
          /> Also tracking {straggler_count_label(@stragglers)} with nothing scheduled
        </span>
      </summary>
      <div class="mt-1.5 flex flex-wrap gap-x-4 gap-y-1 pl-4">
        <span :for={straggler <- @stragglers} id={"shelf-straggler-#{straggler.item_id}"}>
          {straggler.name}
        </span>
      </div>
    </details>
    """
  end

  defp straggler_count_label([_single]), do: "1 title"
  defp straggler_count_label(stragglers), do: "#{length(stragglers)} titles"

  defp hairline?(%Card{status: :in_pursuit, percent: percent}) when is_integer(percent), do: true
  defp hairline?(%Card{}), do: false

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

  # The mockup's stacked-sheets treatment for a season drop — two offset
  # ghost sheets behind the art, pure decoration (aria-hidden by being
  # ::before/::after pseudo-elements).
  defp stacked_class do
    "isolate before:absolute before:inset-0 before:-z-10 before:translate-x-[5px] before:-translate-y-[5px] before:rotate-[1.1deg] before:rounded-xl before:border before:border-base-content/10 before:bg-base-200 before:opacity-75 before:content-[''] after:absolute after:inset-0 after:-z-20 after:translate-x-[10px] after:-translate-y-[10px] after:rotate-[2.2deg] after:rounded-xl after:border after:border-base-content/10 after:bg-base-200 after:opacity-45 after:content-['']"
  end
end
