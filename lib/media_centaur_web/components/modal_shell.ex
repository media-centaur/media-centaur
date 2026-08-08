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
  alias MediaCentaurWeb.Components.Detail.Logic
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

  attr :all_episode_details_open, :boolean,
    default: false,
    doc: "Forwarded to `DetailPanel.detail_panel/1`. List-level episode-details toggle."

  attr :on_play, :string, default: "play"
  attr :on_close, :string, default: "close_detail"
  attr :rematch_confirm, :boolean, default: false
  attr :detail_view, :atom, default: :main

  attr :cast_filter, :string,
    default: "",
    doc: "Forwarded to `DetailPanel.detail_panel/1`. Current Cast-view filter query."

  attr :cast_limit, :integer,
    default: nil,
    doc:
      "Forwarded to `DetailPanel.detail_panel/1`. How many cast matches the Cast view renders; `nil` falls back to one page."

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
      panel_class={
        if @entity && DetailPanel.scrollable_content?(@entity, @detail_view),
          do: "modal-panel--full"
      }
      data-detail-mode={@open && "modal"}
      data-detail-nested={@open && to_string(nested_view?(@entity, @detail_view))}
      data-nav-overlay={@open && "detail"}
    >
      <%!-- No close-X — backdrop click and Escape both close, and the
            URL preserves history so browser-back also works. --%>

      <%!-- Fixed cinematic stage (2026-08-05 sticky-orientation design):
              the backdrop pins to the panel, BEHIND the transparent
              scroll surface, so it never moves while the document —
              atmosphere scrim included — scrolls over it. The image
              extends under the reserved scrollbar gutter, so the rail
              blends into the picture instead of cutting it off. --%>
      <CinematicBackdrop.backdrop :if={@entity} backdrop_url={@backdrop_url} />
      <%!-- Atmosphere scrim is panel-fixed like the backdrop (2026-08-05
              instant-pin revision): the pinned orientation block's backing
              replicates it verbatim, and that replica only equals the real
              thing at every scroll depth if the real thing never moves.
              At rest this renders identically to the earlier
              scrolls-with-content seating (content coords == panel coords
              until you scroll); once scrolled, everything above the ramp
              hides behind the opaque backing anyway. --%>
      <div :if={@entity} class="modal-page-atmosphere z-0" aria-hidden="true"></div>
      <%!-- Single scroll surface for the entire detail document. Only the
              content (and its sheet) scrolls; backdrop and atmosphere
              stay put. .modal-detail-scroll owns the rail treatment:
              stable gutter (no re-flow when the scrollbar appears), track
              painted to the shim tone. See the app.css comment. --%>
      <div
        :if={@entity}
        id="detail-scrollport"
        phx-hook="DetailScrollGeometry"
        class="flex-1 min-h-0 overflow-y-auto overflow-x-hidden relative z-[1] modal-detail-scroll"
      >
        <div class="modal-page-content">
          <div class="relative z-[2]">
            <DetailPanel.detail_panel
              entity={@entity}
              progress={@progress}
              resume={@resume}
              progress_records={@progress_records}
              seasons_view={@seasons_view}
              expanded_seasons={@expanded_seasons}
              expanded_episode_details={@expanded_episode_details}
              all_episode_details_open={@all_episode_details_open}
              on_play={@on_play}
              on_close={@on_close}
              rematch_confirm={@rematch_confirm}
              detail_view={@detail_view}
              detail_files={@detail_files}
              cast_filter={@cast_filter}
              cast_limit={@cast_limit}
              delete_confirm={@delete_confirm}
              deleting={@deleting}
              spoiler_free={@spoiler_free}
              tracking_status={@tracking_status}
              available={@available}
              tmdb_ready={@tmdb_ready}
            />
          </div>
        </div>
      </div>
    </.modal>
    """
  end

  @doc """
  Whether the panel is showing something other than the entity's root view,
  which is what tells the input system that BACK returns *within* the modal
  rather than dismissing it.

  Answered here rather than in JS because the root view is entity-dependent:
  a title with no contents of its own (a movie with no extras) has no body
  tab and opens on Cast, which is its root. The client used to infer
  this by comparing the view name to `"main"`, which got that case wrong in
  both directions — BACK left focus trapped in an overlay the server had
  already dismissed.

  A closed modal (`entity: nil`) is never nested.
  """
  @spec nested_view?(map() | nil, atom()) :: boolean()
  def nested_view?(nil, _detail_view), do: false
  def nested_view?(entity, detail_view), do: detail_view != Logic.resolve_view(entity, :main)
end
