defmodule MediaCentaurWeb.Components.ReviewQueue do
  @moduledoc """
  The bulk list of Review → Identity (campaign `review-bulk-match`): one
  flat list of review items a person ticks, and the action bar that acts
  on what is ticked.

    * `queue_header/1` — the column names, and the tick for every row shown.
    * `queue_divider/1` — where the parsed title changes; ticking it ticks
      the rows beneath it. It decides nothing.
    * `queue_item/1` — one review item: its tick, how it was named, its
      file, the best guess and why it waits. The whole row is the control.
    * `match_bar/1` — the action bar: the title search, its results, and
      the actions for the ticked rows.
    * `match_result/1` — one search result; pressing it matches every
      ticked row to that title.

  The rows share one column grid (`@columns`) so the header, dividers
  and items line up. For keyboard and gamepad, the rows are the
  `review-rows` zone (a TREE: UP and DOWN walk it, RIGHT goes to the bar),
  the bar's controls the `review-bar` zone and the results the
  `review-results` shelf (`config.js`).
  """
  use MediaCentaurWeb, :html

  import MediaCentaurWeb.Components.Settings, only: [settings_input: 1, settings_select: 1]
  import MediaCentaurWeb.ReviewHelpers

  alias MediaCentaurWeb.Components.Checkbox
  alias MediaCentaurWeb.LiveHelpers

  @columns "grid grid-cols-[1.75rem_minmax(9rem,15rem)_4.5rem_minmax(0,1fr)_minmax(9rem,14rem)_8.5rem] items-center gap-x-3"

  attr :state, :atom, required: true, values: [:checked, :indeterminate, :unchecked]
  attr :selectable, :boolean, default: true, doc: "false for the importing view: nothing to act on."
  attr :rest, :global, doc: "the tick-all event (`phx-click`)."

  @doc "The column names over the list; its tick ticks every row shown."
  def queue_header(assigns) do
    assigns = assign(assigns, :columns, @columns)

    ~H"""
    <div class={[
      @columns,
      "px-3 py-2 border-b border-base-content/8 text-[0.625rem] font-semibold uppercase tracking-[0.06em] text-base-content/55"
    ]}>
      <Checkbox.checkbox :if={@selectable} state={@state} aria-label="Tick every row shown" {@rest} />
      <span :if={!@selectable}></span>
      <span>Parsed title</span>
      <span>Episode</span>
      <span>File</span>
      <span>Best guess</span>
      <span>Why it waits</span>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :label, :string, required: true, doc: "the parsed title, with its year when it has one."
  attr :count, :integer, required: true
  attr :state, :atom, required: true, values: [:checked, :indeterminate, :unchecked]
  attr :selectable, :boolean, default: true
  attr :rest, :global, doc: "the tick-block event (`phx-click`) and its `phx-value-*`."

  @doc "Where the parsed title changes: the title and its file count; pressing it ticks the block."
  def queue_divider(assigns) do
    assigns = assign(assigns, :columns, @columns)

    ~H"""
    <button
      :if={@selectable}
      type="button"
      id={@id}
      class={[
        @columns,
        "w-full text-left px-3 pt-4 pb-1.5 cursor-pointer rounded-md hover:bg-base-content/4"
      ]}
      role="checkbox"
      aria-checked={aria_checked(@state)}
      data-nav-item
      tabindex="0"
      {@rest}
    >
      <Checkbox.checkbox_mark state={@state} />
      <span class="col-span-5 truncate text-sm">
        <span class="font-semibold">{@label}</span>
        <span class="text-base-content/55 ml-2">{file_count(@count)}</span>
      </span>
    </button>
    <div :if={!@selectable} id={@id} class={[@columns, "px-3 pt-4 pb-1.5"]}>
      <span></span>
      <span class="col-span-5 truncate text-sm">
        <span class="font-semibold">{@label}</span>
        <span class="text-base-content/55 ml-2">{file_count(@count)}</span>
      </span>
    </div>
    """
  end

  attr :id, :string, required: true

  attr :file, :map,
    required: true,
    doc:
      "a `Review.PendingFile`: parsed title/season/episode, `file_path`, `media_directory`, the best guess (`tmdb_id`, `match_title`, `match_year`, `match_poster_path`, `confidence`, `candidates`), the title a contradicted grab wanted (`wanted_title`), `status`, `error_message`."

  attr :ticked, :boolean, default: false
  attr :selectable, :boolean, default: true, doc: "false for an importing item: no tick, not a control."
  attr :rest, :global, doc: "the tick event (`phx-click`) and its `phx-value-*`."

  @doc "One review item; the whole row ticks it."
  def queue_item(assigns) do
    reason = MediaCentaur.Review.reason(assigns.file)

    assigns =
      assigns
      |> assign(:columns, @columns)
      |> assign(:reason, if(assigns.file.status == :dismissed, do: :dismissed, else: reason))
      |> assign(:path, relative_path(assigns.file))

    ~H"""
    <button
      :if={@selectable}
      type="button"
      id={@id}
      class={[
        @columns,
        "w-full text-left px-3 py-1.5 cursor-pointer rounded-md text-sm hover:bg-base-content/4",
        @ticked && "bg-primary/10 hover:bg-primary/14"
      ]}
      role="checkbox"
      aria-checked={to_string(@ticked)}
      data-nav-item
      tabindex="0"
      {@rest}
    >
      <Checkbox.checkbox_mark state={if @ticked, do: :checked, else: :unchecked} />
      <.item_cells file={@file} reason={@reason} path={@path} />
    </button>
    <div :if={!@selectable} id={@id} class={[@columns, "px-3 py-1.5 text-sm"]}>
      <span></span>
      <.item_cells file={@file} reason={@reason} path={@path} />
    </div>
    """
  end

  attr :file, :map, required: true, doc: "the `Review.PendingFile` the row draws (see `queue_item/1`)."
  attr :reason, :atom, required: true
  attr :path, :string, required: true

  defp item_cells(assigns) do
    ~H"""
    <span class="truncate">
      {@file.parsed_title || "Unknown"}
      <span :if={@file.parsed_year} class="text-base-content/55">
        ({@file.parsed_year})
      </span>
    </span>
    <span class="font-mono text-xs text-base-content/70">{episode_label(@file)}</span>
    <span class="font-mono text-xs text-base-content/60 truncate-left" data-tip={@path}>
      <bdo dir="ltr">{Path.basename(@file.file_path)}</bdo>
    </span>
    <span class="flex items-center gap-2 min-w-0">
      <%= if @file.tmdb_id && @file.match_title do %>
        <img
          :if={@file.match_poster_path}
          src={LiveHelpers.tmdb_cdn_url(@file.match_poster_path, :w92)}
          alt=""
          loading="eager"
          decoding="sync"
          class="w-5 h-[30px] rounded-sm object-cover shrink-0"
        />
        <span class="truncate">
          {@file.match_title}<span :if={@file.match_year} class="text-base-content/55"> · {@file.match_year}</span>
        </span>
      <% else %>
        <span class="text-base-content/55">—</span>
      <% end %>
    </span>
    <span
      class={["truncate text-xs", reason_class(@reason)]}
      data-tip={@reason == :not_added && @file.error_message}
    >
      {reason_text(@reason, @file)}
    </span>
    """
  end

  attr :count, :integer, required: true, doc: "how many rows are ticked."
  attr :status, :atom, required: true, values: [:waiting, :dismissed], doc: "the list's view."
  attr :query, :string, required: true
  attr :type, :atom, required: true, values: [:tv, :movie]
  attr :searching, :boolean, default: false
  attr :searched, :boolean, default: false, doc: "a search has answered for the current query."
  attr :results, :list, default: [], doc: "`Review.Search.tmdb/2` results."
  attr :tmdb_ready, :boolean, default: true, doc: "TMDB is configured; without it there is no search."

  attr :accept_guesses, :boolean,
    default: false,
    doc: "every ticked row has a best guess — offer to accept each under its own."

  attr :dismiss_armed, :boolean, default: false
  attr :delete_armed, :boolean, default: false
  attr :deleting, :boolean, default: false

  attr :delete_label, :string,
    default: nil,
    doc:
      "what the armed Delete removes, from the resolved plan; nil while it resolves (Delete disabled)."

  @doc """
  The action bar for the ticked rows. A waiting view searches TMDB for
  the title — the search starts from the first ticked row's parsed title —
  and offers its results, Accept best guess when every ticked row has one,
  Dismiss and Delete; the dismissed view offers Restore and Delete.
  """
  def match_bar(assigns) do
    ~H"""
    <section
      id="review-match-bar"
      class="glass-surface rounded-xl p-3 space-y-3 border !border-primary/40 shrink-0"
      aria-label="Ticked files"
    >
      <div class="flex flex-wrap items-center gap-2" data-nav-zone="review-bar">
        <span class="text-sm font-semibold mr-1">{file_count(@count)} ticked</span>
        <form
          :if={@status == :waiting && @tmdb_ready}
          id="review-search-form"
          phx-submit="search"
          phx-change="update_search"
          class="flex items-center gap-2 flex-1 min-w-[22rem]"
        >
          <span class="text-sm text-base-content/60 shrink-0">Which title?</span>
          <.settings_input
            name="query"
            value={@query}
            phx-debounce="400"
            aria-label="Title to search TMDB for"
            placeholder={if @type == :tv, do: "Show name", else: "Movie title"}
            class="min-w-0 flex-1"
          />
          <.settings_select
            name="type"
            aria_label="Type"
            options={[{"tv", "TV"}, {"movie", "Movie"}]}
            selected={to_string(@type)}
          />
          <.button
            type="submit"
            variant="info"
            size="sm"
            disabled={@searching}
            data-nav-item
            tabindex="0"
          >
            {if @searching, do: "Searching…", else: "Search"}
          </.button>
        </form>
        <span :if={@status == :dismissed} class="flex-1"></span>
        <.button
          :if={@status == :waiting && @accept_guesses}
          variant="action"
          size="sm"
          phx-click="accept_guesses"
          data-nav-item
          tabindex="0"
        >
          Accept best {if @count == 1, do: "guess", else: "guesses"}
        </.button>
        <.armed_button
          :if={@status == :waiting}
          armed={@dismiss_armed}
          event="dismiss"
          armed_label={"Press again to dismiss #{file_count(@count)}"}
          variant="dismiss"
        >
          Dismiss
        </.armed_button>
        <.button
          :if={@status == :dismissed}
          variant="secondary"
          size="sm"
          phx-click="restore"
          data-nav-item
          tabindex="0"
        >
          Restore
        </.button>
        <.armed_button
          armed={@delete_armed}
          event="delete"
          armed_label={@delete_label || "Press again to delete"}
          busy={@deleting}
          busy_label="Deleting…"
          disabled={is_nil(@delete_label)}
        >
          Delete
        </.armed_button>
        <.button variant="dismiss" size="sm" phx-click="clear_selection" data-nav-item tabindex="0">
          Clear
        </.button>
      </div>
      <div
        :if={@status == :waiting && @tmdb_ready}
        class="grid grid-cols-[repeat(auto-fill,minmax(15rem,1fr))] gap-2"
        data-nav-zone="review-results"
      >
        <.match_result :for={result <- @results} result={result} count={@count} />
        <p
          :if={@results == [] && @searched && !@searching}
          class="col-span-full text-sm text-base-content/60 py-1"
        >
          TMDB has nothing for “{@query}”. Try fewer words, or switch between TV and Movie.
        </p>
      </div>
      <p :if={@status == :waiting && !@tmdb_ready} class="text-sm text-base-content/60">
        Set up TMDB in Settings to search for titles.
      </p>
    </section>
    """
  end

  attr :result, :map,
    required: true,
    doc: "`%{tmdb_id, tmdb_type, title, year, overview, poster_path}` from `Review.Search.tmdb/2`."

  attr :count, :integer, required: true, doc: "how many rows pressing it matches."

  @doc "One search result; pressing it matches every ticked row to this title."
  def match_result(assigns) do
    ~H"""
    <button
      type="button"
      id={"review-result-#{@result.tmdb_type}-#{@result.tmdb_id}"}
      class="flex gap-3 items-center p-2 rounded-lg text-left cursor-pointer bg-base-content/4 hover:bg-primary/12"
      phx-click="match"
      phx-value-tmdb-id={@result.tmdb_id}
      phx-value-tmdb-type={@result.tmdb_type}
      phx-value-title={@result.title}
      phx-value-year={@result.year}
      phx-value-poster-path={@result.poster_path}
      aria-label={"Match #{file_count(@count)} to #{@result.title}"}
      data-nav-item
      tabindex="0"
    >
      <img
        :if={@result.poster_path}
        src={LiveHelpers.tmdb_cdn_url(@result.poster_path, :w92)}
        alt=""
        loading="eager"
        decoding="sync"
        class="w-[34px] h-[51px] rounded object-cover shrink-0"
      />
      <span
        :if={!@result.poster_path}
        class="w-[34px] h-[51px] rounded glass-inset flex items-center justify-center shrink-0"
      >
        <.icon name="hero-film" class="size-4 opacity-30" />
      </span>
      <span class="min-w-0">
        <span class="block text-sm font-semibold truncate">{@result.title}</span>
        <span class="block text-xs text-base-content/55">
          {format_type(@result.tmdb_type)}{if @result.year, do: " · #{@result.year}"}
        </span>
      </span>
    </button>
    """
  end

  defp file_count(1), do: "1 file"
  defp file_count(count), do: "#{count} files"

  defp aria_checked(:checked), do: "true"
  defp aria_checked(:indeterminate), do: "mixed"
  defp aria_checked(_state), do: "false"

  defp reason_text(:low_confidence, file), do: "Unsure · #{round((file.confidence || 0) * 100)}%"
  defp reason_text(:grab_conflict, file), do: "Grab wanted #{file.wanted_title}"
  defp reason_text(:dismissed, _file), do: "Dismissed"
  defp reason_text(reason, _file), do: reason_label(reason)

  defp reason_class(:dismissed), do: "text-base-content/55"
  defp reason_class(reason), do: reason_text_class(reason)

  defp relative_path(%{media_directory: nil, file_path: path}), do: path

  defp relative_path(%{media_directory: dir, file_path: path}),
    do: String.replace_prefix(path, dir <> "/", "")
end
