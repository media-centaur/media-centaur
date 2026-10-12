defmodule MediaCentaurWeb.Components.Acquisition.DownloadStrip do
  @moduledoc """
  The one drawing of a download-client job: its phase on the ladder, the
  phase word, the figure bar, and the facts beside them.

  Every surface that shows a job composes from `download_strip/1` — the
  pursuit row's footer, the Other downloads row, the pursuit modal's
  activity card. None draws a bar or a state word of its own; three
  drawings of one idea is how the transfer footer, the orphan badge and
  the modal's fatter bar drifted apart.

  Reads `DownloadProgress.phase` (`Downloads.Phase`): the ladder as one
  small segment per step in the shared `CellVocabulary` (past steps
  `:landed`, the current step `:underway`, later steps the muted default;
  each segment names its step on hover), the phase word as plain colored
  text, and the 3px bar — the known figure when there is one, the
  indeterminate slide while the client works with no figure, nothing for
  a held or failed job without a figure. ETA shows only during the
  download step: the client's estimate describes the transfer.

  Cancel is the house arm gesture (MC0027 tier 2): the host owns which
  job is armed and passes it as `cancel_armed_id`; a strip with no
  `queue_item_id` draws no cancel (the modal cancels the pursuit, not the
  job).
  """

  use Phoenix.Component

  import MediaCentaurWeb.CoreComponents, only: [armed_button: 1, icon: 1]

  alias MediaCentaur.Acquisition.ViewModels.DownloadProgress
  alias MediaCentaur.Downloads.Phase
  alias MediaCentaur.Format
  alias MediaCentaurWeb.Components.Acquisition.CellVocabulary

  attr :download, DownloadProgress, required: true

  attr :queue_item_id, :string,
    default: nil,
    doc: "The client's id for the job. Nil draws no cancel control."

  attr :cancel_title, :string,
    default: nil,
    doc: "The name the cancel event carries (`phx-value-title`); defaults to the release name."

  attr :cancel_armed_id, :string,
    default: nil,
    doc: "Host-owned: the queue-item id whose cancel is one click from firing."

  attr :telemetry_age, :string,
    default: nil,
    doc: "Staleness qualifier (\"last seen 4m ago\") when the client is lagging; nil when fresh."

  attr :bare, :boolean,
    default: false,
    doc:
      "Skips the top border and padding — the host frame (identity-banner strip, orphan row) provides its own."

  def download_strip(assigns) do
    phase = assigns.download.phase
    figure = phase && phase.figure
    pct = figure && round(figure * 100)

    assigns =
      assigns
      |> assign(:phase, phase)
      |> assign(:pct, pct)
      |> assign(:indeterminate?, is_nil(pct) and phase != nil and Phase.working?(phase))

    ~H"""
    <div class={[@bare && "space-y-1.5", !@bare && "border-t border-base-content/5 pt-2 space-y-1.5"]}>
      <div class="flex items-center gap-3">
        <.ladder :if={@phase} phase={@phase} />
        <span
          :if={@phase}
          class={[
            "flex-shrink-0 text-xs font-medium uppercase tracking-wider",
            Phase.text_class(@phase)
          ]}
        >
          {Phase.word(@phase)}
        </span>
        <%!-- The release name is what tells three otherwise-identical
              strips apart on a multi-download pursuit. --%>
        <span
          :if={@download.title}
          class="min-w-0 truncate text-xs text-base-content/55"
          data-tip={@download.title}
        >
          {@download.title}
        </span>
        <%!-- Facts cluster right, beside the cancel affordance — a
              left-glued cluster leaves the row's width as dead span on
              wide viewports. --%>
        <div class="flex-1" />
        <span :if={@pct} class="text-xs text-base-content/60 tabular-nums">{@pct}%</span>
        <span
          :if={@download.eta && @phase && @phase.current == :download}
          class="flex-shrink-0 text-xs text-base-content/55 tabular-nums"
        >
          ETA {@download.eta}
        </span>
        <span
          :if={@download.size_bytes}
          class="flex-shrink-0 text-xs text-base-content/55 tabular-nums"
        >
          {Format.format_size_decimal(@download.size_bytes)}
        </span>
        <span :if={@download.client} class="flex-shrink-0 text-xs text-base-content/55">
          {@download.client}
        </span>
        <%!-- When the download client is lagging/offline these figures are
              last-known, not live — qualify them so the user isn't misled
              into thinking the bar is updating in real time. --%>
        <span :if={@telemetry_age} class="text-xs text-warning/80 tabular-nums">
          · {@telemetry_age}
        </span>
        <%!-- No `shape="circle"`: the armed state relabels the control,
              and a fixed circle would clip the label it grows into. --%>
        <.armed_button
          :if={@queue_item_id}
          armed={@cancel_armed_id == @queue_item_id}
          event="cancel_download"
          armed_label="Click again to cancel"
          variant="destructive_inline"
          size="xs"
          class="text-base-content/55 hover:text-error"
          phx-value-id={@queue_item_id}
          phx-value-title={@cancel_title || @download.title}
          data-tip="Cancel and delete"
          aria-label="Cancel download"
        >
          <.icon name="hero-x-mark-mini" class="size-4" />
        </.armed_button>
      </div>

      <div :if={@pct} class="h-[3px] bg-base-content/10 rounded-full overflow-hidden">
        <div class="progress-fill h-full bg-primary rounded-full" style={"width: #{@pct}%"}></div>
      </div>
      <div
        :if={@indeterminate?}
        class="progress-indeterminate h-[3px] bg-base-content/10 rounded-full"
      >
      </div>
    </div>
    """
  end

  # The ladder: one segment per step, the same w-2 squares as the
  # composite pursuit card's unit segments (UIDR-014) — the shape of
  # completion, not a percentage.
  attr :phase, Phase, required: true

  defp ladder(assigns) do
    ~H"""
    <div class="flex flex-shrink-0 items-center gap-1" aria-hidden="true">
      <span
        :for={{step, state} <- steps(@phase)}
        data-step={step}
        data-step-state={state}
        data-tip={Phase.step_word(step)}
        class={["w-2 h-2 rounded-sm", segment_class(state)]}
      ></span>
    </div>
    """
  end

  # Past steps landed, the current step underway, later steps ahead. A
  # job with no position (failed, unknown) lights nothing.
  defp steps(%Phase{ladder: ladder, current: nil}), do: Enum.map(ladder, &{&1, :ahead})

  # A current step missing from its own ladder is a Phase bug: raise.
  defp steps(%Phase{ladder: ladder, current: current}) do
    {past, [^current | later]} = Enum.split_while(ladder, &(&1 != current))

    Enum.map(past, &{&1, :landed}) ++
      [{current, :underway}] ++ Enum.map(later, &{&1, :ahead})
  end

  defp segment_class(:landed), do: CellVocabulary.segment_treatment(:landed)
  defp segment_class(:underway), do: CellVocabulary.segment_treatment(:underway)
  defp segment_class(:ahead), do: CellVocabulary.segment_treatment(:ahead)
end
