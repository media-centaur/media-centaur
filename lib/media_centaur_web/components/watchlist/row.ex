defmodule MediaCentaurWeb.Components.Watchlist.Row do
  @moduledoc """
  One row of the Watchlist page (campaign `discovery.md`, M15): a title
  intent as the app draws a list row you manage in place. The identity
  block (`TitleSummary.title_summary/1`, as the search row and the Feed
  row draw it) with the host's quiet markers and the note a friend's
  listing came with; at the right the social glyphs, the **state block**
  — what the app knows about the title's releases, one line and a date —
  and the **controls**, always shown: the rung as a glass select whose
  items are the rung's state words (`Title.Logic.rung_word/1`) with
  Ignore and Remove as verbs, so the row is where a rung is changed, not
  a trip to the title detail. An Ignored row offers On your list and
  Stop ignoring. An owned title is never offered Ignore.

  Pure rendering of an `Item`; the row decides nothing. The whole row
  bubbles `open_title` with the title's ref (the ref doubles as
  `data-entity-id`, the input system's overlay-restore origin); the
  select's trigger pushes `rung_menu_toggle` with the ref, its items
  `rung_choice` with `choice` and `ref`, and a click outside or BACK
  `rung_menu_close` — the page owns which menu is open, since one is
  open at a time. The row is a nav item of the page's `watchlist_rows`
  tree; the trigger is a `data-nav-sub-item`, so RIGHT steps onto it
  and the open list is its own `watchlist_rung_menu` zone (`GlassMenu`).

  The state block's words are this module's (`state_words/2`), so the
  page's logic decides the fact — a kind, a count, a date — and the
  kit the sentence; `data-state` carries the kind for the tests.
  """

  use Phoenix.Component

  import MediaCentaurWeb.Components.TMDB.TitleSummary, only: [title_summary: 1]

  alias MediaCentaur.Format
  alias MediaCentaurWeb.Components.GlassMenu
  alias MediaCentaurWeb.Components.Title.Grade
  alias MediaCentaurWeb.Components.Title.Logic
  alias MediaCentaurWeb.Components.Title.SocialGlyph
  alias MediaCentaurWeb.Components.Title.SocialWords
  alias MediaCentaurWeb.Components.Title.TrackingControls
  alias MediaCentaurWeb.TitleRef
  alias Phoenix.LiveView.JS

  defmodule State do
    @moduledoc """
    What the app knows about a listed title's releases, as a fact: the
    kind, and the count or date the kind rests on. The page's logic
    builds it from the release calendar (a followed title) or the
    release stage (a List-only one); `Row.state_words/2` says it.

    | kind | fact | reads |
    |---|---|---|
    | `:episodes_out` | `count` aired, not had; `date` the latest | *3 episodes out · Latest Mar 27* |
    | `:next_episode` | `date` the next one dated | *Next episode · Nov 11* |
    | `:between_seasons` | TMDB says the series returns, nothing dated | *Between seasons* |
    | `:ended` / `:canceled` | TMDB's word | *Ended* / *Canceled* |
    | `:nothing_scheduled` | a followed series TMDB has not dated or placed | *Nothing scheduled* |
    | `:out_now` | the home stage; `date` the home release, or a series' first episode | *Out now · Oct 16* |
    | `:in_theaters` | the theatrical stage; `date` the opening | *In theaters · Oct 16* |
    | `:coming_up` | unreleased; `date` the nearest ahead | *Coming up · Dec* |
    | `:undated` | TMDB has no usable date | *No release date* |
    | `:ignored` | the Ignored rung | *Hidden from the Feed and Discovery* |
    """

    @enforce_keys [:kind]
    defstruct [:kind, :count, :date]

    @type kind ::
            :episodes_out
            | :next_episode
            | :between_seasons
            | :ended
            | :canceled
            | :nothing_scheduled
            | :out_now
            | :in_theaters
            | :coming_up
            | :undated
            | :ignored

    @type t :: %__MODULE__{kind: kind(), count: non_neg_integer() | nil, date: Date.t() | nil}
  end

  defmodule Item do
    @moduledoc """
    View-model for one Watchlist row, built by `WatchlistLive.Logic`:
    the title intent's identity and rung, what the library and the
    acquisition say (`markers`, `owned?`), the friend's note, the
    title's social activity rows for the glyphs, the `State`, and
    whether this row's rung menu is the open one.
    """

    alias MediaCentaur.TMDB.Title
    alias MediaCentaurWeb.Components.Watchlist.Row.State

    @enforce_keys [:id, :ref, :title, :rung]
    defstruct [
      :id,
      :ref,
      :title,
      :rung,
      :poster_url,
      :state,
      owned?: false,
      markers: [],
      notes: [],
      social_activity: [],
      menu_open?: false
    ]

    @type t :: %__MODULE__{
            id: String.t(),
            ref: {pos_integer(), :movie | :tv_series},
            title: Title.t(),
            rung: :ignored | :list | :follow | :grab,
            poster_url: String.t() | nil,
            state: State.t() | nil,
            owned?: boolean(),
            markers: [String.t()],
            notes: [%{name: String.t() | nil, text: String.t()}],
            social_activity: [map()],
            menu_open?: boolean()
          }
  end

  attr :item, Item, required: true
  attr :today, Date, required: true, doc: "the date the state's chip is relative to"

  def watchlist_row(assigns) do
    rows = assigns.item.social_activity
    ref = TitleRef.param(assigns.item.ref)
    {line, detail} = state_words(assigns.item.state, assigns.today)

    assigns =
      assign(assigns,
        ref: ref,
        flags: SocialWords.drawn_flags(rows),
        grades: Grade.for_title(rows),
        sentences: SocialWords.sentences(rows),
        line: line,
        detail: detail,
        choices: choices(assigns.item)
      )

    ~H"""
    <div
      id={@item.id}
      role="button"
      class="group watchlist-row flex cursor-pointer items-center gap-4 rounded-lg px-4 py-3 text-left hover:bg-base-content/5"
      data-component="watchlist-row"
      data-rung={@item.rung}
      data-state={@item.state && @item.state.kind}
      data-owned={@item.owned? && "true"}
      phx-click="open_title"
      phx-value-ref={@ref}
      data-entity-id={@ref}
      data-nav-item
      tabindex="0"
    >
      <.title_summary title={@item.title} poster_url={@item.poster_url}>
        <:markers>
          <span :for={marker <- @item.markers} class="shrink-0 text-xs text-base-content/55">
            {marker}
          </span>
        </:markers>
        <:secondary :if={@item.notes != []}>
          <span :for={note <- @item.notes} class="block">
            <span :if={note.name} class="font-medium text-base-content/70">{note.name}</span>
            {note.text}
          </span>
        </:secondary>
      </.title_summary>

      <div class="ml-auto flex shrink-0 items-center gap-6">
        <SocialGlyph.social_glyphs
          :if={@flags != []}
          flags={@flags}
          grades={@grades}
          tips={@sentences}
          class="gap-3 [--glyph:1.25rem]"
        />

        <div :if={@line} class="w-44 text-right" data-role="state">
          <p class="text-sm text-base-content/80">{@line}</p>
          <p :if={@detail} class="text-xs text-base-content/55">{@detail}</p>
        </div>

        <GlassMenu.menu_select
          id={"#{@item.id}-rung"}
          open={@item.menu_open?}
          on_toggle={JS.push("rung_menu_toggle", value: %{ref: @ref})}
          on_close="rung_menu_close"
          menu_zone="watchlist_rung_menu"
          value_label={Logic.rung_word(@item.rung)}
          label="Rung"
          sub_item
          class="w-36 justify-end"
          data-role="rung"
        >
          <:item
            :for={{choice, label} <- @choices}
            id={"#{@item.id}-rung-#{choice}"}
            event="rung_choice"
            values={%{"choice" => choice, "ref" => @ref}}
            active={choice == Atom.to_string(@item.rung)}
          >
            {label}
          </:item>
        </GlassMenu.menu_select>
      </div>
    </div>
    """
  end

  @doc """
  The state block's words for a `State`: the line and the date beneath
  it (`Format.date_chip/3`, relative to `today`); `{nil, nil}` for no
  state.
  """
  @spec state_words(State.t() | nil, Date.t()) :: {String.t() | nil, String.t() | nil}
  def state_words(nil, _today), do: {nil, nil}

  def state_words(%State{kind: :episodes_out, count: count, date: date}, today),
    do: {episodes_out(count), latest(date, today)}

  def state_words(%State{kind: :next_episode, date: date}, today),
    do: {"Next episode", Format.date_chip(:day, date, today)}

  def state_words(%State{kind: :between_seasons}, _today), do: {"Between seasons", nil}
  def state_words(%State{kind: :ended}, _today), do: {"Ended", nil}
  def state_words(%State{kind: :canceled}, _today), do: {"Canceled", nil}
  def state_words(%State{kind: :nothing_scheduled}, _today), do: {"Nothing scheduled", nil}

  def state_words(%State{kind: :out_now, date: date}, today),
    do: {"Out now", Format.date_chip(:day, date, today)}

  def state_words(%State{kind: :in_theaters, date: date}, today),
    do: {"In theaters", Format.date_chip(:day, date, today)}

  def state_words(%State{kind: :coming_up, date: date}, today),
    do: {"Coming up", Format.date_chip(:month, date, today)}

  def state_words(%State{kind: :undated}, _today), do: {"No release date", nil}
  def state_words(%State{kind: :ignored}, _today), do: {"Hidden from the Feed and Discovery", nil}

  defp episodes_out(1), do: "1 episode out"
  defp episodes_out(count), do: "#{count} episodes out"

  defp latest(nil, _today), do: nil
  defp latest(date, today), do: "Latest #{Format.date_chip(:day, date, today)}"

  @doc """
  The rung menu's items for a row, `{choice, label}` in order: the three
  list rungs by their state words, then Ignore (not for an owned title)
  and Remove; an Ignored row offers On your list and Stop ignoring. The
  choice is the word `set_rung` takes.
  """
  @spec choices(Item.t()) :: [{String.t(), String.t()}]
  def choices(%Item{rung: :ignored}),
    do: [{"list", Logic.rung_word(:list)}, {"off", TrackingControls.unignore_label()}]

  def choices(%Item{owned?: owned?}) do
    rungs = for rung <- [:list, :follow, :grab], do: {Atom.to_string(rung), Logic.rung_word(rung)}
    ignore = if owned?, do: [], else: [{"ignored", TrackingControls.ignore_label()}]
    rungs ++ ignore ++ [{"off", "Remove"}]
  end
end
