defmodule MediaCentaurWeb.Components.Detail.ManagePanel do
  @moduledoc """
  The Manage sheet — the detail modal's `:info` sub-view (the cog).

  Administration for one title: delete its files, rematch it, refresh its
  artwork, follow its external ids. The sheet is exactly two surfaces
  (2026-08-08 overhaul, `docs/plans/2026-08-08-manage-sheet-overhaul.md`):

  ## Toolbar card

  Every whole-title verb and the title's identity in one card, first, so
  nothing the user can *do* requires scrolling. Delete-all leads (the
  primary usage pattern is whole-title cleanup), Rematch and Refresh
  artwork sit at the right, and external ids + UUID form the card's quiet
  lower edge — they are all "identity of this title", not a scroll
  destination of their own.

  ## Folder ledger

  One collapsed disclosure row per folder: name, count, size, and a quiet
  Delete — scoped cleanup without expansion or arithmetic. Expanding
  reveals the file rows, sorted by filename (discovery order is
  effectively random and reads as disorder). Groups reuse the season
  accordion's exact TREE contract — `data-nav-group` around an
  `aria-expanded` head that is itself the `data-nav-item`, with the
  folder delete as a `data-nav-sub-item` inside it — so LEFT/RIGHT mean
  the same thing here as in the episode list (UIDR-019).

  ## Navigation: two sibling zones

  The sheet declares its own nav zones (the `:info` branch in
  `DetailPanel` adds none): the toolbar card is a `manage_tools` TOOLBAR
  — a horizontal strip navigates LEFT/RIGHT, and DOWN drops past it into
  the ledger instead of walking its buttons as vertical steps — and the
  ledger (with the playback bookkeeping under it) is the `manage_list`
  TREE. `manage_list` is deliberately NOT the episode list's
  `detail_list`: per-context cursor memory is keyed by context name, so
  sharing it let ledger activity overwrite the episode list's remembered
  position — returning to Episodes then entered at the ledger's index
  instead of the resume episode. Region edges live in `config.js`
  `overlays.detail`; the zones are siblings and must never nest.

  Small inventories (≤ #{6} files total — typical movies) auto-expand:
  a single file hidden behind a chevron is bookkeeping, not calm. The
  expanded set is host state (`expanded_file_groups` in `EntityModal`),
  `nil` meaning "the automatic default".

  ## Delete confirmation

  Confirmation is INLINE — first click arms `delete_confirm` for that
  target and the button flips its label; second click executes; any other
  delete button re-targets. There is no confirmation modal (deliberately
  killed: modal-on-modal noise is uglier than the in-place gesture).
  Delete affordances are quiet at rest but always visible — hover-gating
  would hide them from couch navigation, which cannot hover.

  The media-dir root never offers folder delete — deleting a watch root
  would be catastrophic.
  """

  use MediaCentaurWeb, :html

  import MediaCentaurWeb.LibraryFormatters, only: [format_human_duration: 1]
  import MediaCentaurWeb.LiveHelpers

  alias MediaCentaurWeb.Components.Detail.SubtitlesRow
  alias MediaCentaurWeb.Components.Detail.TrackOverrideBadge

  # Above this many files the ledger rests collapsed; at or below it,
  # every group opens. Six covers a movie + subtitles + a couple of
  # extras — the inventories where hiding the filenames costs more than
  # showing them.
  @auto_expand_threshold 6

  @doc_files "list of file-info maps (`%{file: KnownFile.t(), size: bytes | nil}`) built by `EntityModal.load_entity_files/1`."
  @doc_delete_confirm "pending inline-confirm target: `nil` | `:all` | `{:file, path}` | `{:folder, path}`."
  @doc_deleting "in-flight delete target (same sum type as `delete_confirm`). Set while the async deletion runs so the matching button shows \"Deleting…\" and all delete buttons disable."

  attr :entity, :map,
    required: true,
    doc:
      "`MediaCentaur.Library.EntityView`. Read for `:id`, `:url`, `:external_ids`, `:watched_files` (probed media info), and movie `:subtitle_tracks`."

  attr :files, :list, default: [], doc: @doc_files

  attr :files_status, :atom,
    values: [:loading, :loaded, :failed],
    default: :loaded,
    doc:
      "state of the load behind `files`. `:loading` and `:failed` render a status line in place of the ledger and hide Delete all — an empty list is only \"no files\" once the load has finished."

  attr :rematch_confirm, :boolean, default: false
  attr :delete_confirm, :any, default: nil, doc: @doc_delete_confirm
  attr :deleting, :any, default: nil, doc: @doc_deleting
  attr :tmdb_ready, :boolean, default: true

  attr :expanded_groups, :any,
    default: nil,
    doc:
      "`MapSet.t()` of expanded folder dirs, or `nil` for the automatic default (all expanded when the inventory is ≤ #{@auto_expand_threshold} files, else all collapsed). Owned by the host's `expanded_file_groups` assign; toggled via `toggle_file_group`."

  def manage_panel(assigns) do
    total_size = Enum.reduce(assigns.files, 0, fn %{size: size}, acc -> acc + (size || 0) end)
    file_count = length(assigns.files)

    external_ids =
      if is_list(assigns.entity.external_ids), do: assigns.entity.external_ids, else: []

    media_dirs = MapSet.new(MediaCentaur.Settings.Config.get(:media_dirs) || [])
    file_groups = build_file_groups(assigns.files, media_dirs)
    expanded_dirs = effective_expanded_dirs(file_groups, assigns.expanded_groups)

    subtitle_languages = subtitle_languages_for(assigns.entity)

    # Understood languages lead the subtitles row; the rest fold behind
    # the trailing-+ reveal. Read here (prod: SettingsCache) rather than
    # threaded through every modal host.
    understood_languages =
      if subtitle_languages == [],
        do: [],
        else: MediaCentaur.Playback.LanguagePolicy.load().understood_languages

    assigns =
      assigns
      |> assign(:total_size, total_size)
      |> assign(:file_count, file_count)
      |> assign(:external_ids, external_ids)
      |> assign(:file_groups, file_groups)
      |> assign(:expanded_dirs, expanded_dirs)
      |> assign(:media_info_by_path, media_info_by_path(assigns.entity))
      |> assign(:subtitle_languages, subtitle_languages)
      |> assign(:understood_languages, understood_languages)

    ~H"""
    <div class="pt-3 space-y-5">
      <%!-- The card is its own TOOLBAR nav region (`manage_tools`,
            config.js overlays.detail): a horizontal strip navigates
            LEFT/RIGHT, and DOWN drops past it into the ledger rather
            than walking Delete-all → Rematch → … as vertical steps.
            Sibling of the `detail_list` zone below — never nested. --%>
      <div
        class="glass-inset rounded-xl p-3 space-y-3"
        data-role="manage-toolbar"
        data-nav-zone="manage_tools"
      >
        <div class="flex flex-wrap items-center gap-2">
          <.button
            :if={@files != [] and @files_status == :loaded}
            variant="danger"
            size="sm"
            phx-click="delete_all_prompt"
            disabled={delete_in_flight?(@deleting)}
            data-nav-item
            tabindex="0"
            aria-label={delete_all_aria_label(@file_count)}
          >
            <.icon name="hero-trash-mini" class="size-4" />
            <%= case delete_gesture_state(:all, @deleting, @delete_confirm) do %>
              <% :deleting -> %>
                Deleting… {delete_all_label(@file_count)} ({format_file_size(@total_size)})
              <% :confirm -> %>
                Click again to confirm — {delete_all_label(@file_count)} ({format_file_size(
                  @total_size
                )})
              <% :idle -> %>
                {delete_all_label(@file_count)} ({format_file_size(@total_size)})
            <% end %>
          </.button>
          <.button
            :if={@delete_confirm == :all}
            variant="dismiss"
            size="sm"
            phx-click="delete_cancel"
            data-nav-item
            tabindex="0"
          >
            Cancel
          </.button>
          <span class="flex-1" />
          <.button
            :if={@tmdb_ready}
            variant={if @rematch_confirm, do: "danger", else: "risky"}
            size="sm"
            phx-click="rematch"
            phx-value-id={@entity.id}
            data-nav-item
            tabindex="0"
          >
            <.icon name="hero-arrow-path-mini" class="size-4" />
            {if @rematch_confirm, do: "Confirm?", else: "Rematch"}
          </.button>
          <.button
            :if={@tmdb_ready}
            variant="neutral"
            size="sm"
            phx-click="refresh_artwork"
            phx-value-id={@entity.id}
            data-nav-item
            tabindex="0"
          >
            <.icon name="hero-photo-mini" class="size-4" /> Refresh artwork
          </.button>
          <p :if={!@tmdb_ready} class="text-xs text-base-content/55">
            Rematch needs a working TMDB connection. Test it in <.link
              navigate="/settings?section=tmdb"
              class="link link-primary"
            >Settings</.link>.
          </p>
        </div>
        <%!-- Identity edge: external ids + UUID share the card's quiet
              last line — all "which title is this", none worth a section. --%>
        <div class="flex flex-wrap items-baseline gap-x-4 gap-y-1 text-xs">
          <.external_id_link :for={ext_id <- @external_ids} ext_id={ext_id} entity_url={@entity.url} />
          <span class="ml-auto flex items-baseline gap-1.5 text-base-content/55">
            <.icon name="hero-finger-print-mini" class="size-3 self-center" />
            <span class="font-mono select-all">{@entity.id}</span>
          </span>
        </div>
      </div>

      <div data-nav-zone="manage_list" class="space-y-5">
        <p
          :if={@files_status == :loading}
          class="text-xs text-base-content/55"
          data-role="files-status"
        >
          Reading files…
        </p>
        <p :if={@files_status == :failed} class="text-xs text-error/80" data-role="files-status">
          Couldn't read this entry's files. Check the console for details.
        </p>
        <div :if={@files != [] and @files_status == :loaded}>
          <div class="flex items-center justify-between mb-2">
            <span class="text-xs font-medium text-base-content/55 uppercase tracking-wide">
              Files
            </span>
            <span class="text-xs text-base-content/55">
              {file_summary(@file_count, @total_size)}
            </span>
          </div>
          <div class="space-y-1">
            <.file_group
              :for={group <- @file_groups}
              group={group}
              expanded={MapSet.member?(@expanded_dirs, group.dir)}
              media_info_by_path={@media_info_by_path}
              delete_confirm={@delete_confirm}
              deleting={@deleting}
            />
          </div>
        </div>

        <%!-- Playback bookkeeping the files carry: detected subtitle
              languages (movies) and the per-entity remembered track
              override. Administration, not show information. --%>
        <SubtitlesRow.subtitles_row
          languages={@subtitle_languages}
          understood={@understood_languages}
        />
        <TrackOverrideBadge.track_override_badge entity={@entity} />
      </div>
    </div>
    """
  end

  attr :group, :map,
    required: true,
    doc: "one `build_file_groups/2` entry — `%{dir, name, files, is_media_dir}`."

  attr :expanded, :boolean, required: true

  attr :media_info_by_path, :map,
    required: true,
    doc:
      "`%{file_path => WatchedFile.media_info()}` — probed facts keyed by path, joined onto file rows by their shared path identity (see `media_info_by_path/1`)."

  attr :delete_confirm, :any, default: nil, doc: @doc_delete_confirm
  attr :deleting, :any, default: nil, doc: @doc_deleting

  # A folder as one disclosure row. Same DOM contract as the season
  # accordion (`data-nav-group` + `aria-expanded` head), so TREE
  # navigation needs no new rules here. The head is a clickable div —
  # not a button — because the folder delete nests inside it as a
  # `data-nav-sub-item` (RIGHT from the head reaches it; a click on it
  # wins over the head's toggle because LiveView dispatches to the
  # closest `phx-click`). The id keeps morphdom from rebuilding the head
  # across the toggle patch, which would drop focus.
  defp file_group(assigns) do
    group_size = Enum.reduce(assigns.group.files, 0, fn %{size: size}, acc -> acc + (size || 0) end)

    assigns = assign(assigns, :group_size, group_size)

    ~H"""
    <div data-nav-group id={"file-group-#{:erlang.phash2(@group.dir)}"}>
      <div
        data-role="file-group-head"
        role="button"
        phx-click="toggle_file_group"
        phx-value-dir={@group.dir}
        aria-expanded={to_string(@expanded)}
        data-nav-item
        tabindex="0"
        class="flex items-center gap-2 w-full px-1 py-1.5 rounded cursor-pointer text-sm text-base-content/70 hover:text-base-content hover:bg-base-content/5"
        title={@group.dir}
      >
        <.icon
          name={if @expanded, do: "hero-chevron-down-mini", else: "hero-chevron-right-mini"}
          class="size-4 flex-shrink-0"
        />
        <.icon name="hero-folder-mini" class="size-3.5 text-base-content/40 flex-shrink-0" />
        <span class="font-medium truncate">{@group.name}</span>
        <span class="flex-1" />
        <span class="text-xs text-base-content/55 tabular-nums flex-shrink-0">
          {file_summary(length(@group.files), @group_size)}
        </span>
        <.button
          :if={!@group.is_media_dir}
          variant="destructive_inline"
          size="xs"
          disabled={delete_in_flight?(@deleting)}
          class={[
            "flex-shrink-0",
            if(@delete_confirm == {:folder, @group.dir},
              do: "text-error font-medium",
              else: "text-error/60 hover:text-error"
            )
          ]}
          phx-click="delete_folder_prompt"
          phx-value-path={@group.dir}
          phx-value-count={length(@group.files)}
          data-nav-sub-item
        >
          <.icon name="hero-trash-mini" class="size-3.5" />
          <%= case delete_gesture_state({:folder, @group.dir}, @deleting, @delete_confirm) do %>
            <% :deleting -> %>
              Deleting…
            <% :confirm -> %>
              Click again to confirm
            <% :idle -> %>
              Delete
          <% end %>
        </.button>
      </div>
      <div :if={@expanded} class="mt-1 ml-6 space-y-1.5">
        <.file_row
          :for={file_info <- @group.files}
          file_info={file_info}
          media_info={@media_info_by_path[file_info.file.file_path]}
          delete_confirm={@delete_confirm}
          deleting={@deleting}
        />
      </div>
    </div>
    """
  end

  attr :file_info, :map, required: true, doc: "single file-info map — see `manage_panel/1`'s `:files`."

  attr :media_info, :any,
    default: nil,
    doc:
      "probed `MediaCentaur.Library.Views.DetailItem.WatchedFile.media_info()` for this file, or `nil` when unprobed. Rendered as the file's own claims (container title + measured tech line) next to the filename-parsed quality badges."

  attr :delete_confirm, :any,
    default: nil,
    doc:
      "current pending-delete target — `{:file, path}` flips this row's trash button into confirm state."

  attr :deleting, :any, default: nil, doc: @doc_deleting

  defp file_row(assigns) do
    file = assigns.file_info.file
    size = assigns.file_info.size
    absent = is_nil(size)
    filename = Path.basename(file.file_path)
    badges = parse_quality_badges(filename)
    added_at = Map.get(file, :inserted_at)
    gesture = delete_gesture_state({:file, file.file_path}, assigns.deleting, assigns.delete_confirm)
    tech_line = if assigns.media_info, do: file_tech_line(assigns.media_info), else: ""

    assigns =
      assigns
      |> assign(:file_id, file.id)
      |> assign(:file_path, file.file_path)
      |> assign(:filename, filename)
      |> assign(:size, size)
      |> assign(:absent, absent)
      |> assign(:badges, badges)
      |> assign(:added_at, added_at)
      |> assign(:gesture, gesture)
      |> assign(:is_pending, gesture == :confirm)
      |> assign(:is_deleting, gesture == :deleting)
      |> assign(:delete_in_flight, delete_in_flight?(assigns.deleting))
      |> assign(:tech_line, tech_line)

    ~H"""
    <div
      id={"manage-file-#{@file_id}"}
      data-role="manage-file-row"
      class={[
        "text-sm rounded p-2",
        @absent && "opacity-60",
        if(@is_pending or @is_deleting,
          do: "bg-error/15 ring-1 ring-error/40",
          else: "bg-base-content/5"
        )
      ]}
    >
      <div class="flex items-center gap-2">
        <.icon
          name={if @absent, do: "hero-exclamation-triangle-mini", else: "hero-document-mini"}
          class={"size-3.5 flex-shrink-0 #{if @absent, do: "text-warning", else: "text-base-content/40"}"}
        />
        <span class="truncate font-mono text-xs text-base-content/80" title={@file_path}>
          {@filename}
        </span>
        <span :if={@size} class="text-xs text-base-content/55 flex-shrink-0 ml-auto">
          {format_file_size(@size)}
        </span>
        <span :if={@absent} class="text-xs text-warning flex-shrink-0">absent</span>
        <.button
          variant="destructive_inline"
          size="xs"
          disabled={@delete_in_flight}
          class={[
            "min-h-0 flex-shrink-0",
            if(@is_pending or @is_deleting,
              do: "px-2 text-error font-medium",
              else: "size-6 p-0 text-error/60 hover:text-error"
            )
          ]}
          phx-click="delete_file_prompt"
          phx-value-path={@file_path}
          aria-label={if @is_pending, do: "Click again to confirm delete", else: "Delete file"}
          data-nav-item
          tabindex="0"
        >
          <.icon name="hero-trash-mini" class="size-3.5" />
          <span :if={@is_deleting}>Deleting…</span>
          <span :if={@is_pending}>Click to confirm</span>
        </.button>
      </div>
      <div
        :if={@badges != [] || @added_at}
        class="mt-1 ml-5 flex items-center gap-1.5 text-xs text-base-content/55"
      >
        <%!-- Highlight HDR (a quality users actively care about) with the
              info-blue tint; everything else stays a quiet ghost chip. --%>
        <.badge
          :for={badge <- @badges}
          variant={if badge == "HDR", do: "info", else: "ghost"}
          size="xs"
        >
          {badge}
        </.badge>
        <span :if={@added_at} class="ml-auto">added {time_ago(@added_at)}</span>
      </div>
      <%!-- The file's own claims, probed from the container — measured
            facts next to the filename-parsed badges above, so a renamed
            fake release (original container title, disagreeing duration)
            is visible right on the row. Display-only, no judgement. --%>
      <div :if={@media_info} class="mt-1 ml-5 space-y-0.5 text-xs">
        <div :if={@media_info.container_title} class="flex items-baseline gap-2 min-w-0">
          <span class="uppercase tracking-wider text-base-content/55 shrink-0">
            Container title
          </span>
          <span class="truncate text-base-content/60" title={@media_info.container_title}>
            {@media_info.container_title}
          </span>
        </div>
        <div :if={@tech_line != ""} class="text-base-content/55">
          {@tech_line}
        </div>
      </div>
    </div>
    """
  end

  attr :ext_id, :map, required: true, doc: "`MediaCentaur.Library.ExternalId.t()`"
  attr :entity_url, :string, default: nil

  defp external_id_link(assigns) do
    url = external_id_url(assigns.ext_id.source, assigns.ext_id.external_id, assigns.entity_url)
    label = external_id_label(assigns.ext_id.source)
    assigns = assigns |> assign(:url, url) |> assign(:label, label)

    ~H"""
    <span class="flex items-baseline gap-1.5">
      <span class="text-base-content/55 uppercase tracking-wide text-[0.65rem]">{@label}</span>
      <%= if @url do %>
        <a
          href={@url}
          target="_blank"
          rel="noopener"
          class="inline-flex items-baseline gap-1 link link-primary font-mono"
          data-nav-item
          tabindex="0"
        >
          {@ext_id.external_id}
          <.icon name="hero-arrow-top-right-on-square-mini" class="size-3 self-center" />
        </a>
      <% else %>
        <span class="text-base-content/70 font-mono">{@ext_id.external_id}</span>
      <% end %>
    </span>
    """
  end

  defp external_id_url("tmdb", _id, entity_url) when is_binary(entity_url), do: entity_url
  defp external_id_url("imdb", id, _), do: "https://www.imdb.com/title/#{id}/"
  defp external_id_url("tvdb", id, _), do: "https://www.thetvdb.com/dereferrer/series/#{id}"
  defp external_id_url(_, _, _), do: nil

  defp external_id_label("tmdb"), do: "TMDB"
  defp external_id_label("imdb"), do: "IMDb"
  defp external_id_label("tvdb"), do: "TVDB"
  defp external_id_label(source) when is_binary(source), do: String.upcase(source)
  defp external_id_label(_), do: "—"

  # --- Pure helpers (public for unit tests, ADR-030) ---

  @doc """
  Groups watched files by directory. Groups sort by directory path
  (filesystem order — never by size); files within a group sort by
  filename, because discovery order is effectively random and reads as
  disorder. Returns a list of `%{dir, name, files, is_media_dir}` maps.
  """
  def build_file_groups(files, media_dirs) do
    files
    |> Enum.group_by(fn %{file: file} -> Path.dirname(file.file_path) end)
    |> Enum.sort_by(fn {dir, _files} -> dir end)
    |> Enum.map(fn {dir, dir_files} ->
      %{
        dir: dir,
        name: Path.basename(dir),
        files: Enum.sort_by(dir_files, fn %{file: file} -> Path.basename(file.file_path) end),
        is_media_dir: dir in media_dirs
      }
    end)
  end

  @doc """
  The set of folder dirs whose groups render expanded. An explicit
  `MapSet` (host state, after the user toggled something) passes
  through; `nil` computes the automatic default — everything expanded
  when the whole inventory is at most #{@auto_expand_threshold} files,
  everything collapsed above that.
  """
  def effective_expanded_dirs(file_groups, nil) do
    total = Enum.reduce(file_groups, 0, fn group, acc -> acc + length(group.files) end)

    if total > 0 and total <= @auto_expand_threshold,
      do: MapSet.new(file_groups, & &1.dir),
      else: MapSet.new()
  end

  def effective_expanded_dirs(_file_groups, %MapSet{} = expanded), do: expanded

  @doc """
  Builds the grouped payload for the entity-wide delete.
  Returns `%{file_groups, total_size, file_count}` where each group has
  `%{dir, name, is_media_dir, files}` with files as `%{path, name, size}` maps.
  """
  def build_delete_all_payload(detail_files, media_dirs) do
    # Single pass: group by directory and accumulate the total size.
    {groups_by_dir, total_size, file_count} =
      Enum.reduce(detail_files, {%{}, 0, 0}, fn %{file: file, size: size}, {acc, total, count} ->
        dir = Path.dirname(file.file_path)

        entry = %{
          path: file.file_path,
          name: Path.basename(file.file_path),
          size: size
        }

        {Map.update(acc, dir, [entry], &[entry | &1]), total + (size || 0), count + 1}
      end)

    file_groups =
      groups_by_dir
      |> Enum.sort_by(fn {dir, _files} -> dir end)
      |> Enum.map(fn {dir, files} ->
        %{
          dir: dir,
          name: Path.basename(dir),
          is_media_dir: dir in media_dirs,
          files: Enum.reverse(files)
        }
      end)

    %{file_groups: file_groups, total_size: total_size, file_count: file_count}
  end

  def file_summary(count, total_size) do
    size_str = format_file_size(total_size)
    "#{count} #{if count == 1, do: "file", else: "files"}, #{size_str}"
  end

  @doc """
  Label for the prominent entity-wide delete button. Single-file
  entities read "Delete this file" because "Delete all" reads as
  awkward when there's only one.
  """
  def delete_all_label(1), do: "Delete this file"
  def delete_all_label(_), do: "Delete all files"

  defp delete_all_aria_label(1), do: "Delete the file for this entry"
  defp delete_all_aria_label(_), do: "Delete all files for this entry"

  @doc """
  One compact " · "-joined line of a file's probed technical facts, e.g.
  `"1h 41m · HEVC · 3840×2160 · DTS-HD MA 5.1"`, for the file rows.
  Empty string when nothing was probed. Public for unit tests (ADR-030).
  """
  @spec file_tech_line(MediaCentaur.Library.Views.DetailItem.WatchedFile.media_info()) ::
          String.t()
  def file_tech_line(media_info) do
    [
      tech_duration(media_info.duration_seconds),
      media_info.video_codec,
      tech_resolution(media_info),
      media_info.audio_summary
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  defp tech_duration(seconds) when is_integer(seconds), do: format_human_duration(seconds)
  defp tech_duration(_seconds), do: nil

  defp tech_resolution(%{width: width, height: height}) when is_integer(width) and is_integer(height),
    do: "#{width}×#{height}"

  defp tech_resolution(_media_info), do: nil

  # Probed media_info keyed by file path, for joining the projection's
  # `watched_files` (which carry the ffprobe result) onto the Manage
  # view's async-stat'd file list (which carries size + presence). The
  # two lists describe the same files from different concerns; the path
  # is their shared identity.
  defp media_info_by_path(entity) do
    for %{path: path, media_info: media_info} <- Map.get(entity, :watched_files) || [],
        media_info != nil,
        into: %{},
        do: {path, media_info}
  end

  # Movies are the only type with detected subtitles for v1. Series'
  # episodes each carry their own WatchedFile with its own tracks;
  # aggregating across episodes needs a different display story
  # (per-season? show-wide?). Skip non-movies entirely so the row
  # never renders for them. Reads the projection's already-loaded
  # tracks — never re-queried.
  defp subtitle_languages_for(%{type: :movie, subtitle_tracks: tracks}) when is_list(tracks),
    do: MediaCentaur.Subtitles.aggregate_track_languages(tracks)

  defp subtitle_languages_for(_entity), do: []

  @doc """
  Extracts a small, ordered list of quality/format badges from a release filename.

  Returns at most one badge per category: resolution, HDR, source, codec.
  Order is fixed (resolution → HDR → source → codec) so the row reads the same
  shape across files. Unknown filenames return `[]` — the row simply hides the
  badge strip.
  """
  def parse_quality_badges(filename) when is_binary(filename) do
    down = String.downcase(filename)

    Enum.reject(
      [resolution_badge(down), hdr_badge(down), source_badge(down), codec_badge(down)],
      &is_nil/1
    )
  end

  def parse_quality_badges(_), do: []

  defp resolution_badge(down) do
    cond do
      String.contains?(down, "2160p") or String.contains?(down, "4k") or
          String.contains?(down, "uhd") ->
        "4K"

      String.contains?(down, "1080p") ->
        "1080p"

      String.contains?(down, "720p") ->
        "720p"

      String.contains?(down, "480p") ->
        "480p"

      true ->
        nil
    end
  end

  defp hdr_badge(down) do
    cond do
      String.contains?(down, "dolby.vision") or String.contains?(down, "dolbyvision") or
          String.contains?(down, ".dv.") ->
        "DV"

      String.contains?(down, "hdr") ->
        "HDR"

      true ->
        nil
    end
  end

  defp source_badge(down) do
    cond do
      String.contains?(down, "remux") ->
        "REMUX"

      String.contains?(down, "bluray") or String.contains?(down, "blu-ray") or
          String.contains?(down, "bdrip") ->
        "BluRay"

      String.contains?(down, "web-dl") or String.contains?(down, "webrip") or
        String.contains?(down, ".web.") or String.contains?(down, "-web-") ->
        "WEB"

      String.contains?(down, "hdtv") ->
        "HDTV"

      String.contains?(down, "dvdrip") ->
        "DVDRip"

      true ->
        nil
    end
  end

  defp codec_badge(down) do
    cond do
      String.contains?(down, "h265") or String.contains?(down, "h.265") or
        String.contains?(down, "hevc") or String.contains?(down, "x265") ->
        "H265"

      String.contains?(down, "h264") or String.contains?(down, "h.264") or
          String.contains?(down, "x264") ->
        "H264"

      String.contains?(down, "av1") ->
        "AV1"

      true ->
        nil
    end
  end

  def format_file_size(bytes) when bytes >= 1_073_741_824 do
    "#{Float.round(bytes / 1_073_741_824, 1)} GB"
  end

  def format_file_size(bytes) when bytes >= 1_048_576 do
    "#{Float.round(bytes / 1_048_576, 1)} MB"
  end

  def format_file_size(bytes) when bytes >= 1024 do
    "#{Float.round(bytes / 1024, 1)} KB"
  end

  def format_file_size(bytes), do: "#{bytes} B"
end
