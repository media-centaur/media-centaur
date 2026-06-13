defmodule MediaCentaurWeb.Components.Upcoming.MiniMonth do
  @moduledoc """
  The quiet, persistent mini-month companion to the rail.

  Calm by design (the rail is the star): a compact month grid where release days
  carry a small status-coloured dot (or a count for multi-release days), today is
  the single strong primary fill, and the rail's currently-focused day gets a
  quiet ring. Clicking a day jumps the rail; the chevrons page the month. Colour
  is reserved for status; the grid itself is greyscale-on-dark.
  """

  use Phoenix.Component

  import MediaCentaurWeb.CoreComponents

  alias MediaCentaurWeb.Components.Upcoming.MonthGrid
  alias MediaCentaurWeb.Components.Upcoming.Present

  @weekday_initials ~w(M T W T F S S)

  attr :year, :integer, required: true
  attr :month, :integer, required: true
  attr :today, Date, required: true
  attr :focused_day, Date, default: nil, doc: "The day the rail is scrolled to (quiet ring)."

  attr :marks, :map,
    default: %{},
    doc:
      "`%{Date => %{count, status}}` release marks for the visible month (from `UpcomingFeed.mini_month_marks/3`)."

  def mini_month(assigns) do
    assigns =
      assigns
      |> assign(:weeks, MonthGrid.weeks(assigns.year, assigns.month))
      |> assign(:weekday_initials, @weekday_initials)
      |> assign(:label, Calendar.strftime(Date.new!(assigns.year, assigns.month, 1), "%B %Y"))
      |> assign(:total, assigns.marks |> Map.values() |> Enum.map(& &1.count) |> Enum.sum())

    ~H"""
    <div class="rounded-xl glass-surface p-3" data-nav-zone="mini-month">
      <div class="mb-2 flex items-center justify-between">
        <button
          type="button"
          class="rounded p-1 text-base-content/50 hover:bg-base-content/[0.06] hover:text-base-content"
          data-nav-item
          tabindex="0"
          phx-click="mini_month_prev"
          aria-label="Previous month"
        >
          <.icon name="hero-chevron-left-mini" class="size-4" />
        </button>
        <span class="text-sm font-medium">{@label}</span>
        <button
          type="button"
          class="rounded p-1 text-base-content/50 hover:bg-base-content/[0.06] hover:text-base-content"
          data-nav-item
          tabindex="0"
          phx-click="mini_month_next"
          aria-label="Next month"
        >
          <.icon name="hero-chevron-right-mini" class="size-4" />
        </button>
      </div>

      <div class="grid grid-cols-7 gap-0.5 text-center text-[10px] text-base-content/30">
        <span :for={initial <- @weekday_initials}>{initial}</span>
      </div>

      <div class="mt-1 space-y-0.5">
        <div :for={week <- @weeks} class="grid grid-cols-7 gap-0.5">
          <div :for={cell <- week} class="aspect-square">
            <.day_cell
              :if={cell}
              date={cell}
              today={@today}
              focused_day={@focused_day}
              mark={Map.get(@marks, cell)}
            />
          </div>
        </div>
      </div>

      <p class="mt-3 text-center text-xs text-base-content/40">
        {@total} {if @total == 1, do: "release", else: "releases"} this month
      </p>
    </div>
    """
  end

  attr :date, Date, required: true
  attr :today, Date, required: true
  attr :focused_day, Date, default: nil
  attr :mark, :map, default: nil, doc: "`%{count, status}` for this day, or nil when no release."

  defp day_cell(assigns) do
    assigns =
      assigns
      |> assign(:is_today, Date.compare(assigns.date, assigns.today) == :eq)
      |> assign(
        :is_focused,
        assigns.focused_day && Date.compare(assigns.date, assigns.focused_day) == :eq
      )

    ~H"""
    <button
      type="button"
      class={[
        "relative flex h-full w-full flex-col items-center justify-center rounded text-[11px] tabular-nums transition-colors",
        cond do
          @is_today -> "bg-primary font-semibold text-primary-content"
          @is_focused -> "ring-1 ring-primary/60 text-base-content"
          @mark -> "text-base-content hover:bg-base-content/[0.06]"
          true -> "text-base-content/40 hover:bg-base-content/[0.04]"
        end
      ]}
      phx-click="jump_to_day"
      phx-value-date={Date.to_iso8601(@date)}
    >
      <span>{@date.day}</span>
      <span
        :if={@mark && @mark.count == 1}
        class={["mt-0.5 size-1 rounded-full", dot_class(@mark, @is_today)]}
      >
      </span>
      <span
        :if={@mark && @mark.count > 1}
        class="absolute right-0 top-0 text-[8px] font-semibold leading-none text-base-content/60"
      >
        {@mark.count}
      </span>
    </button>
    """
  end

  defp dot_class(_mark, true), do: "bg-primary-content"
  defp dot_class(%{status: status}, false), do: Present.tone_dot_class(Present.status_tone(status))
end
