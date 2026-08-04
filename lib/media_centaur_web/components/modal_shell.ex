defmodule MediaCentaurWeb.Components.ModalShell do
  @moduledoc """
  Centered overlay shell for the DetailPanel.

  Always present in the DOM so the browser keeps the `backdrop-filter`
  compositing layer warm. Toggled via `data-state="open"/"closed"` +
  CSS visibility/opacity — no first-frame blur jank on open.
  """

  use MediaCentaurWeb, :html

  import MediaCentaurWeb.LiveHelpers, only: [image_url: 2]

  alias MediaCentaurWeb.Components.Detail.CinematicBackdrop
  alias MediaCentaurWeb.Components.DetailPanel

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
    doc: "`MediaCentaur.Library.ProgressSummary.t() | nil` — produced by `Library.Browser`."

  attr :resume, :map,
    default: nil,
    doc:
      "resume target map `%{kind, season, episode, ...} | nil` describing where playback would resume; see `LibraryProgress.resume_target_for/1` for the producer."

  attr :progress_records, :list,
    default: [],
    doc: "list of `MediaCentaur.Library.WatchProgress.t()` rows preloaded from the entity."

  attr :expanded_seasons, MapSet, default: nil

  attr :expanded_episode_details, MapSet,
    default: nil,
    doc:
      "Forwarded to `DetailPanel.detail_panel/1`. `{season_number, episode_number}` keys of episode rows whose synopsis/thumbnail disclosure is open."

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

  attr :deleting, :any,
    default: nil,
    doc: "Forwarded to `DetailPanel.detail_panel/1`. In-flight delete target — see its `:deleting` attr."

  attr :spoiler_free, :boolean, default: false
  attr :tracking_status, :atom, default: nil
  attr :available, :boolean, default: true
  attr :tmdb_ready, :boolean, default: true

  attr :seasons_view, :list,
    default: nil,
    doc: "Forwarded to `DetailPanel.detail_panel/1`. See its `:seasons_view` attr."

  def modal_shell(assigns) do
    backdrop_url =
      if assigns.entity && assigns.available do
        image_url(assigns.entity, "backdrop") || image_url(assigns.entity, "poster")
      end

    assigns = assign(assigns, :backdrop_url, backdrop_url)

    ~H"""
    <.modal
      id="detail-modal"
      open={@open}
      dismiss={:ephemeral}
      on_close={@on_close}
      data-detail-mode={@open && "modal"}
      data-detail-view={@open && to_string(@detail_view)}
    >
      <%!-- No close-X — backdrop click and Escape both close, and the
            URL preserves history so browser-back also works. --%>

      <%!-- Single scroll surface for the entire detail. Backdrop image
              and atmospheric scrim live inside the scroll container so
              they scroll with the content, mirroring HomeLive's
              page-level `.page-backdrop` treatment. The hero, metadata,
              and content list all flow as one continuous document. --%>
      <%!-- The backdrop image and atmospheric scrim live inside this scroll
              container (its positioning context) so they scroll with the
              content, mirroring HomeLive's page-level `.page-backdrop`. The
              hero, metadata, and content list flow as one document. --%>
      <div
        :if={@entity}
        class="flex-1 min-h-0 overflow-y-auto overflow-x-hidden relative thin-scrollbar"
      >
        <CinematicBackdrop.cinematic_backdrop backdrop_url={@backdrop_url}>
          <DetailPanel.detail_panel
            entity={@entity}
            progress={@progress}
            resume={@resume}
            progress_records={@progress_records}
            seasons_view={@seasons_view}
            expanded_seasons={@expanded_seasons}
            expanded_episode_details={@expanded_episode_details}
            on_play={@on_play}
            on_close={@on_close}
            rematch_confirm={@rematch_confirm}
            detail_view={@detail_view}
            detail_files={@detail_files}
            delete_confirm={@delete_confirm}
            deleting={@deleting}
            spoiler_free={@spoiler_free}
            tracking_status={@tracking_status}
            available={@available}
            tmdb_ready={@tmdb_ready}
          />
        </CinematicBackdrop.cinematic_backdrop>
      </div>
    </.modal>
    """
  end
end
