defmodule MediaCentarrWeb.Components.ModalShell do
  @moduledoc """
  Centered overlay shell for the DetailPanel.

  Always present in the DOM so the browser keeps the `backdrop-filter`
  compositing layer warm. Toggled via `data-state="open"/"closed"` +
  CSS visibility/opacity — no first-frame blur jank on open.
  """

  use MediaCentarrWeb, :html

  import MediaCentarrWeb.LiveHelpers, only: [image_url: 2]

  alias MediaCentarrWeb.Components.DetailPanel

  # ModalShell is a thin wrapper around DetailPanel — these attrs forward
  # one-to-one. The contracts live on DetailPanel; this layer just passes
  # them through.

  attr :open, :boolean, default: false

  attr :entity, :map,
    default: nil,
    doc:
      "polymorphic Library schema (`Movie | TVSeries | MovieSeries | VideoObject`) — see `DetailPanel.detail_panel/1` for the field contract."

  attr :progress, :map,
    default: nil,
    doc: "`MediaCentarr.Library.ProgressSummary.t() | nil` — produced by `Library.Browser`."

  attr :resume, :map,
    default: nil,
    doc:
      "resume target map `%{kind, season, episode, ...} | nil` describing where playback would resume; see `LibraryProgress.resume_target_for/1` for the producer."

  attr :progress_records, :list,
    default: [],
    doc: "list of `MediaCentarr.Library.ProgressRecord.t()` rows preloaded from the entity."

  attr :expanded_seasons, MapSet, default: nil
  attr :on_play, :string, default: "play"
  attr :on_close, :string, default: "close_detail"
  attr :rematch_confirm, :boolean, default: false
  attr :detail_view, :atom, default: :main

  attr :detail_files, :list,
    default: [],
    doc:
      "list of file-info maps (`%{file: KnownFile.t(), entity_id, role, ...}`) built by `LibraryLive.list_files_for_entity/2` for the Files sub-view."

  attr :delete_confirm, :any,
    default: nil,
    doc:
      "transient delete-confirmation state — `nil`, `:entity`, or a `%{file_id: id}` map. Heterogeneous tag-or-map shape; `:any` is intentional."

  attr :spoiler_free, :boolean, default: false
  attr :tracking_status, :atom, default: nil
  attr :available, :boolean, default: true
  attr :tmdb_ready, :boolean, default: true

  def modal_shell(assigns) do
    backdrop_url =
      if assigns.entity && assigns.available do
        image_url(assigns.entity, "backdrop") || image_url(assigns.entity, "poster")
      end

    assigns = assign(assigns, :backdrop_url, backdrop_url)

    ~H"""
    <div
      id="detail-modal"
      class="modal-backdrop"
      data-state={if @open, do: "open", else: "closed"}
      phx-click={@open && @on_close}
      phx-window-keydown={@open && @on_close}
      phx-key="Escape"
      data-detail-mode={@open && "modal"}
      data-detail-view={@open && to_string(@detail_view)}
    >
      <div class="modal-panel" phx-click={%Phoenix.LiveView.JS{}}>
        <%!-- Close button — pinned to the panel, sits above the scroll
              surface so it stays in place while content scrolls. --%>
        <.button
          :if={@entity}
          variant="dismiss"
          size="sm"
          shape="circle"
          class="absolute top-3 right-3 z-20"
          phx-click={@on_close}
          aria-label="Close"
        >
          <.icon name="hero-x-mark-mini" class="size-5" />
        </.button>

        <%!-- Single scroll surface for the entire detail. Backdrop image
              and atmospheric scrim live inside the scroll container so
              they scroll with the content, mirroring HomeLive's
              page-level `.page-backdrop` treatment. The hero, metadata,
              and content list all flow as one continuous document. --%>
        <div
          :if={@entity}
          class="flex-1 min-h-0 overflow-y-auto overflow-x-hidden relative thin-scrollbar"
        >
          <div :if={@backdrop_url} class="modal-page-backdrop" aria-hidden="true">
            <img src={@backdrop_url} alt="" />
          </div>

          <%!-- Atmosphere + content share a positioning anchor that grows
                with the content, so the absolute atmosphere covers the full
                scroll height (not just the viewport-sized scroll padding box,
                which would scroll off and cut the dim partway down). --%>
          <div class="modal-page-content">
            <div class="modal-page-atmosphere" aria-hidden="true"></div>

            <div class="relative z-[2]">
              <DetailPanel.detail_panel
                entity={@entity}
                progress={@progress}
                resume={@resume}
                progress_records={@progress_records}
                expanded_seasons={@expanded_seasons}
                on_play={@on_play}
                on_close={@on_close}
                rematch_confirm={@rematch_confirm}
                detail_view={@detail_view}
                detail_files={@detail_files}
                delete_confirm={@delete_confirm}
                spoiler_free={@spoiler_free}
                tracking_status={@tracking_status}
                available={@available}
                tmdb_ready={@tmdb_ready}
              />
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
