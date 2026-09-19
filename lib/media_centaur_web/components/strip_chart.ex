defmodule MediaCentaurWeb.Components.StripChart do
  @moduledoc """
  The strip chart: N strips sharing one window, one time axis and one
  synced cursor, for any tenant with a time series to show.

  This component renders the shell — card header, the window control on
  the house segmented pill, legend, footer slot — and one element that
  carries `phx-hook="StripChart"` and `phx-update="ignore"`. The hook
  owns everything inside that element (rows, name columns, figures,
  canvases) and changes it only when a frame arrives; LiveView never
  patches it. Frames come from `MediaCentaurWeb.Components.StripChart.Feed`,
  whose moduledoc carries the frame contract.

  The pills push `strip_chart:window` with `phx-value-id` and
  `phx-value-window`; the feed handles that event and patches the URL.

  Story: `/storybook/composites/strip_chart`.
  """
  use MediaCentaurWeb, :html

  alias MediaCentaur.TimeSeries.Window

  @doc "Strip chart shell. The strips render from pushed frames."
  attr :id, :string, required: true, doc: "hook element id and the feed key"
  attr :title, :string, required: true
  attr :lede, :string, default: nil
  attr :window, :atom, required: true, values: Window.all()
  attr :windows, :list, default: Window.all(), doc: "the windows offered, in order"

  attr :legend, :list,
    default: [],
    doc: "%{label, tone} with tone in error | solid | muted | line"

  slot :footer, doc: "tenant content beside the legend"

  def strip_chart(assigns) do
    ~H"""
    <div class="card glass-inset strip-chart" data-testid={"strip-chart-#{@id}"}>
      <div class="card-body">
        <div class="flex items-start justify-between gap-4">
          <div>
            <h2 class="card-title text-lg">{@title}</h2>
            <p :if={@lede} class="text-xs text-base-content/55">{@lede}</p>
          </div>
          <div
            class="tabs tabs-boxed segmented-control w-fit shrink-0"
            role="group"
            aria-label="Window"
          >
            <button
              :for={window <- @windows}
              type="button"
              class={["tab cursor-pointer", window == @window && "tab-active"]}
              aria-pressed={to_string(window == @window)}
              phx-click="strip_chart:window"
              phx-value-id={@id}
              phx-value-window={window}
            >
              {window}
            </button>
          </div>
        </div>

        <div
          id={@id}
          phx-hook="StripChart"
          phx-update="ignore"
          class="strip-chart-strips"
          data-window={@window}
        >
        </div>

        <div class="strip-chart-footer">
          <ul class="strip-chart-legend">
            <li :for={item <- @legend}>
              <span class={"strip-chart-swatch strip-chart-swatch-#{item.tone}"}></span>
              {item.label}
            </li>
          </ul>
          {render_slot(@footer)}
        </div>
      </div>
    </div>
    """
  end
end
