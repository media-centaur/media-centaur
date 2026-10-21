# Person Page Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One page per known person at `/social/friends/<npub>` and `/social/friends/you`: their activity folded one row per title on the left, the reader's view of them (name, picture, colour, hide, remove) on the right; the grid and rail cards link to it and the opened-in-place card is retired.

**Architecture:** The Social page has two projections of one activity list: by action over time (the Feed) and by person folded per title (the person card). The person page is the second projection in full for one person. One fold (`SocialLive.People`) yields one row per title, which is both the card's strip item and the page's row (`Act` is deleted); one row component (`FeedRow`) draws the Feed's per-action row and the page's per-title row from one widened view-model (`FeedEntry`); the toolbar's resolved slots become one value (`ToolbarSlots`). The reader's view is a Settings-kit card (`ReaderView`). The route is a third live action on `SocialLive`.

**Tech Stack:** Phoenix LiveView, Phoenix Storybook, ExUnit + LazyHTML, the input system (`assets/js/input`, bun tests), Tailwind + `assets/css/app.css`.

**Spec:** `docs/superpowers/specs/2026-10-20-person-page-design.md`. Mockup: `docs/superpowers/specs/2026-10-19-person-page-mockups/B-two-column/feed-with-series.html`.

**Ground rules for every task**
- Never run `mix` directly: `~/scripts/agents/agent-mix test <path>`; `~/scripts/agents/agent-mix precommit` at the end.
- The shell is fish: wrap bash loops in `bash -c '...'`.
- Test-first. Story edits before component edits for a component that has a story.
- No real titles anywhere: `Sample Movie`, `Sample Show`.
- Commit after each task with a conventional message.

**Task order and why:** 1–2 widen the row so the page can use it; 3 gives the web layer a key parser; 4 makes the fold yield the row and deletes `Act`; 5 draws the reader's view; 6 adds the route and the page; 7 wires keyboard and gamepad; 8 retires the opened card last, so every behaviour stays covered at every commit; 9 is the records and docs; 10 is precommit and the visual check.

---

## File structure

| File | Responsibility |
|---|---|
| `lib/media_centaur_web/components/social/toolbar_slots.ex` (new) | The toolbar's two resolved slots and their three facts, one value per title |
| `lib/media_centaur_web/components/social/feed_entry.ex` | The row's view-model, widened: optional author, subject, glyphs at grade, episode, slots |
| `lib/media_centaur_web/components/social/feed_row.ex` | The one row component: tile and name only with an author; every glyph; the episode name; the toolbar from `slots` |
| `lib/media_centaur_web/live/social_live/feed_entries.ex` | The Feed's per-action builder; glyph at grade |
| `lib/media_centaur_web/live/social_live/people.ex` | The fold: one `FeedEntry` per title per person |
| `lib/media_centaur_web/components/social/act.ex` | Deleted: the strip item is the row |
| `lib/media_centaur/social.ex` | `parse_pubkey/1`, the web layer's key parser |
| `lib/media_centaur_web/components/social/reader_view.ex` (new) | The reader's view card, from the Settings kit |
| `lib/media_centaur_web/live/social_live/person_page.ex` (new) | `path/1`, `find/2`, and the page composition |
| `lib/media_centaur_web/live/social_live.ex` | The `:person` action; person resolution in `project/1`; links instead of opened state |
| `lib/media_centaur_web/components/social/person_card.ex` | Head (a link) and strip only |
| `lib/media_centaur_web/router.ex` | `/social/friends/:key` |
| `assets/js/input/config.js`, `assets/js/input/__tests__/social_behavior.test.js` | `person_rows` tree and `person_view` grid zones |
| `assets/css/app.css` | `.person-page` columns; `.person-card-opened` removed |
| `storybook/social/*.story.exs` | Stories updated/added in the same task as each component |
| `decisions/user-interface/2026-10-21-054-the-person-page.md` (new), UIDR-046 amendment, `docs/GLOSSARY.md`, `docs/social.md`, `docs/storybook.md`, wiki `Social.md` | Records and docs |

---

### Task 1: `ToolbarSlots`, one value for the toolbar's facts

**Files:**
- Create: `lib/media_centaur_web/components/social/toolbar_slots.ex`
- Test: `test/media_centaur_web/components/social/toolbar_slots_test.exs`

- [ ] **Step 1: Write the failing test**

```elixir
defmodule MediaCentaurWeb.Components.Social.ToolbarSlotsTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaurWeb.Components.Social.ToolbarSlots

  defp facts(overrides),
    do: Map.merge(%{rung: nil, library_owner_id: nil, acquisition_state: nil}, overrides)

  test "the List slot: the verb below the list, Listed on it, Following above it" do
    assert %ToolbarSlots{list: :list, rung: nil} = ToolbarSlots.resolve(facts(%{}))
    assert %ToolbarSlots{list: :listed, rung: :list} = ToolbarSlots.resolve(facts(%{rung: :list}))
    assert %ToolbarSlots{list: :following, rung: :follow} = ToolbarSlots.resolve(facts(%{rung: :follow}))
  end

  test "the Download slot: In library wins, then the acquisition marker, else the verb" do
    assert %ToolbarSlots{download: :download} = ToolbarSlots.resolve(facts(%{}))

    assert %ToolbarSlots{download: {:state, "In library"}, library_owner_id: "owner"} =
             ToolbarSlots.resolve(facts(%{library_owner_id: "owner", acquisition_state: :downloading}))

    assert %ToolbarSlots{download: {:state, "Downloading"}, acquisition_state: :downloading} =
             ToolbarSlots.resolve(facts(%{acquisition_state: :downloading}))
  end

  test "extra keys on an enriched row are ignored" do
    assert %ToolbarSlots{list: :list} = ToolbarSlots.resolve(Map.put(facts(%{}), :activity, :anything))
  end
end
```

- [ ] **Step 2: Run it to see it fail**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/components/social/toolbar_slots_test.exs`
Expected: compile error, `ToolbarSlots` undefined.

- [ ] **Step 3: Write the module**

```elixir
defmodule MediaCentaurWeb.Components.Social.ToolbarSlots do
  @moduledoc """
  The two resolved positions of a row's toolbar (UIDR-045, UIDR-046)
  and the three facts they come from: the title's rung on the reader's
  watchlist, the library entity that owns it, and its acquisition
  state. Facts about the reader and a title, never about an action —
  one value per title, carried by every row for it: the Feed's row for
  one action and the person page's row for one title.

  `list` is what the List position holds: the verb `:list`, the filled
  `:listed`, or the state `:following` (Follow and above; the row
  renders it as "Tracking"). `download` is the verb `:download` or
  `{:state, word}` — "In library", or the acquisition marker while a
  plan runs (`Logic.acquisition_marker/1`, so no state is spelled
  twice). A view-model, resolved by the host; the row decides nothing.
  """

  alias MediaCentaur.Watchlist.TitleIntent
  alias MediaCentaurWeb.Components.Title.Logic

  defstruct [:rung, :library_owner_id, :acquisition_state, :list, :download]

  @type list :: :list | :listed | :following
  @type download :: :download | {:state, String.t()}

  @type t :: %__MODULE__{
          rung: TitleIntent.rung() | nil,
          library_owner_id: Ecto.UUID.t() | nil,
          acquisition_state: atom() | nil,
          list: list(),
          download: download()
        }

  @doc "The slots for an enriched activity row, or any map carrying the three facts."
  @spec resolve(%{
          required(:rung) => TitleIntent.rung() | nil,
          required(:library_owner_id) => term() | nil,
          required(:acquisition_state) => atom() | nil,
          optional(atom()) => term()
        }) :: t()
  def resolve(%{rung: rung, library_owner_id: owner, acquisition_state: state}) do
    %__MODULE__{
      rung: rung,
      library_owner_id: owner,
      acquisition_state: state,
      list: list_slot(rung),
      download: download_slot(owner, state)
    }
  end

  defp list_slot(:list), do: :listed
  defp list_slot(rung), do: if(TitleIntent.follows_releases?(rung), do: :following, else: :list)

  defp download_slot(owner, _state) when not is_nil(owner), do: {:state, "In library"}

  defp download_slot(nil, state) do
    case Logic.acquisition_marker(state) do
      nil -> :download
      word -> {:state, word}
    end
  end
end
```

- [ ] **Step 4: Run the test; it passes**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/components/social/toolbar_slots_test.exs`
Expected: 3 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur_web/components/social/toolbar_slots.ex test/media_centaur_web/components/social/toolbar_slots_test.exs
git commit -m "feat(social): the toolbar's slots are one value per title"
```

---

### Task 2: The row's view-model widens; the Feed's glyph takes its grade

One commit: the struct, the builder, the component, its test, its story and the page's handlers change together or nothing compiles.

**Files:**
- Modify: `lib/media_centaur_web/components/social/feed_entry.ex`
- Modify: `lib/media_centaur_web/components/social/feed_row.ex`
- Modify: `lib/media_centaur_web/live/social_live/feed_entries.ex`
- Modify: `lib/media_centaur_web/live/social_live/people.ex` (accepts `grades:`)
- Modify: `lib/media_centaur_web/live/social_live.ex` (handlers, `project/1`)
- Modify: `storybook/social/feed_row.story.exs`
- Test: `test/media_centaur_web/components/social/feed_row_test.exs`, `test/media_centaur_web/live/social_live/feed_entries_test.exs`

- [ ] **Step 1: The story first — rewrite the fixture and add the page's variations**

In `storybook/social/feed_row.story.exs` replace `entry/2` with:

```elixir
  alias MediaCentaur.Activities.Activity.Episode
  alias MediaCentaurWeb.Components.Social.ToolbarSlots

  @slots %ToolbarSlots{rung: nil, library_owner_id: nil, acquisition_state: nil, list: :list, download: :download}

  defp entry(id, overrides) do
    tmdb_id = Map.get(overrides, :tmdb_id, 777)

    struct!(
      %FeedEntry{
        id: "feed-row-#{id}",
        activity_id: id,
        ref: {tmdb_id, :movie},
        title: Title.new!(%{tmdb_id: tmdb_id, media_type: :movie, name: "Sample Movie", year: "2024"}),
        poster_url: "/images/storybook/sample-poster.jpg",
        author: friend(),
        subject: :friend,
        kind: :listing,
        episode: nil,
        glyphs: [],
        text: nil,
        acted_at: ~U[2026-09-01 12:00:00Z],
        ago: "12m ago",
        slots: @slots
      },
      overrides
    )
  end
```

Then apply this mapping to every variation's overrides:

| Was | Becomes |
|---|---|
| `sentiment: :like` (any flag) | `glyphs: [{:like, :plain}]` |
| `sentiment: nil` | `glyphs: []` |
| `author: you()` | `author: you(), subject: :you` |
| `rung: :list, list_slot: :listed` | `slots: %{@slots \| rung: :list, list: :listed}` |
| `rung: :follow, list_slot: :following` | `slots: %{@slots \| rung: :follow, list: :following}` |
| `library_owner_id: "owner", download_slot: {:state, "In library"}` | `slots: %{@slots \| library_owner_id: "owner", download: {:state, "In library"}}` |
| `acquisition_state: :downloading, download_slot: {:state, "Downloading"}` | `slots: %{@slots \| acquisition_state: :downloading, download: {:state, "Downloading"}}` |

The `:own_hovered` variation combines `subject: :you` with `slots: %{@slots | rung: :list, list: :listed, library_owner_id: "owner", download: {:state, "In library"}}`.

Append three variations:

```elixir
      %Variation{
        id: :graded,
        description: "A love three friends share: the heart in gold, as on a card (the Feed's glyph takes its grade).",
        attributes: %{
          entry: entry("graded", %{kind: :review, glyphs: [{:love, :gold}], text: "Yes.", ago: "1d ago"})
        }
      },
      %Variation{
        id: :person_page_row,
        description:
          "The person page's row: no tile and no name (the page is one person), every act on the title after the verb — reviewed, love and watched — and the review's words.",
        attributes: %{
          entry:
            entry("page", %{
              id: "person-row-page",
              author: nil,
              kind: :review,
              glyphs: [{:love, :gold}, {:watched, :silver}],
              text: @review_text,
              ago: "1w ago"
            })
        }
      },
      %Variation{
        id: :person_page_series,
        description:
          "A series on the person page: watched at its latest episode, the episode's name in the words slot; reviewed earlier, so the opinion glyph follows the eye and the review's words sit under the name.",
        attributes: %{
          entry:
            entry("series", %{
              id: "person-row-series",
              tmdb_id: 1399,
              ref: {1399, :tv_series},
              title: Title.new!(%{tmdb_id: 1399, media_type: :tv_series, name: "Sample Show", year: "1959"}),
              author: nil,
              kind: :watched,
              episode: %Episode{season_number: 1, episode_number: 7, name: "Sample Episode"},
              glyphs: [{:watched, :plain}, {:review, :plain}],
              text: "Slow, but it earns the slowness.",
              ago: "2d ago"
            })
        }
      }
```

Update the story's moduledoc first sentence to: "One row on the Feed and on the person page (UIDR-046, UIDR-054): one author's action on one title, or one person's acts on one title, as the app draws a list row — the identity tile at 40 when the row names its author, the poster at 80×120, then the verb with every glyph at its grade, the title and year, the episode's name on a series, the review's words in full, and the time at the row's right edge."

- [ ] **Step 2: Widen `FeedEntry`**

Replace the whole of `lib/media_centaur_web/components/social/feed_entry.ex`:

```elixir
defmodule MediaCentaurWeb.Components.Social.FeedEntry do
  @moduledoc """
  One row on the Feed or on the person page (UIDR-038, UIDR-045,
  UIDR-054): what the row shows, every fact resolved by the host. On the
  Feed a row is one author's action on one title (`SocialLive.FeedEntries`);
  on the person page it is one person's acts on one title, folded
  (`SocialLive.People`).

  `author` is the person as the reader sees them (`Social.Person`), and
  nil on the person page, where the page is one person: the row then
  draws no identity tile and no name. `subject` decides the verb's
  person and whether Ignore renders (never for `:you`). `kind` and
  `episode` are the newest act's: the verb (`ActivityWords.verb_phrase/3`)
  and, on a series, the episode's name in the words slot. `glyphs` are
  the flags drawn after the verb, each at its grade (`Title.Grade`): the
  review's sentiment alone on the Feed, every act on the title on the
  person page. `text` is the review's words, or nil. `poster_url` is the
  row's one picture, resolved by the host down `TitleArtwork`'s ladder;
  nil shows the empty slot. `slots` is the toolbar (`ToolbarSlots`).
  `ago` is the relative time, anchored by the host's `now`.
  Where this could be confused with a library entry, say *feed row*.
  """

  alias MediaCentaur.Activities.Activity
  alias MediaCentaur.Activities.Activity.Episode
  alias MediaCentaur.Social.Person
  alias MediaCentaur.TMDB.Title
  alias MediaCentaurWeb.Components.Social.ToolbarSlots
  alias MediaCentaurWeb.Components.Title.Flag
  alias MediaCentaurWeb.Components.Title.Grade

  defstruct [
    :id,
    :activity_id,
    :ref,
    :title,
    :poster_url,
    :author,
    :subject,
    :kind,
    :episode,
    :text,
    :acted_at,
    :ago,
    :slots,
    glyphs: []
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          activity_id: String.t(),
          ref: {integer(), Title.media_type()},
          title: Title.t(),
          poster_url: String.t() | nil,
          author: Person.t() | nil,
          subject: :friend | :you,
          kind: Activity.kind(),
          episode: Episode.t() | nil,
          glyphs: [{Flag.flag(), Grade.t()}],
          text: String.t() | nil,
          acted_at: DateTime.t(),
          ago: String.t(),
          slots: ToolbarSlots.t()
        }
end
```

- [ ] **Step 3: The Feed builder**

In `lib/media_centaur_web/live/social_live/feed_entries.ex`:

Add to the moduledoc's last paragraph, replacing the sentence about the toolbar's two slots: "Every row's toolbar is its title's `ToolbarSlots`. The Feed's one glyph is the review's sentiment at its grade — the host hands `grades:` (`Title.Grade.grades/1` over the page's rows) so the count is the same the cards draw."

Aliases: add `alias MediaCentaur.Activities.Activity`, `alias MediaCentaurWeb.Components.Social.ToolbarSlots`, `alias MediaCentaurWeb.Components.Title.Grade`, `alias MediaCentaurWeb.SocialLive.ActivityWords`; remove `alias MediaCentaur.Watchlist.TitleIntent` and `alias MediaCentaurWeb.Components.Title.Logic`.

Change the `build/2` spec and body:

```elixir
  @spec build([map()],
          now: DateTime.t(),
          window: pos_integer(),
          scope: scope(),
          head: String.t() | nil,
          grades: %{{Grade.ref(), Flag.flag()} => Grade.t()}
        ) :: ...
  def build(rows, opts) do
    now = Keyword.fetch!(opts, :now)
    window = min(Keyword.fetch!(opts, :window), @cap)
    scope = Keyword.fetch!(opts, :scope)
    grades = Keyword.fetch!(opts, :grades)
    ...
      entries: visible |> Enum.take(window) |> Enum.map(&entry(&1, now, grades)),
```

(add `alias MediaCentaurWeb.Components.Title.Flag` for the spec). Replace `entry/2` and delete the public `list_slot/1` and `download_slot/1`:

```elixir
  defp entry(%{activity: activity} = row, now, grades) do
    ref = {activity.tmdb_id, activity.media_type}

    %FeedEntry{
      id: "feed-row-" <> activity.id,
      activity_id: activity.id,
      ref: ref,
      title: activity.title,
      poster_url: row.poster_url,
      author: row.author,
      subject: ActivityWords.subject(row.author),
      kind: activity.kind,
      episode: nil,
      glyphs: glyphs(activity, ref, grades),
      text: if(activity.kind == :review, do: activity.text),
      acted_at: activity.acted_at,
      ago: Format.relative_ago(activity.acted_at, now: now, sub_minute: :just_now),
      slots: ToolbarSlots.resolve(row)
    }
  end

  # The Feed's one glyph: the review's sentiment at its grade; none for
  # a review without one or a listing (UIDR-046).
  defp glyphs(%Activity{kind: :review, sentiment: sentiment}, ref, grades) when not is_nil(sentiment),
    do: [{sentiment, Map.fetch!(grades, {ref, sentiment})}]

  defp glyphs(_activity, _ref, _grades), do: []
```

- [ ] **Step 4: `People.build/3` takes the grades the host computed**

In `lib/media_centaur_web/live/social_live/people.ex` change `build/3`:

```elixir
  @spec build([map()], %{optional(String.t()) => Person.t()},
          now: DateTime.t(),
          grades: %{{Grade.ref(), Flag.flag()} => Grade.t()}
        ) :: [Card.t()]
  def build(rows, people, opts) do
    now = Keyword.fetch!(opts, :now)
    by_author = Enum.group_by(rows, & &1.activity.author_pubkey)
    grades = Keyword.fetch!(opts, :grades)
```

and add to the `@doc`: "`grades:` is `Title.Grade.grades/1` over the same rows; the host computes it once for the cards and the Feed." In `people_test.exs` add `alias MediaCentaurWeb.Components.Title.Grade` and `defp build(rows, people), do: People.build(rows, people, now: @now, grades: Grade.grades(rows))`, and replace every `People.build(rows, people, now: @now)`-shaped call with `build(rows, people)`.

- [ ] **Step 5: The row component**

Replace the `~H` body of `feed_row/1` in `lib/media_centaur_web/components/social/feed_row.ex` from `<IdentityTile.identity_tile` through the end of the `<p ... data-role="text">` block, and the Ignore button's `:if`:

```heex
      <IdentityTile.identity_tile
        :if={@entry.author}
        {IdentityTile.person_attrs(@entry.author)}
        size={40}
      />

      <img
        :if={@entry.poster_url}
        src={row_poster_src(@entry.poster_url)}
        alt=""
        class="h-[120px] w-20 shrink-0 rounded-md object-cover shadow-[0_3px_12px_oklch(0%_0_0/0.45)]"
        data-role="poster"
        loading="eager"
        decoding="sync"
      />
      <div
        :if={!@entry.poster_url}
        class="h-[120px] w-20 shrink-0 rounded-md bg-base-content/6 ring-1 ring-inset ring-base-content/10"
        data-role="poster-empty"
      >
      </div>

      <div class="min-w-0 flex-1">
        <p class="truncate text-base leading-6 text-base-content/80" data-role="who">
          <span :if={@entry.author} class="font-medium text-base-content/95">
            {Format.person_name(@entry.author)}
          </span>
          {ActivityWords.verb_phrase(@entry.kind, @entry.episode, @entry.subject)}
          <SocialGlyph.social_glyph
            :for={{flag, grade} <- @entry.glyphs}
            flag={flag}
            grade={grade}
            class="size-4 align-middle"
          />
        </p>
        <p class="flex items-baseline gap-2 text-lg font-semibold leading-7" data-role="title">
          <span class="truncate">{@entry.title.name}</span>
          <span :if={@entry.title.year} class="shrink-0 text-sm font-normal text-base-content/60">
            {@entry.title.year}
          </span>
        </p>
        <p
          :if={@entry.episode && @entry.episode.name}
          class="mt-1 text-base leading-6 text-base-content/80"
          data-role="episode"
        >
          {@entry.episode.name}
        </p>
        <p
          :if={@entry.text}
          class="mt-1 max-w-[40rem] text-base leading-6 text-base-content/80"
          data-role="text"
        >
          {@entry.text}
        </p>
```

The root's attributes change to `data-own={@entry.subject == :you}`, `data-list-slot={@entry.slots.list}`, `data-download-slot={slot_name(@entry.slots.download)}`. In the toolbar replace every `@entry.list_slot` with `@entry.slots.list`, every `@entry.download_slot` with `@entry.slots.download`, `@entry.acquisition_state` with `@entry.slots.acquisition_state`, and the Ignore button's guard with `:if={@entry.subject == :friend}`.

Moduledoc: replace the first paragraph's opening with "One row on the Feed and on the person page (UIDR-046, UIDR-054): one author's action on one title, or one person's acts on one title, as the app draws a list row. The identity tile at 40 and the name when the row has an author — never on the person page, which is one person — the poster at 80×120 beside it, then the words: the verb (`Nick reviewed`, `watched S02E05 of`, `You want to watch`) with every glyph after it at its grade (the review's sentiment on the Feed; every act on the title on the person page; nothing when there is none), which title (name and year), the episode's name on a series, and the review's words in full — and the relative time at the row's right edge, all hung from the row's top line." Keep the rest; change "Ignore on a friend's row only" to "Ignore when the subject is a friend".

- [ ] **Step 6: The page's handlers and `project/1`**

In `lib/media_centaur_web/live/social_live.ex`:

Add aliases `alias MediaCentaurWeb.Components.Social.ToolbarSlots` and `alias MediaCentaurWeb.Components.Title.Grade`.

`feed_list`:
```elixir
      %FeedEntry{slots: %ToolbarSlots{list: :list}} = entry ->
      ...
      %FeedEntry{slots: %ToolbarSlots{list: :listed}} = entry ->
```
`feed_download`: `%FeedEntry{slots: %ToolbarSlots{download: :download}} = entry ->`.
`ignore_title`: `previous_rung: entry.slots.rung || :off`.

`project/1`:
```elixir
  defp project(socket) do
    now = DateTime.utc_now()
    grades = Grade.grades(socket.assigns.activities)

    %{entries: entries, has_older?: has_older?, at_cap?: at_cap?, queued: queued} =
      FeedEntries.build(socket.assigns.activities,
        now: now,
        window: socket.assigns.feed_window,
        scope: socket.assigns.feed_scope,
        head: socket.assigns.feed_head,
        grades: grades
      )

    people =
      People.build(socket.assigns.activities, socket.assigns.people_by_pubkey, now: now, grades: grades)
```

- [ ] **Step 7: Update the row's component test**

In `test/media_centaur_web/components/social/feed_row_test.exs` replace the fixture:

```elixir
  alias MediaCentaur.Activities.Activity.Episode
  alias MediaCentaurWeb.Components.Social.ToolbarSlots

  @slots %ToolbarSlots{rung: nil, library_owner_id: nil, acquisition_state: nil, list: :list, download: :download}

  defp slots(overrides), do: struct!(@slots, overrides)

  defp entry(overrides) do
    struct!(
      %FeedEntry{
        id: "feed-row-a",
        activity_id: "a",
        ref: {777, :movie},
        title: Title.new!(%{tmdb_id: 777, media_type: :movie, name: "Sample Movie", year: "2024"}),
        poster_url: "/media-images/x/poster.jpg",
        author: person("Sample Friend"),
        subject: :friend,
        kind: :listing,
        episode: nil,
        glyphs: [],
        text: nil,
        acted_at: ~U[2026-09-01 12:00:00Z],
        ago: "12m ago",
        slots: @slots
      },
      overrides
    )
  end
```

Apply the Step 1 mapping to every existing test's overrides (`sentiment: :love` → `glyphs: [{:love, :plain}]`; `author: own_person()` → `author: own_person(), subject: :you`; `list_slot:`/`download_slot:`/`rung:`/`library_owner_id:`/`acquisition_state:` → `slots: slots(%{...})`). Then append:

```elixir
  test "without an author the row draws no tile and no name: the person page's row" do
    html = render(%{author: nil, kind: :review, glyphs: [{:love, :gold}, {:watched, :silver}], text: "Yes."})

    assert Enum.empty?(LazyHTML.query(html, "[data-component='identity-tile']"))
    who = html |> LazyHTML.query("[data-role='who']") |> LazyHTML.text() |> String.replace(~r/\s+/, " ")
    assert String.trim(who) == "reviewed"
    refute who =~ "Sample Friend"

    glyphs = LazyHTML.query(html, "[data-role='who'] .social-glyph")
    assert LazyHTML.attribute(glyphs, "data-flag") == ["love", "watched"]
    assert LazyHTML.attribute(glyphs, "data-grade") == ["gold", "silver"]
    assert html |> LazyHTML.query("[data-role='text']") |> LazyHTML.text() |> String.trim() == "Yes."
  end

  test "a series row: the episode's verb and its name in the words slot, with the review's words under it" do
    episode = %Episode{season_number: 1, episode_number: 7, name: "Sample Episode"}
    html = render(%{author: nil, kind: :watched, episode: episode, glyphs: [{:watched, :plain}, {:review, :plain}], text: "Slow."})

    assert html |> LazyHTML.query("[data-role='who']") |> LazyHTML.text() |> String.trim() =~ "watched S01E07 of"
    assert html |> LazyHTML.query("[data-role='episode']") |> LazyHTML.text() |> String.trim() == "Sample Episode"
    assert html |> LazyHTML.query("[data-role='text']") |> LazyHTML.text() |> String.trim() == "Slow."

    nameless = render(%{author: nil, kind: :watched, episode: %{episode | name: nil}})
    assert Enum.empty?(LazyHTML.query(nameless, "[data-role='episode']"))
  end

  test "Ignore follows the subject, not the author: none when the subject is You" do
    assert Enum.empty?(LazyHTML.query(render(%{author: nil, subject: :you}), "button[phx-click='ignore_title']"))
    assert render(%{author: nil, subject: :friend}) |> LazyHTML.query("button[phx-click='ignore_title']") |> Enum.count() == 1
  end
```

- [ ] **Step 8: Update the Feed builder's test**

In `test/media_centaur_web/live/social_live/feed_entries_test.exs` add `alias MediaCentaurWeb.Components.Title.Grade` and change the helper:

```elixir
  defp build(rows, opts \\ []) do
    FeedEntries.build(
      rows,
      Keyword.merge(
        [now: @now, window: FeedEntries.page_size(), scope: :everyone, head: nil, grades: Grade.grades(rows)],
        opts
      )
    )
  end
```

Grep the file for `list_slot`, `download_slot`, `sentiment:` and `rung:` assertions on entries (`grep -n "list_slot\|download_slot\|sentiment\|\.rung" test/media_centaur_web/live/social_live/feed_entries_test.exs`). Tests of `FeedEntries.list_slot/1` or `download_slot/1` are deleted (Task 1 covers them); an assertion `entry.list_slot == :listed` becomes `entry.slots.list == :listed`, `entry.sentiment == :love` becomes `entry.glyphs == [{:love, :plain}]`, `entry.rung` becomes `entry.slots.rung`. Append:

```elixir
    test "the Feed's one glyph is the review's sentiment at its grade; a listing and a bare review carry none" do
      rows = [
        row("Cleo", %{tmdb_id: 1, kind: :review, sentiment: :love, id: "cleo"}),
        row("Nick", %{tmdb_id: 1, kind: :review, sentiment: :love, id: "nick"}),
        own(%{tmdb_id: 1, kind: :review, sentiment: :love, id: "mine"}),
        row("Sam", %{tmdb_id: 2, kind: :review, sentiment: nil, text: "words", id: "sam"}),
        row("Sam", %{tmdb_id: 3, kind: :listing, id: "sam-lists"})
      ]

      by_id = Map.new(build(rows).entries, &{&1.activity_id, &1})

      assert by_id["cleo"].glyphs == [{:love, :gold}]
      assert by_id["mine"].glyphs == [{:love, :gold}]
      assert by_id["mine"].subject == :you
      assert by_id["sam"].glyphs == []
      assert by_id["sam-lists"].glyphs == []
      assert by_id["sam-lists"].subject == :friend
      assert %Person{} = by_id["cleo"].author
    end
```

- [ ] **Step 9: Run the three test files and the Social page's tests**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/components/social/feed_row_test.exs test/media_centaur_web/live/social_live/feed_entries_test.exs test/media_centaur_web/live/social_live/people_test.exs test/media_centaur_web/live/social_live_test.exs test/media_centaur_web/storybook_render_test.exs`
Expected: 0 failures. A `social_live_test` assertion on a Feed glyph's grade (e.g. `[data-grade='plain']`) that now reads gold or silver is a correct change in behaviour: three people on one title give gold; update the assertion to the count the test seeds.

- [ ] **Step 10: Commit**

```bash
git add -A lib/media_centaur_web/components/social lib/media_centaur_web/live/social_live.ex lib/media_centaur_web/live/social_live storybook/social/feed_row.story.exs test/media_centaur_web
git commit -m "refactor(social): one row view-model for the Feed and the person page; the Feed's glyph takes its grade"
```

---

### Task 3: `Social.parse_pubkey/1`

The web layer never reaches `Nostr.Keys` (the Social moduledoc's rule); the page needs to turn an address's key into a pubkey.

**Files:**
- Modify: `lib/media_centaur/social.ex` (beside `to_npub/1`, line ~258)
- Test: `test/media_centaur/social/contacts_test.exs`

- [ ] **Step 1: Write the failing test** (append inside the module)

```elixir
  test "parse_pubkey/1 takes an npub or a 64-hex key, trimmed, as lowercase hex, and refuses anything else" do
    assert {:ok, @pubkey} = Social.parse_pubkey(Keys.to_npub(@pubkey))
    assert {:ok, @pubkey} = Social.parse_pubkey("  " <> @pubkey <> "\n")
    assert {:error, :invalid_pubkey} = Social.parse_pubkey("you")
    assert {:error, :invalid_pubkey} = Social.parse_pubkey("npub1nope")
  end
```

- [ ] **Step 2: Run it to see it fail**

Run: `~/scripts/agents/agent-mix test test/media_centaur/social/contacts_test.exs`
Expected: `UndefinedFunctionError` for `Social.parse_pubkey/1`.

- [ ] **Step 3: Add the function** after `to_npub/1`:

```elixir
  @doc """
  An npub or 64-hex key, trimmed, as lowercase hex — the one key parser
  the web layer uses (an address, the add-friend form's key).
  """
  @spec parse_pubkey(String.t()) :: {:ok, String.t()} | {:error, :invalid_pubkey}
  def parse_pubkey(key) when is_binary(key), do: Keys.parse_pubkey(String.trim(key))
```

- [ ] **Step 4: Run; passes. Commit**

```bash
git add lib/media_centaur/social.ex test/media_centaur/social/contacts_test.exs
git commit -m "feat(social): parse_pubkey/1 is the web layer's key parser"
```

---

### Task 4: The fold yields the row; `Act` goes

The strip item and the page's row are one idea: one person's acts on one title. `Act` is deleted; a card's `acts` are `FeedEntry` rows (id `person-row-<newest activity id>`), and the strip reads the poster, the title, the newest activity and the glyphs at grade off the row.

**Files:**
- Delete: `lib/media_centaur_web/components/social/act.ex`
- Modify: `lib/media_centaur_web/live/social_live/people.ex`
- Modify: `lib/media_centaur_web/components/social/person_card.ex`
- Modify: `storybook/social/person_card.story.exs`
- Test: `test/media_centaur_web/live/social_live/people_test.exs`, `test/media_centaur_web/components/social/person_card_test.exs`

- [ ] **Step 1: Write the failing test** in `people_test.exs` (append; add `alias MediaCentaurWeb.Components.Social.FeedEntry` and `alias MediaCentaurWeb.Components.Social.ToolbarSlots`, remove the `Act.Entry` alias):

```elixir
  test "an act is the page's row: one per title, the newest act's verb, every flag at its grade, the review's words, the title's slots" do
    rows = [
      activity("Bob", @bob, %{tmdb_id: 7, kind: :watched, id: "bob-watched-7", acted_at: ~U[2026-09-02 12:00:00Z]}),
      activity("Bob", @bob, %{tmdb_id: 7, kind: :review, sentiment: :love, text: "Yes.", id: "bob-loves-7", acted_at: ~U[2026-09-01 12:00:00Z]}),
      activity("Alice", @alice, %{tmdb_id: 7, kind: :review, sentiment: :love, id: "alice-loves-7"}),
      activity("Bob", @bob, %{tmdb_id: 1399, media_type: :tv_series, kind: :review, sentiment: nil, text: "Slow.", id: "bob-reviews-show", acted_at: ~U[2026-08-30 12:00:00Z]}),
      activity("Bob", @bob, %{tmdb_id: 1399, media_type: :tv_series, kind: :watched, episode: %Episode{season_number: 1, episode_number: 7, name: "Sample Episode"}, id: "bob-watched-show", acted_at: ~U[2026-09-03 11:00:00Z]})
    ]

    [_you, %Card{person: %Person{pubkey: @bob}, acts: [show, movie]} | _rest] = build(rows, people(true))

    assert %FeedEntry{id: "person-row-bob-watched-show", activity_id: "bob-watched-show", author: nil, subject: :friend, kind: :watched} = show
    assert show.episode.name == "Sample Episode"
    assert show.glyphs == [{:review, :plain}, {:watched, :plain}]
    assert show.text == "Slow."

    assert %FeedEntry{id: "person-row-bob-watched-7", kind: :watched, episode: nil} = movie
    assert movie.glyphs == [{:love, :silver}, {:watched, :plain}]
    assert movie.text == "Yes."
    assert %ToolbarSlots{list: :list, download: :download} = movie.slots
  end

  test "the reader's own acts are rows in the second person" do
    [%Card{person: %Person{own?: true}, acts: [act]} | _friends] = build([own(%{tmdb_id: 3, kind: :listing})], people(true))
    assert act.subject == :you
    assert act.author == nil
  end
```

Add the helper the whole file now uses, and replace every `People.build(rows, people, now: @now)` call with `build(rows, people)` (the grades are the host's, computed once, so the test computes them the way the host does):

```elixir
  alias MediaCentaurWeb.Components.Title.Grade

  defp build(rows, people), do: People.build(rows, people, now: @now, grades: Grade.grades(rows))
```

Existing assertions convert as: `act.flags` → `Enum.map(act.glyphs, &elem(&1, 0))`; `act.grades` → `Map.new(act.glyphs)`; `act.entries` (the acts behind a title in order) → `act.glyphs` (the flags in order) or `act.kind` (the newest kind); `%Act{...}` → `%FeedEntry{...}`. Grep: `grep -n "Act\b\|entries\|\.flags\|\.grades" test/media_centaur_web/live/social_live/people_test.exs`.

- [ ] **Step 2: Run to see it fail**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/social_live/people_test.exs`
Expected: `KeyError` on a row field, or a pattern mismatch against `%Act{}`.

- [ ] **Step 3: `People`** — delete `act.ex`; in `people.ex` replace `card/4`, `acts/3`, `act/4` and `entry/1`:

```elixir
  defp card(%Person{} = person, rows, now, grades) do
    sorted = Enum.sort_by(rows, & &1.activity.acted_at, {:desc, DateTime})
    %Card{person: person, acts: acts(sorted, person, grades, now)}
  end

  # One row per title in the order the titles first appear — newest
  # first, since the rows are sorted — with every act on it behind it.
  defp acts(sorted, person, grades, now) do
    by_ref = Enum.group_by(sorted, &ref/1)

    sorted
    |> Enum.map(&ref/1)
    |> Enum.uniq()
    |> Enum.map(&act(&1, Map.fetch!(by_ref, &1), person, grades, now))
  end

  defp act(ref, [%{activity: %Activity{} = newest} = first | _rest] = rows, person, grades, now) do
    flags = rows |> Enum.map(&Flag.flag(&1.activity)) |> Flag.sort()

    %FeedEntry{
      id: "person-row-" <> newest.id,
      activity_id: newest.id,
      ref: ref,
      title: newest.title,
      poster_url: first.poster_url,
      author: nil,
      subject: ActivityWords.subject(person),
      kind: newest.kind,
      episode: newest.episode,
      glyphs: Enum.map(flags, &{&1, Map.fetch!(grades, {ref, &1})}),
      text: review_text(rows),
      acted_at: newest.acted_at,
      ago: Format.relative_ago(newest.acted_at, now: now, sub_minute: :just_now),
      slots: ToolbarSlots.resolve(first)
    }
  end

  # The review's words on the title, whichever act is newest.
  defp review_text(rows) do
    Enum.find_value(rows, fn
      %{activity: %Activity{kind: :review, text: text}} -> text
      _other -> nil
    end)
  end
```

`build/3`: `grades = Keyword.fetch!(opts, :grades)` (required; the `@doc` says the host computes it once for the cards and the Feed). `sort_key/1`: `%Card{acts: [%FeedEntry{acted_at: at} | _rest], person: person}`. `Card`'s type: `acts: [FeedEntry.t()]`, its doc "their acts, newest first — one `FeedEntry` per title acted on". Aliases: add `FeedEntry`, `ToolbarSlots` (`MediaCentaurWeb.Components.Social.*`) and `alias MediaCentaurWeb.SocialLive.ActivityWords`; remove `Act` and `Act.Entry`. Moduledoc: "A person's acts are one row per title (`FeedEntry`, the person page's row: the newest act's verb, every flag on the title at its grade — one count per person per title and flag over the rows this fold holds, the reader included — the review's words, the title's toolbar slots), newest first."

- [ ] **Step 4: `PersonCard` reads rows** — `attr :acts, :list, required: true, doc: "the person's rows (`FeedEntry`), newest first; `[]` for a quiet person"`. In the strip: `:for={row <- @shown}`, `TitleRef.param(row.ref)`, `tip(@name, row, @subject)`, `phx-value-activity={row.activity_id}`, `data-flags={Enum.map_join(row.glyphs, " ", &elem(&1, 0))}`, `<SocialGlyph.social_glyphs flags={flags(row)} grades={Map.new(row.glyphs)} class="act-slots" aria-hidden="true" />`, `act_poster_src(row.poster_url, @width)`, `row.title.name`. In the opened rows (retired in Task 8): `:for={row <- @acts}`, `id={"#{@id}-#{row.activity_id}"}`, `TitleRef.param(row.ref)`, `row.activity_id`, `ActivityWords.verb_phrase(row.kind, row.episode, @subject)`, `row.title.name`, `<SocialGlyph.social_glyph :for={{flag, grade} <- row.glyphs} flag={flag} grade={grade} class="ml-1 size-4 align-middle" />`, `row.ago`. Replace `sentence/2`, `tip/3` and `newest/1` with:

```elixir
  defp flags(%FeedEntry{glyphs: glyphs}), do: Enum.map(glyphs, &elem(&1, 0))

  defp tip(name, %FeedEntry{} = row, subject),
    do: name <> " " <> ActivityWords.sentence(row.kind, row.episode, row.title.name, subject)
```

Alias `FeedEntry` instead of `Act`. Moduledoc: "Pure rendering of a `Social.Person` and their rows (`FeedEntry`, one per title, `SocialLive.People`)".

- [ ] **Step 5: Story and component test fixtures** — in `storybook/social/person_card.story.exs` replace `act/4` (and the `Act`/`Entry` aliases) with:

```elixir
  alias MediaCentaurWeb.Components.Social.FeedEntry
  alias MediaCentaurWeb.Components.Social.ToolbarSlots

  @slots %ToolbarSlots{rung: nil, library_owner_id: nil, acquisition_state: nil, list: :list, download: :download}

  defp act(tmdb_id, name, flags, opts \\ []) do
    media_type = Keyword.get(opts, :media_type, :movie)
    grades = Map.merge(Map.new(flags, &{&1, :plain}), Keyword.get(opts, :grades, %{}))

    %FeedEntry{
      id: "person-row-#{tmdb_id}",
      activity_id: "activity-#{tmdb_id}-#{hd(flags)}",
      ref: {tmdb_id, media_type},
      title: Title.new!(%{tmdb_id: tmdb_id, media_type: media_type, name: name}),
      poster_url: Keyword.get(opts, :poster_url, @poster),
      author: nil,
      subject: :friend,
      kind: kind(hd(flags)),
      episode: Keyword.get(opts, :episode),
      glyphs: Enum.map(flags, &{&1, grades[&1]}),
      text: nil,
      acted_at: ~U[2026-09-01 12:00:00Z],
      ago: Keyword.get(opts, :ago, "2h ago"),
      slots: @slots
    }
  end
```

`test/media_centaur_web/components/social/person_card_test.exs`: the same shape for `act/3` (`activity_id: Keyword.fetch!(opts, :id)`, `kind: :review`, `glyphs: Enum.map(flags, &{&1, grades[&1]})` with `grades = Keyword.get(opts, :grades, Map.new(flags, &{&1, :plain}))`); delete `entry/2`, alias `FeedEntry` and `ToolbarSlots` instead of `Act` and `Entry`.

- [ ] **Step 6: Run**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/social_live/people_test.exs test/media_centaur_web/components/social/person_card_test.exs test/media_centaur_web/live/social_live_test.exs test/media_centaur_web/storybook_render_test.exs`
Expected: 0 failures.

- [ ] **Step 7: Commit**

```bash
git add -A lib/media_centaur_web/components/social lib/media_centaur_web/live/social_live storybook/social test/media_centaur_web
git commit -m "refactor(social): the fold yields the row; Act is gone"
```

---

### Task 5: `ReaderView`, the reader's view of a person

**Files:**
- Create: `lib/media_centaur_web/components/social/reader_view.ex`
- Create: `storybook/social/reader_view.story.exs`; modify `storybook/social/_social.index.exs`
- Test: `test/media_centaur_web/components/social/reader_view_test.exs`

- [ ] **Step 1: Write the failing test**

```elixir
defmodule MediaCentaurWeb.Components.Social.ReaderViewTest do
  use MediaCentaur.Case, async: true

  import MediaCentaur.SocialRows, only: [person: 1, person: 2]
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias MediaCentaurWeb.Components.Social.ReaderView

  defp render(attrs), do: LazyHTML.from_fragment(render_component(&ReaderView.reader_view/1, attrs))

  defp text(html, selector),
    do: html |> LazyHTML.query(selector) |> LazyHTML.text() |> String.replace(~r/\s+/, " ") |> String.trim()

  test "the card is headed with the reader's name for them and says only the reader sees it" do
    html = render(person: person("Nick"))

    assert text(html, "[data-component='reader-view'] h3") == "Your view of Nick"
    assert text(html, "[data-component='reader-view']") =~ "Only you see these"
  end

  test "Name: the override in the field, the masked name as the placeholder, Rename submits set_friend_name with the key" do
    html = render(person: person("Nick", published_name: "Ada"))
    form = LazyHTML.query(html, "[data-role='name-form']")

    assert LazyHTML.attribute(form, "phx-submit") == ["set_friend_name"]
    assert form |> LazyHTML.query("input[name='pubkey']") |> LazyHTML.attribute("value") == [person("Nick").pubkey]
    assert form |> LazyHTML.query("input[name='name']") |> LazyHTML.attribute("value") == ["Nick"]
    assert form |> LazyHTML.query("input[name='name']") |> LazyHTML.attribute("placeholder") == ["Ada"]
    assert text(form, "button[type='submit']") == "Rename"

    nameless = render(person: person(nil))
    assert nameless |> LazyHTML.query("[data-role='name-form'] input[name='name']") |> LazyHTML.attribute("value") == []
    assert nameless |> LazyHTML.query("[data-role='name-form'] input[name='name']") |> LazyHTML.attribute("placeholder") == ["Unnamed"]
  end

  test "Show their picture is a switch carrying the key and the value to set" do
    shown = LazyHTML.query(render(person: person("Nick")), "[role='switch'][phx-click='set_show_avatar']")
    assert LazyHTML.attribute(shown, "aria-checked") == ["true"]
    assert LazyHTML.attribute(shown, "phx-value-pubkey") == [person("Nick").pubkey]
    assert LazyHTML.attribute(shown, "phx-value-show") == ["false"]

    hidden = LazyHTML.query(render(person: person("Nick", show_avatar: false)), "[role='switch'][phx-click='set_show_avatar']")
    assert LazyHTML.attribute(hidden, "aria-checked") == ["false"]
    assert LazyHTML.attribute(hidden, "phx-value-show") == ["true"]
  end

  test "Colour: Theirs in the published hue, the chosen swatch pressed, the slider in a form saving on the act" do
    html = render(person: person("Nick", published_hue: 12, hue_override: 195))
    form = LazyHTML.query(html, "form[data-role='hue-form']")

    assert LazyHTML.attribute(form, "phx-change") == ["set_hue_override"]
    assert form |> LazyHTML.query("input[type='hidden'][name='pubkey']") |> LazyHTML.attribute("value") == [person("Nick").pubkey]
    assert form |> LazyHTML.query("button[data-role='theirs']") |> LazyHTML.attribute("style") == ["--hue: 12"]
    assert form |> LazyHTML.query("button[data-role='theirs']") |> LazyHTML.attribute("aria-pressed") == ["false"]
    assert form |> LazyHTML.query("button[data-hue='195']") |> LazyHTML.attribute("aria-pressed") == ["true"]
    assert form |> LazyHTML.query("input[type='range'][name='hue']") |> LazyHTML.attribute("value") == ["195"]
  end

  test "Hide is a switch: off for a shown person, on for a hidden one, carrying the value to set" do
    shown = LazyHTML.query(render(person: person("Nick")), "[role='switch'][phx-click='set_hidden']")
    assert LazyHTML.attribute(shown, "aria-checked") == ["false"]
    assert LazyHTML.attribute(shown, "phx-value-hide") == ["true"]

    hidden = LazyHTML.query(render(person: %{person("Nick") | hidden: true}), "[role='switch'][phx-click='set_hidden']")
    assert LazyHTML.attribute(hidden, "aria-checked") == ["true"]
    assert LazyHTML.attribute(hidden, "phx-value-hide") == ["false"]
  end

  test "the foot: the key and how the reader follows them; Remove friend for a friend, never for a member" do
    friend = render(person: person("Nick"))
    assert text(friend, "[data-role='foot']") =~ "npub1lyy9…8z4h"
    assert text(friend, "[data-role='foot']") =~ "added Aug 30"
    assert friend |> LazyHTML.query("button[phx-click='remove_friend']") |> LazyHTML.attribute("phx-value-pubkey") == [person("Nick").pubkey]

    member = render(person: %{person("Sample Member") | friend?: false, added_on: nil, member_of: ["wss://group.example/"]})
    assert text(member, "[data-role='foot']") =~ "on group.example"
    refute text(member, "[data-role='foot']") =~ "added"
    assert Enum.empty?(LazyHTML.query(member, "button[phx-click='remove_friend']"))
  end
end
```

- [ ] **Step 2: Run to see it fail**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/components/social/reader_view_test.exs`
Expected: compile error, `ReaderView` undefined.

- [ ] **Step 3: Write the component**

```elixir
defmodule MediaCentaurWeb.Components.Social.ReaderView do
  @moduledoc """
  The reader's view of one person (UIDR-054): the settings a reader keeps
  about a friend or a member and that nobody else sees, as one Settings
  card (`Components.Settings`, UIDR-041) headed *Your view of <name>*.
  Rows, in order: **Name** — the reader's name for them in a field with
  Rename, the name it masks (the published one, else Unnamed) as the
  placeholder (UIDR-047); the form submits `set_friend_name` with the
  key and the name, a blank clearing it. **Show their picture**, a
  switch pushing `set_show_avatar` with the key and the value to set.
  **Colour** (`HueSwatches`, UIDR-048): Theirs, the published hue, then
  the palette and the ring, pushing `set_hue_override` with the key and
  the hue, empty for Theirs; the slider through the row's own form.
  **Hide**, a switch pushing `set_hidden` with the key and the value to
  set — the hidden group's Show sends the same. The foot: the short npub
  and how the reader follows them — *added* and the date for a friend,
  *on* the relay's host for a member — and, for a friend only, **Remove
  friend** (`remove_friend` with the key). Pure rendering of a
  `Social.Person`; never drawn for the reader's own, whose name, picture
  and colour are under Settings → Social.
  """

  use Phoenix.Component

  import MediaCentaurWeb.CoreComponents, only: [button: 1]

  alias MediaCentaur.Format
  alias MediaCentaur.Social.Person
  alias MediaCentaurWeb.Components.Settings
  alias MediaCentaurWeb.Components.Social.HueSwatches

  attr :id, :string, default: "reader-view"
  attr :person, Person, required: true, doc: "a friend or a member as the reader sees them; never the reader's own"

  def reader_view(assigns) do
    assigns = assign(assigns, name: Format.person_name(assigns.person))

    ~H"""
    <Settings.settings_card
      id={@id}
      title={"Your view of #{@name}"}
      description={"Only you see these. They change nothing for #{@name} or anyone else."}
      data-component="reader-view"
    >
      <Settings.settings_field
        label="Name"
        description="What you call them. Blank shows the name they publish."
        layout={:stacked}
      >
        <form
          id={"#{@id}-name-form"}
          class="flex items-center gap-2"
          phx-submit="set_friend_name"
          data-role="name-form"
        >
          <input type="hidden" name="pubkey" value={@person.pubkey} />
          <Settings.settings_input
            name="name"
            value={@person.name_override}
            placeholder={masked_name(@person)}
            class="max-w-64"
            autocomplete="off"
          />
          <.button type="submit" variant="neutral" size="sm" data-nav-item tabindex="0">Rename</.button>
        </form>
      </Settings.settings_field>

      <Settings.settings_row
        label="Show their picture"
        description="Their published picture in every tile; off shows the letter."
        checked={@person.show_avatar}
        event="set_show_avatar"
        event_value={%{"pubkey" => @person.pubkey, "show" => to_string(not @person.show_avatar)}}
      />

      <Settings.settings_field
        label="Colour"
        description="The hue their tile and marks are drawn in."
        layout={:stacked}
      >
        <form id={"#{@id}-hue-form"} phx-change="set_hue_override" data-role="hue-form">
          <input type="hidden" name="pubkey" value={@person.pubkey} />
          <HueSwatches.hue_swatches
            id={"#{@id}-hues"}
            selected={@person.hue_override}
            theirs?
            theirs_hue={@person.published_hue}
            event="set_hue_override"
            values={%{"pubkey" => @person.pubkey}}
            aria-label="Colour"
          />
        </form>
      </Settings.settings_field>

      <Settings.settings_row
        label="Hide"
        description="Keeps their activity off the Feed, titles and the Friends grid."
        checked={@person.hidden}
        event="set_hidden"
        event_value={%{"pubkey" => @person.pubkey, "hide" => to_string(not @person.hidden)}}
      />

      <div class="flex items-center justify-between gap-2 pt-1" data-role="foot">
        <span class="text-sm text-base-content/65">
          <code>{@person.short_npub}</code> · {provenance(@person)}
        </span>
        <.button
          :if={@person.friend?}
          variant="dismiss"
          size="sm"
          phx-click="remove_friend"
          phx-value-pubkey={@person.pubkey}
          data-nav-item
          tabindex="0"
        >
          Remove friend
        </.button>
      </div>
    </Settings.settings_card>
    """
  end

  # The name the override masks — the published one, else Unnamed — as
  # the field's placeholder; never a literal here.
  defp masked_name(%Person{} = person), do: Format.person_name(%{person | name_override: nil})

  # How the reader came to follow the person: the day they added them,
  # else the relay whose members they follow.
  defp provenance(%Person{friend?: true, added_on: %Date{} = added_on}),
    do: "added " <> Calendar.strftime(added_on, "%b %-d")

  defp provenance(%Person{} = person), do: "on " <> Enum.join(Person.member_hosts(person), ", ")
end
```

- [ ] **Step 4: Run; passes**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/components/social/reader_view_test.exs`
Expected: 6 tests, 0 failures.

- [ ] **Step 5: The story**

`storybook/social/reader_view.story.exs`:

```elixir
defmodule MediaCentaurWeb.Storybook.Social.ReaderView do
  @moduledoc """
  The reader's view of one person (UIDR-054): the Settings-kit card on
  the person page's right — Name with Rename over the name it masks,
  Show their picture, Colour with Theirs first, Hide — and the foot: the
  key, how the reader follows them, Remove friend for a friend. Never
  for the reader's own.
  """

  use PhoenixStorybook.Story, :component

  alias MediaCentaur.Social.Person

  def function, do: &MediaCentaurWeb.Components.Social.ReaderView.reader_view/1
  def render_source, do: :function
  def layout, do: :one_column
  def template, do: ~s(<div class="w-[440px]"><.psb-variation/></div>)

  defp friend do
    %Person{
      pubkey: "f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9",
      name_override: "Sample Friend",
      own?: false,
      friend?: true,
      short_npub: "npub1lyy9…8z4h",
      added_on: ~D[2026-08-30]
    }
  end

  def variations do
    [
      %Variation{
        id: :friend,
        description: "A friend: the common state — nothing published yet, the picture switch on over the letter, Theirs the default hue, Hide off, Remove friend",
        attributes: %{id: "rv-friend", person: friend()}
      },
      %Variation{
        id: :published_name,
        description: "A friend who published a name: the override in the field, the published name as its placeholder",
        attributes: %{id: "rv-published", person: %{friend() | published_name: "Ada"}}
      },
      %Variation{
        id: :picture_off,
        description: "The picture switch off",
        attributes: %{id: "rv-picture-off", person: %{friend() | show_avatar: false}}
      },
      %Variation{
        id: :hue_override,
        description: "A friend who published Rose, overridden with Teal: Theirs in Rose, Teal pressed",
        attributes: %{id: "rv-hue", person: %{friend() | published_hue: 12, hue_override: 195}}
      },
      %Variation{
        id: :member,
        description: "A member followed through a relay set to Everyone on this relay: the foot names the relay, no Remove friend",
        attributes: %{
          id: "rv-member",
          person: %{friend() | friend?: false, added_on: nil, member_of: ["wss://group.example/"], name_override: nil, published_name: "Sample Member"}
        }
      },
      %Variation{
        id: :hidden,
        description: "A hidden person: Hide on",
        attributes: %{id: "rv-hidden", person: %{friend() | hidden: true}}
      }
    ]
  end
end
```

Add to `storybook/social/_social.index.exs`: `def entry("reader_view"), do: [icon: {:fa, "sliders", :thin}, name: "Reader's view"]`.

- [ ] **Step 6: Run the story tests; commit**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/storybook_compile_test.exs test/media_centaur_web/storybook_render_test.exs`
Expected: 0 failures.

```bash
git add lib/media_centaur_web/components/social/reader_view.ex storybook/social test/media_centaur_web/components/social/reader_view_test.exs
git commit -m "feat(social): the reader's view of a person, from the Settings kit"
```

---

### Task 6: The route, `PersonPage`, and the `:person` action

**Files:**
- Modify: `lib/media_centaur_web/router.ex:51`
- Create: `lib/media_centaur_web/live/social_live/person_page.ex`
- Modify: `lib/media_centaur_web/live/social_live.ex`
- Modify: `assets/css/app.css` (after `.friends-grid`)
- Test: `test/media_centaur_web/live/social_live/person_page_test.exs` (new), `test/media_centaur_web/live/social_live_test.exs`, `test/media_centaur_web/page_smoke_test.exs`

- [ ] **Step 1: The pure half's failing test**

```elixir
defmodule MediaCentaurWeb.SocialLive.PersonPageTest do
  use MediaCentaur.Case, async: true

  import MediaCentaur.SocialRows, only: [person: 1, own_person: 0]

  alias MediaCentaur.Social
  alias MediaCentaurWeb.SocialLive.PersonPage

  @friend "f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9"

  defp people, do: Map.new([person("Nick"), own_person()], &{&1.pubkey, &1})

  test "path/1: you for the reader, the npub for anyone else" do
    assert PersonPage.path(own_person()) == "/social/friends/you"
    assert PersonPage.path(person("Nick")) == "/social/friends/" <> Social.to_npub(@friend)
  end

  test "find/2: you is the reader's own; an npub or hex key is that person; a bad key or a stranger is nil" do
    assert %{own?: true} = PersonPage.find("you", people())
    assert %{pubkey: @friend} = PersonPage.find(Social.to_npub(@friend), people())
    assert %{pubkey: @friend} = PersonPage.find(@friend, people())
    assert PersonPage.find("npub1nope", people()) == nil
    assert PersonPage.find("c6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5", %{}) == nil
    assert PersonPage.find("you", Map.delete(people(), own_person().pubkey)) == nil
  end
end
```

- [ ] **Step 2: Run; fails (`PersonPage` undefined)**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/social_live/person_page_test.exs`

- [ ] **Step 3: The route**

In `lib/media_centaur_web/router.ex` after `live "/social/friends", SocialLive, :friends` add:

```elixir
      live "/social/friends/:key", SocialLive, :person
```

- [ ] **Step 4: `PersonPage`**

```elixir
defmodule MediaCentaurWeb.SocialLive.PersonPage do
  @moduledoc """
  The person page (UIDR-054): one page per known person, the reader
  included, at `/social/friends/<npub>` and `/social/friends/you`.

  The pure half: `path/1`, a person's address, and `find/2`, the person
  an address's key names among the known people (`Social.people/0`'s
  map, the hidden included) — `you` is the reader's own, else the key
  parsed as npub or hex; nil when nobody known holds it, which the page
  answers by returning to Friends.

  The drawn half, `person_page/1`: the back row, the head (the identity
  tile at 48 and the name), then the person's activity as the Feed's
  rows folded one per title — `People`'s acts, each carrying its `row`,
  drawn by `FeedRow` without the identity tile — beside the reader's
  view (`ReaderView`) for a friend or a member. The reader's own page
  has no card, only the pointer to Settings → Social. A hidden person's
  rows are never loaded (hidden means off everything), so their page is
  the head and the card over the hidden empty state; a shown person with
  no acts reads *Nothing yet*. Two nav zones: `person_rows`, the back
  row and the rows as a tree; `person_view`, the card's controls.
  """

  use Phoenix.Component
  use Phoenix.VerifiedRoutes, endpoint: MediaCentaurWeb.Endpoint, router: MediaCentaurWeb.Router

  import MediaCentaurWeb.CoreComponents, only: [icon: 1]

  alias MediaCentaur.Format
  alias MediaCentaur.Social
  alias MediaCentaur.Social.Person
  alias MediaCentaurWeb.Components.Social.FeedRow
  alias MediaCentaurWeb.Components.Social.IdentityTile
  alias MediaCentaurWeb.Components.Social.ReaderView
  alias MediaCentaurWeb.SocialLive.People.Card

  @doc "The address of a person's page: `you` for the reader, else their npub."
  @spec path(Person.t()) :: String.t()
  def path(%Person{own?: true}), do: ~p"/social/friends/you"
  def path(%Person{pubkey: pubkey}), do: ~p"/social/friends/#{Social.to_npub(pubkey)}"

  @doc "The person `key` names among `people` (pubkey → person): the reader's own for `you`, else the key parsed as npub or hex; nil when nobody known holds it."
  @spec find(String.t(), %{optional(String.t()) => Person.t()}) :: Person.t() | nil
  def find("you", people), do: Enum.find_value(people, fn {_pubkey, person} -> person.own? && person end)

  def find(key, people) do
    case Social.parse_pubkey(key) do
      {:ok, pubkey} -> Map.get(people, pubkey)
      {:error, :invalid_pubkey} -> nil
    end
  end

  attr :person, Person, required: true, doc: "the person the address names"
  attr :card, Card, default: nil, doc: "their card from `People.build/3`; nil for a hidden person, whose rows are never loaded"

  def person_page(assigns) do
    assigns =
      assign(assigns,
        name: Format.person_name(assigns.person),
        acts: if(assigns.card, do: assigns.card.acts, else: [])
      )

    ~H"""
    <div
      id="person-page"
      class="person-page"
      data-component="person-page"
      data-own={@person.own?}
      data-hidden={@person.hidden}
    >
      <div class="min-w-0" data-nav-zone="person_rows">
        <.link
          id="person-page-back"
          patch={~p"/social/friends"}
          class="mb-4 inline-flex items-center gap-1.5 rounded-md px-1 text-sm text-base-content/60 hover:text-base-content"
          data-nav-item
          tabindex="0"
        >
          <.icon name="hero-chevron-left" class="size-3.5" /> Friends
        </.link>

        <header class="flex items-center gap-3.5 px-1" data-role="head">
          <IdentityTile.identity_tile {IdentityTile.person_attrs(@person)} size={48} />
          <h2 class="min-w-0 flex-1 truncate text-xl font-semibold leading-8" data-role="name">
            {@name}
          </h2>
        </header>

        <div :if={@acts != []} id="person-rows" class="mt-3 divide-y divide-base-content/10">
          <FeedRow.feed_row :for={act <- @acts} entry={act} />
        </div>
        <p
          :if={@acts == [] and not @person.hidden}
          id="person-rows-empty"
          class="mt-6 px-4 text-sm text-base-content/65"
        >
          Nothing yet.
        </p>
        <p
          :if={@person.hidden}
          id="person-rows-hidden"
          class="mt-6 max-w-[60ch] px-4 text-sm text-base-content/65"
        >
          Hidden. Their activity is kept off the Feed, titles and Friends. Switch Hide off to see it here.
        </p>
        <p :if={@person.own?} id="person-settings-pointer" class="mt-6 px-4 text-xs text-base-content/55">
          Your name, picture and colour are under <.link
            navigate={~p"/settings?section=social"}
            class="link link-primary"
          >Settings → Social</.link>.
        </p>
      </div>

      <div :if={not @person.own?} class="person-page-side" data-nav-zone="person_view">
        <ReaderView.reader_view person={@person} />
      </div>
    </div>
    """
  end
end
```

- [ ] **Step 5: Run the pure test; passes**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/social_live/person_page_test.exs`
Expected: 2 tests, 0 failures.

- [ ] **Step 6: The page tests, failing first** — append a `describe "person page"` to `test/media_centaur_web/live/social_live_test.exs` (inside the module, after the friends-tab describe; it reuses `@friend_secret`, `@friend_pubkey`, `signed/3` and `friend_profile/4`, so copy those four definitions into this describe as the feed-tab describe does):

```elixir
  describe "person page" do
    @friend_secret Secret.wrap(String.duplicate("0", 63) <> "3")
    @friend_pubkey "f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9"

    defp friend_path, do: "/social/friends/" <> Social.to_npub(@friend_pubkey)

    defp signed_by_friend(kind, title, opts),
      do: Event.sign(Translation.to_event(kind, title, opts, @friend_pubkey), @friend_secret)

    defp friend_profile_event(name, hue),
      do:
        Event.sign(
          ProfileTranslation.to_event(%{name: name, avatar: nil, hue: hue}, @friend_pubkey, 1_700_000_000),
          @friend_secret
        )

    test "a friend's page: the head, one row per title with every act's glyph and the review's words, the reader's view; a series at its latest episode",
         %{conn: conn} do
      Identity.ensure()
      {:ok, _friend} = Social.add_friend(@friend_pubkey, "Nick")
      movie = Title.new!(%{tmdb_id: 777, media_type: :movie, name: "Sample Movie 777"})
      show = Title.new!(%{tmdb_id: 1399, media_type: :tv_series, name: "Sample Show"})

      {:ok, watched} = Activities.ingest(signed_by_friend(:watched, movie, []))
      {:ok, reviewed} = Activities.ingest(signed_by_friend(:review, movie, text: "Yes.", sentiment: :love))
      {:ok, _show_review} = Activities.ingest(signed_by_friend(:review, show, text: "Slow.", sentiment: nil))

      {:ok, episode_watched} =
        Activities.ingest(
          signed_by_friend(:watched, show, episode: %Episode{season_number: 1, episode_number: 7, name: "Sample Episode"})
        )

      backdate(watched, :acted_at, ~U[2026-09-01 09:00:00Z])
      backdate(reviewed, :acted_at, ~U[2026-09-01 10:00:00Z])

      {:ok, view, _html} = live(conn, friend_path())

      assert has_element?(view, "#person-page [data-role='head'] h2", "Nick")
      assert has_element?(view, "#person-page [data-component='identity-tile'][data-size='48']")
      assert has_element?(view, "[data-nav-zone='zone-tabs'] a.zone-tab-active", "Friends")
      assert has_element?(view, "#person-page-back[href='/social/friends']", "Friends")

      # Two titles, two rows, the series first (newest act); no identity tile on a row.
      assert ids(view, "#person-rows [data-component='feed-row']") == [
               "person-row-#{episode_watched.id}",
               "person-row-#{reviewed.id}"
             ]

      refute has_element?(view, "#person-rows [data-component='identity-tile']")

      show_row = "#person-row-#{episode_watched.id}"
      assert has_element?(view, show_row <> " [data-role='who']", "watched S01E07 of")
      assert has_element?(view, show_row <> " [data-role='episode']", "Sample Episode")
      assert has_element?(view, show_row <> " [data-role='text']", "Slow.")
      assert has_element?(view, show_row <> " [data-role='who'] .social-glyph[data-flag='review']")
      assert has_element?(view, show_row <> " [data-role='who'] .social-glyph[data-flag='watched']")

      movie_row = "#person-row-#{reviewed.id}"
      assert has_element?(view, movie_row <> " [data-role='who']", "reviewed")
      assert has_element?(view, movie_row <> " [data-role='who'] .social-glyph[data-flag='love']")
      assert has_element?(view, movie_row <> " [data-role='who'] .social-glyph[data-flag='watched']")
      assert has_element?(view, movie_row <> " [data-role='text']", "Yes.")
      assert has_element?(view, movie_row <> " button", "Ignore")

      # The card beside the rows.
      assert has_element?(view, "[data-nav-zone='person_view'] [data-component='reader-view'] h3", "Your view of Nick")
      assert has_element?(view, "[data-component='reader-view'] button", "Remove friend")

      # A row's press opens the modal speaking for the newest act on the title.
      view |> element(movie_row) |> render_click()
      assert_patch(view, friend_path() <> "?title=movie-777&activity=#{reviewed.id}")
      assert has_element?(view, "#detail-note", "Yes.")
      render_hook(view, "close_title", %{})
      assert_patch(view, friend_path())

      await_supervised_tasks()
    end

    test "the controls on the page: rename, picture, colour and hide take effect without leaving; Remove friend returns to Friends",
         %{conn: conn} do
      Identity.ensure()
      {:ok, _friend} = Social.add_friend(@friend_pubkey, "Nick")
      {:ok, _profile} = Social.ingest_profile(friend_profile_event("Ada", 12))
      {:ok, view, _html} = live(conn, friend_path())
      tile = "#person-page [data-role='head'] [data-component='identity-tile']"

      view |> form("#reader-view-name-form", %{"name" => "Nicholas"}) |> render_submit()
      assert has_element?(view, "#person-page [data-role='head'] h2", "Nicholas")
      assert has_element?(view, "#reader-view-name-form input[name='name'][value='Nicholas']")

      view |> form("#reader-view-name-form", %{"name" => ""}) |> render_submit()
      assert has_element?(view, "#person-page [data-role='head'] h2", "Ada")
      assert has_element?(view, "#reader-view-name-form input[name='name'][placeholder='Ada']")

      view |> element("[data-component='reader-view'] [role='switch'][phx-click='set_show_avatar']") |> render_click()
      assert %{show_avatar: false} = Social.contact_by_pubkey(@friend_pubkey)
      assert has_element?(view, "[role='switch'][phx-click='set_show_avatar'][aria-checked='false']")

      assert has_element?(view, tile <> "[data-hue='12']")
      view |> element("#reader-view-hue-form button[data-hue='195']") |> render_click()
      assert has_element?(view, tile <> "[data-hue='195']")
      view |> form("#reader-view-hue-form", %{"hue" => "100"}) |> render_change(%{"_target" => ["hue"]})
      assert has_element?(view, tile <> "[data-hue='100']")
      view |> element("#reader-view-hue-form button[data-role='theirs']") |> render_click()
      assert has_element?(view, tile <> "[data-hue='12']")

      view |> element("[data-component='reader-view'] [role='switch'][phx-click='set_hidden']") |> render_click()
      render_until(view, fn _html -> has_element?(view, "#person-rows-hidden") end)
      assert has_element?(view, "#person-page[data-hidden]")
      assert has_element?(view, "[role='switch'][phx-click='set_hidden'][aria-checked='true']")

      view |> element("[data-component='reader-view'] [role='switch'][phx-click='set_hidden']") |> render_click()
      render_until(view, fn _html -> not has_element?(view, "#person-rows-hidden") end)
      assert has_element?(view, "#person-rows-empty", "Nothing yet.")

      view |> element("[data-component='reader-view'] button", "Remove friend") |> render_click()
      assert_redirect(view, "/social/friends")
      assert Social.list_friends() == []
    end

    test "a member's page has the card without Remove friend; a hidden person's page shows the hidden state", %{conn: conn} do
      Identity.ensure()
      {:ok, _relay} = Social.add_relay("wss://group.example", :members)
      :ok = Social.note_member("wss://group.example", @friend_pubkey)
      {:ok, _} = Activities.ingest(signed_by_friend(:listing, Title.new!(%{tmdb_id: 5, media_type: :movie, name: "Sample Movie 5"}), []))

      {:ok, view, _html} = live(conn, friend_path())
      assert has_element?(view, "[data-component='reader-view'] [data-role='foot']", "on group.example")
      refute has_element?(view, "[data-component='reader-view'] button", "Remove friend")
      assert has_element?(view, "#person-rows [data-component='feed-row']")

      {:ok, _contact} = Social.set_hidden(@friend_pubkey, true)
      {:ok, hidden, _html} = live(conn, friend_path())
      assert has_element?(hidden, "#person-rows-hidden")
      refute has_element?(hidden, "#person-rows")
      assert has_element?(hidden, "[role='switch'][phx-click='set_hidden'][aria-checked='true']")
    end

    test "the reader's own page: own acts in the second person, no card, the pointer to Settings", %{conn: conn} do
      {:ok, _review} = Activities.review(Title.new!(%{tmdb_id: 777, media_type: :movie, name: "Sample Movie 777"}), :like, "mine")
      {:ok, view, _html} = live(conn, "/social/friends/you")

      assert has_element?(view, "#person-page[data-own] [data-role='head'] h2", "You")
      assert has_element?(view, "#person-rows [data-role='who']", "reviewed")
      refute has_element?(view, "#person-rows button", "Ignore")
      refute has_element?(view, "[data-component='reader-view']")
      assert has_element?(view, "#person-settings-pointer a[href='/settings?section=social']")
    end

    test "a key nobody known holds returns to Friends with a flash; so does a friend removed in another tab", %{conn: conn} do
      Identity.ensure()
      {:ok, _friend} = Social.add_friend(@friend_pubkey, "Nick")

      {:error, {:live_redirect, %{to: "/social/friends", flash: flash}}} = live(conn, "/social/friends/npub1nope")
      assert flash["error"] =~ "No one by that key"

      {:ok, view, _html} = live(conn, friend_path())
      :ok = Social.remove_friend(@friend_pubkey)
      assert_redirect(view, "/social/friends")
    end

    test "a hex key resolves and patches to the one address, the npub", %{conn: conn} do
      Identity.ensure()
      {:ok, _friend} = Social.add_friend(@friend_pubkey, "Nick")
      {:ok, view, _html} = live(conn, "/social/friends/" <> @friend_pubkey)
      assert_patch(view, friend_path())
      assert has_element?(view, "#person-page [data-role='head'] h2", "Nick")
    end
  end
```

Replace the smoke test's entry `{"/social/friends?person=person-you", "social friends, a card opened"}` with `{"/social/friends/you", "the reader's person page"}` and add `{"/social/friends/#{Social.to_npub(@smoke_friend_pubkey)}", "a friend's person page"}` — the `for` runs at compile time, so interpolate with `Social.to_npub(@smoke_friend_pubkey)` directly in the list (add `alias MediaCentaur.Social` at the top if the file lacks it).

- [ ] **Step 7: Run; the page tests fail** (the route resolves but `person_page` is not rendered and `person` is unassigned).

- [ ] **Step 8: `SocialLive`**

Aliases: `alias MediaCentaurWeb.SocialLive.PersonPage` and `alias MediaCentaur.Social.Person`.

Mount assigns: add `person: nil, person_card: nil, person_key: nil`.

`handle_params`:

```elixir
  @impl true
  def handle_params(params, _uri, socket) do
    scope = FeedEntries.parse_scope(params["scope"])
    landed = if socket.assigns.live_action == :friends, do: params["person"]

    {:noreply,
     socket
     |> reset_head_on_scope_change(scope)
     |> assign(feed_scope: scope, landed_person: landed, person_key: params["key"])
     |> open_landed(landed)
     |> project()
     |> leave_if_gone()
     |> canonical_address()}
  end

  # A person page has one address: a key that resolved by hex patches to the npub.
  defp canonical_address(%{assigns: %{live_action: :person, person: %Person{} = person, person_key: key}} = socket) do
    path = PersonPage.path(person)
    if path == ~p"/social/friends/#{key}", do: socket, else: push_patch(socket, to: path)
  end

  defp canonical_address(socket), do: socket

  # A person page whose key nobody known holds — a bad address, or the
  # friend removed meanwhile — returns to Friends.
  defp leave_if_gone(%{assigns: %{live_action: :person, person: nil}} = socket) do
    socket
    |> put_flash(:error, "No one by that key is on your list")
    |> push_navigate(to: ~p"/social/friends")
  end

  defp leave_if_gone(socket), do: socket
```

`load_people` reads the known people once:

```elixir
  defp load_people(socket) do
    known = Social.people()
    people = Map.reject(known, fn {_pubkey, person} -> person.hidden end)

    assign(socket,
      known_people: known,
      people_by_pubkey: people,
      hidden_people: People.hidden(known),
      friend_count: Social.count_followed(people)
    )
  end
```

`project/1` ends with `|> assign_person(people)` — change its `assign(socket, ...)` to `socket |> assign(...) |> assign_person(people)` and add:

```elixir
  # The person page's person and card, re-resolved on every projection so
  # a change in another tab lands: hidden takes their card away (the rows
  # are never loaded), removed leaves nobody holding the key.
  defp assign_person(%{assigns: %{live_action: :person, person_key: key}} = socket, cards)
       when is_binary(key) do
    person = PersonPage.find(key, socket.assigns.known_people)
    card = person && Enum.find(cards, &(&1.person.pubkey == person.pubkey))
    assign(socket, person: person, person_card: card)
  end

  defp assign_person(socket, _cards), do: assign(socket, person: nil, person_card: nil)
```

The `@people_tags` handler: `{:noreply, socket |> load_people() |> load_activities() |> leave_if_gone()}`.

`remove_friend`:

```elixir
  def handle_event("remove_friend", %{"pubkey" => pubkey}, socket) do
    :ok = Social.remove_friend(pubkey)

    if socket.assigns.live_action == :person,
      do: {:noreply, push_navigate(socket, to: ~p"/social/friends")},
      else: {:noreply, socket}
  end
```

The toolbar's lookup serves both lists — rename `feed_entry/2` to `shown_entry/2` at its three call sites and define:

```elixir
  # The row a toolbar verb names: on the Feed, or on the person page.
  defp shown_entry(socket, id),
    do: Enum.find(socket.assigns.feed, &(&1.activity_id == id)) || person_row(socket, id)

  defp person_row(%{assigns: %{person_card: %People.Card{acts: acts}}}, id),
    do: Enum.find(acts, &(&1.activity_id == id))

  defp person_row(_socket, _id), do: nil
```

`social_path/2`: add before the `:friends` clause

```elixir
  defp social_path(%{assigns: %{live_action: :person, person_key: key}}, params),
    do: ~p"/social/friends/#{key}?#{params}"
```

`current_path/1`: add `defp current_path(:person), do: "/social/friends"` before the catch-all. The layout: `full_width={@live_action in [:friends, :person]}`. The tab strip: `active={tab_for(@live_action)}` with

```elixir
  # The person page sits under Friends.
  defp tab_for(:person), do: :friends
  defp tab_for(action), do: action
```

Render: after the `:friends` block's closing `</div>` and before the rail, add

```heex
              <PersonPage.person_page
                :if={@live_action == :person and @person}
                person={@person}
                card={@person_card}
              />
```

Moduledoc: after the Friends paragraph add "**The person page** (`/social/friends/<npub>`, `/social/friends/you`; `SocialLive.PersonPage`, UIDR-054) — one person's acts as the Feed's rows folded one per title (`People`'s acts, each with its `row`) beside the reader's view of them (`ReaderView`: `set_friend_name`, `set_show_avatar`, `set_hue_override`, `set_hidden`, `remove_friend`, which returns to Friends). The key is read off the address in `handle_params` and resolved on every projection (`PersonPage.find/2` over the known people, the hidden included); a key nobody holds returns to Friends."

- [ ] **Step 9: CSS** — after the `.friends-grid` container query in `assets/css/app.css`:

```css
/* ── The person page (UIDR-054) ── the rows beside the reader's view on
   the Friends tab's full width: one column, the card under the rows,
   until the grid's own fold; past it the card at 440, sticky. */
.person-page {
  display: grid;
  grid-template-columns: minmax(0, 1fr);
  gap: 24px 32px;
  align-items: start;
}

@container social (min-width: 1700px) {
  .person-page {
    grid-template-columns: minmax(0, 1fr) 440px;
  }

  .person-page-side {
    position: sticky;
    top: 24px;
  }
}
```

- [ ] **Step 10: Run the page, smoke and Social tests**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/social_live_test.exs test/media_centaur_web/page_smoke_test.exs test/media_centaur_web/live/social_live`
Expected: 0 failures. If the Social page test's "a friend's withdrawal removes the entry without a reload" or any `?person=` test fails on `known_people`, it is the mount path: `load_people` must run before `load_activities` (it does in `mount/3`; keep that order).

- [ ] **Step 11: Commit**

```bash
git add lib/media_centaur_web/router.ex lib/media_centaur_web/live/social_live.ex lib/media_centaur_web/live/social_live/person_page.ex assets/css/app.css test/media_centaur_web
git commit -m "feat(social): the person page at /social/friends/<key>"
```

---

### Task 7: Keyboard and gamepad on the person page

**Files:**
- Modify: `assets/js/input/config.js` (`contextSelectors`, `instanceTypes`, `layouts.social`, `cursorStartPriority.social`)
- Modify: `assets/js/input/social_behavior.js` (the comment)
- Test: `assets/js/input/__tests__/social_behavior.test.js`

- [ ] **Step 1: The failing test** — replace the layout test in `social_behavior.test.js`:

```js
  test("the body under the zone tabs is the Feed's rows, the person cards, or the person page's rows over its card", () => {
    expect(inputConfig.layouts.social).toEqual({
      zone_tabs: { down: ["feed", "people", "person_rows", "person_view"] },
      feed: { up: ["zone_tabs"] },
      people: { up: ["zone_tabs"] },
      person_rows: { up: ["zone_tabs"], down: ["person_view"] },
      person_view: { up: ["person_rows", "zone_tabs"] },
      sidebar: { right: ["feed", "people", "person_rows", "person_view", "zone_tabs"] },
    })
    expect(inputConfig.cursorStartPriority.social).toEqual([
      "feed", "people", "person_rows", "person_view", "zone_tabs", "sidebar",
    ])

    const friends = buildNavGraph("social", { zone_tabs: 2, title_rows: 6, people: 3, sidebar: 4 }, inputConfig)
    expect(friends.zone_tabs.down).toBe("people")
    expect(friends.sidebar.right).toBe("people")

    const feed = buildNavGraph("social", { zone_tabs: 2, feed: 20, sidebar: 4 }, inputConfig)
    expect(feed.zone_tabs.down).toBe("feed")
    expect(feed.feed.up).toBe("zone_tabs")
    expect(feed.sidebar.right).toBe("feed")

    // The person page: DOWN past the last row enters the card; UP from the card's top returns to the rows.
    const person = buildNavGraph("social", { zone_tabs: 2, person_rows: 5, person_view: 14, sidebar: 4 }, inputConfig)
    expect(person.zone_tabs.down).toBe("person_rows")
    expect(person.person_rows.down).toBe("person_view")
    expect(person.person_view.up).toBe("person_rows")
    expect(person.sidebar.right).toBe("person_rows")

    // The reader's own page has no card: DOWN at the last row is a wall.
    const own = buildNavGraph("social", { zone_tabs: 2, person_rows: 3, sidebar: 4 }, inputConfig)
    expect(own.person_rows.down).toBeUndefined()
  })

  test("the person page's rows are a tree like the Feed's; its card walks like a Settings card", () => {
    expect(inputConfig.instanceTypes.person_rows).toBe("tree")
    expect(inputConfig.instanceTypes.person_view).toBe("grid")
    expect(inputConfig.contextSelectors.person_rows).toBe("[data-nav-zone='person_rows'] [data-nav-item]")
    expect(inputConfig.contextSelectors.person_view).toBe("[data-nav-zone='person_view'] [data-nav-item]")
  })
```

- [ ] **Step 2: Run; fails**

Run: `bun test assets/js/input/__tests__/social_behavior.test.js`
Expected: the layout `toEqual` fails.

- [ ] **Step 3: Config**

In `contextSelectors` after the `feed` line:
```js
    person_rows: "[data-nav-zone='person_rows'] [data-nav-item]",
    person_view: "[data-nav-zone='person_view'] [data-nav-item]",
```
In `instanceTypes` after `feed: Context.TREE,`:
```js
    // The person page: the back row and the rows as a tree (a row's verbs
    // are its sub-items), the reader's view a vertical walk of its controls.
    person_rows: Context.TREE,
    person_view: Context.GRID,
```
`layouts.social`:
```js
    // Social: the zone-tabs strip above one body — the Feed's rows on Feed,
    // the person cards on Friends, the person page's rows over its card. The
    // Feed's rail of people is not a nav zone.
    social: {
      zone_tabs:   { down: ["feed", "people", "person_rows", "person_view"] },
      feed:        { up: ["zone_tabs"] },
      people:      { up: ["zone_tabs"] },
      person_rows: { up: ["zone_tabs"], down: ["person_view"] },
      person_view: { up: ["person_rows", "zone_tabs"] },
      sidebar:     { right: ["feed", "people", "person_rows", "person_view", "zone_tabs"] },
    },
```
`cursorStartPriority.social: ["feed", "people", "person_rows", "person_view", "zone_tabs", "sidebar"]`.

`social_behavior.js` comment: "Layout: the zone-tabs strip above one body — the `feed` tree of rows on Feed, the `people` shelf of person cards on Friends, the `person_rows` tree over the `person_view` card on a person page (the Feed's rail is not a nav zone)."

- [ ] **Step 4: Run all input tests; pass**

Run: `bun test assets/js/input/`
Expected: 0 failures.

- [ ] **Step 5: Trace it on the dev server** (the dev server reloads the checkout's code; the profile gate passes for headless tools):

Run: `~/scripts/agents/mc-nav-trace --url http://127.0.0.1:2160/social/friends/you 'Down Down'`
Expected: focus lands on the back row, then the first row; no clipped focus reported. Then on a friend's page (`/social/friends/<npub>` of a dev friend) `Down Down Down Down Down Down`: after the last row, focus enters the card's Name field.

- [ ] **Step 6: Commit**

```bash
git add assets/js/input
git commit -m "feat(social): the person page navigates by keyboard and gamepad"
```

---

### Task 8: Retire the opened card; the cards link to the page

**Files:**
- Modify: `lib/media_centaur_web/components/social/person_card.ex`
- Modify: `lib/media_centaur_web/live/social_live.ex`
- Modify: `assets/css/app.css` (`.person-card` rules)
- Modify: `storybook/social/person_card.story.exs`
- Test: `test/media_centaur_web/components/social/person_card_test.exs`, `test/media_centaur_web/live/social_live_test.exs`

- [ ] **Step 1: Story first** — in `person_card.story.exs` delete the variations `:page_opened`, `:page_opened_member`, `:page_opened_avatar`, `:page_opened_avatar_hidden`, `:page_opened_hue`, `:page_you_opened`; add `patch: "/social/friends/npub1lyy9kqv0jtcg9fy5fzlmt8e5whmr7d8evdw6a9f4j0ldrq3upkgqe2z8kh"` to every remaining variation's `attributes` map (the `one_flag_each/1` helper included). Moduledoc: "... (900, a card on the inset tone, five acts). The head is a link to the person's page (UIDR-054); a poster opens the title with the newest act on it. A person with no acts is a tile and a name; nothing says what a person withholds."

- [ ] **Step 2: Component tests** — in `person_card_test.exs` delete the tests "an opened page card shows every act...", "the opened foot carries your name...", "the opened foot carries the avatar switch...", "the foot's Colour row...", "the foot's placeholder is the published name...", "the card the address names takes focus on mount...", "the opened foot says how the reader follows them...". Add `patch: "/social/friends/you"` to every `render(...)` call's attrs. Replace "the rail shows three acts and navigates; the page shows five and opens in place" with:

```elixir
  test "the rail shows three acts and the page five; the head is a link to the person's page, the root presses nothing" do
    rail = render(person: friend(), acts: acts_of(7), width: :rail, patch: "/social/friends/npub1x")
    page = render(person: friend(), acts: acts_of(7), width: :page, patch: "/social/friends/npub1x")

    assert rail |> acts() |> Enum.count() == 3
    assert page |> acts() |> Enum.count() == 5

    for html <- [rail, page] do
      head = LazyHTML.query(html, "a[data-role='head']")
      assert LazyHTML.attribute(head, "href") == ["/social/friends/npub1x"]
      assert LazyHTML.attribute(head, "data-phx-link") == ["patch"]
      assert LazyHTML.attribute(head, "data-nav-item") == [""]
      assert html |> LazyHTML.query("[data-component='person-card']") |> LazyHTML.attribute("phx-click") == []
      assert html |> LazyHTML.query("[data-component='person-card']") |> LazyHTML.attribute("role") == []
      assert Enum.empty?(LazyHTML.query(html, "footer, [data-role='act-row']"))
    end

    assert rail |> LazyHTML.query("[data-component='person-card']") |> LazyHTML.attribute("data-width") == ["rail"]
  end
```

- [ ] **Step 3: The component** — rewrite `person_card/1`'s attrs and body:

```elixir
  attr :person, Person, required: true, doc: "the person as the reader sees them"
  attr :acts, :list, required: true, doc: "the person's rows (`FeedEntry`, one per title), newest first; `[]` for a quiet person"
  attr :width, :atom, required: true, values: [:rail, :page]
  attr :patch, :string, required: true, doc: "the person page's address (`PersonPage.path/1`); the head links to it"

  def person_card(assigns) do
    assigns =
      assign(assigns,
        id: dom_id(assigns.person),
        name: Format.person_name(assigns.person),
        shown: Enum.take(assigns.acts, @cap[assigns.width]),
        subject: ActivityWords.subject(assigns.person),
        page?: assigns.width == :page
      )

    ~H"""
    <section
      id={@id}
      class={["person-card", @page? && "person-card-page"]}
      data-component="person-card"
      data-width={@width}
      data-own={@person.own?}
    >
      <.link
        patch={@patch}
        class="flex items-center gap-3 rounded-md"
        data-role="head"
        data-nav-item
        tabindex="0"
      >
        <IdentityTile.identity_tile {IdentityTile.person_attrs(@person)} size={tile_size(@width)} />
        <h2
          class={[
            "min-w-0 flex-1 truncate font-semibold",
            if(@page?, do: "text-xl leading-8", else: "text-lg leading-7")
          ]}
          data-role="name"
        >
          {@name}
        </h2>
      </.link>

      <div
        :if={@acts != []}
        class={["acts-strip", if(@page?, do: "mt-4", else: "mt-2 pl-13")]}
        data-role="acts"
      >
        <button
          :for={row <- @shown}
          id={"#{@id}-act-#{TitleRef.param(row.ref)}"}
          type="button"
          class="act"
          data-tip={tip(@name, row, @subject)}
          aria-label={tip(@name, row, @subject)}
          phx-click="open_title"
          phx-value-ref={TitleRef.param(row.ref)}
          phx-value-activity={row.activity_id}
          data-entity-id={TitleRef.param(row.ref)}
          data-flags={Enum.map_join(row.glyphs, " ", &elem(&1, 0))}
          data-nav-item
          tabindex="0"
        >
          <SocialGlyph.social_glyphs flags={flags(row)} grades={Map.new(row.glyphs)} class="act-slots" aria-hidden="true" />
          <img
            :if={row.poster_url}
            src={act_poster_src(row.poster_url, @width)}
            alt={row.title.name}
            loading="eager"
            decoding="sync"
          />
          <span :if={!row.poster_url} class="act-empty text-sm leading-tight text-base-content/65">
            {row.title.name}
          </span>
        </button>
      </div>
    </section>
    """
  end
```

Delete `shown/3`, `masked_name/1`, `provenance/1`, the `button`, `HueSwatches`, `Switch` and `JS` imports/aliases; keep `dom_id/1` (its doc becomes "The card's DOM id: `person-you` for the reader, else `person-` and the key's first eight hex digits; the hidden group's rows derive theirs from it."), `act_poster_src/2`, `tile_size/1`, `tip/3`, `flags/1`. Moduledoc: cut everything from "Its press opens the card in place" to the end of the foot's description and write: "Its head is a link to the person's page (`patch`, UIDR-054), where every act is a row and the reader's view lives. Pure rendering of a `Social.Person` and their rows: the head and every poster are nav items; a poster bubbles `open_title` with the title's ref and the activity."

- [ ] **Step 4: The page** — in `social_live.ex`:
  - delete the `toggle_person` and `open_person` handlers, `open_landed/2`, the `landed_person` and `opened_people` assigns and `landed` in `handle_params` (the `assign` there becomes `assign(feed_scope: scope, person_key: params["key"])`);
  - the grid: `<PersonCard.person_card :for={card <- @people} person={card.person} acts={card.acts} width={:page} patch={PersonPage.path(card.person)} />`;
  - the rail: `<PersonCard.person_card :for={card <- @rail.cards} person={card.person} acts={card.acts} width={:rail} patch={PersonPage.path(card.person)} />`;
  - moduledoc: replace "a press opens a card in place (`toggle_person`, the `opened_people` set), and `?person=<card id>` — where a rail card's press lands (`open_person`) — opens that card and hands it focus on mount. The opened card's foot carries ... Remove friend." with "a card's head links to the person's page (UIDR-054), as the rail's does."
  - the rail's comment: "A card's head links to the person's page."

- [ ] **Step 5: CSS** — in `app.css` remove `cursor: pointer;` from `.person-card`, and remove `.person-card-opened` and `.person-card-page.person-card-opened` from the two hover selectors (leave `:hover` and `:focus-within`).

- [ ] **Step 6: The Social page tests** — in `social_live_test.exs`:
  - "adds a friend by npub and name, shows their card, renames from the foot, and removes": cut from `# The foot is behind the card's press` to the end; append `assert has_element?(view, friend_card() <> " a[data-role='head'][href='" <> "/social/friends/" <> npub <> "']")`.
  - "adds a friend without a name ...": keep the add and Unnamed assertions; delete the foot's placeholder part (the page test covers it).
  - delete "the opened foot's switch hides a friend's picture...", "the foot's Colour row saves on the act...", "a press opens the card: every act...", "?person= opens that card...".
  - "Hide takes a friend off the tab and the feed; the hidden group shows them again": replace the two card-press lines with `{:ok, _contact} = Social.set_hidden(@friend_pubkey, true)` and keep the rest.
  - "a member's card names the relay and offers Hide, not Remove friend": replace the body with `assert has_element?(view, friend_card() <> " a[data-role='head'][href='/social/friends/" <> Social.to_npub(@friend_pubkey) <> "']")` and `refute has_element?(view, friend_card() <> " footer")`.
  - "a friend's card is their acts as posters...": cut from `# The opened card: one row per title` to `assert has_element?(view, "#detail-social .social-glyph[data-flag='love'][data-tip*='Sample Friend']")` inclusive, keeping `await_supervised_tasks()`; rename the test to drop "; an opened row opens the act".
  - the rail test: replace `view |> element(card) |> render_click()` and the `assert_redirect` with `assert has_element?(view, card <> " a[data-role='head'][href='/social/friends/" <> Social.to_npub(roster_pubkey(1)) <> "']")`.

- [ ] **Step 7: Run**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/components/social/person_card_test.exs test/media_centaur_web/live/social_live_test.exs test/media_centaur_web/page_smoke_test.exs test/media_centaur_web/storybook_render_test.exs`
Expected: 0 failures.

- [ ] **Step 8: Commit**

```bash
git add -A lib/media_centaur_web assets/css/app.css storybook/social test/media_centaur_web
git commit -m "refactor(social): the person card is its head and strip; the head links to the person page"
```

---

### Task 9: Records and docs

**Files:**
- Create: `decisions/user-interface/2026-10-21-054-the-person-page.md`
- Modify: `decisions/user-interface/2026-09-27-046-the-feed-is-the-apps-list-beside-a-rail-of-people.md`
- Modify: `docs/GLOSSARY.md`, `docs/social.md`, `docs/storybook.md`, `../media-centaur.wiki/Social.md`
- Run: `scripts/gen-decisions-index`

- [ ] **Step 1: UIDR-054**

```markdown
---
status: accepted
date: 2026-10-21
---
# A person has a page

Amends UIDR-046 (rule 5: the page card no longer opens in place; the Feed's glyph takes its grade). Design: `docs/superpowers/specs/2026-10-20-person-page-design.md`; mockups under `docs/superpowers/specs/2026-10-19-person-page-mockups/` (direction B, round 3). Plan: `docs/superpowers/plans/2026-10-21-person-page.md`.

## Context and Problem Statement

A friend's activity and the reader's settings for them lived inside a grid card that opened in place: opening reflowed the grid, the settings sat in a foot under one-line act rows that showed none of a review's words, and nothing had an address — a rail press landed on `?person=<card id>`, a second kind of navigation state beside the route. And the Feed, by design (UIDR-038), leaves watched activity out, so the app never said what a person is watching lately.

## Decision Outcome

The Social page has two projections of one activity list: by action over time (the Feed) and by person folded per title (the person card). **The person page is the second projection in full for one person, at an address.**

1. **The address.** `/social/friends/<npub>` for a friend or a member, `/social/friends/you` for the reader: a third live action on the Social LiveView. The grid card's head and the rail card's head are links to it. A key nobody known holds returns to Friends with a flash.
2. **The fold.** One row per title, newest act first: the newest act's verb, every act's glyph after it at its grade, the title and year, the episode's name on a series, the review's words in full, the time of the newest act. Watched rows are in: a series is one row at its latest episode (the store holds one watched row per person per title; the next episode replaces it) and rises as each episode lands. Never one row per episode.
3. **One row.** The Feed row draws both surfaces from one view-model: the author optional (no tile and no name on the page), the glyphs a list at grade, the episode, the toolbar's facts one value per title (`ToolbarSlots`). The Feed's glyph therefore takes its grade, the one glyph in the app that did not.
4. **The reader's view.** A Settings-kit card beside the rows, *Your view of <name>*: Name with Rename over the name it masks, Show their picture, Colour, Hide as a switch, the foot with the key, the provenance and Remove friend (a friend only). The card never pushes the rows down: at 440 beside them past the Friends grid's fold, under them below it. The reader's page has no card; a line points to Settings → Social.
5. **Hidden keeps meaning off everything.** A hidden person's rows are not loaded; their page is the head and the card with Hide on over a line that says so.

### Consequences

* Good, because a person has one place, reachable by link, refresh and the sidebar's URL memory.
* Good, because the page shows what a person is watching, which no surface did.
* Good, because the row, the fold and the toolbar's slots exist once each; the card lost a third of its markup.
* Bad, because the page is two nav zones side by side on a TV; the card's controls are a vertical walk.
* Bad, because the Friends grid's card no longer answers a press in place; the page is one navigation away.

## Anti-patterns

* **Doubled posters** — an acts strip over the rows, or two rows for a watched-and-reviewed title.
* **An episode diary** — one row per episode.
* **Settings over activity** — the card before or above the rows.
* **Two addresses** — a query parameter or an opened set that says which person is open.
* **A second row builder** — a copy of the row that pattern-matches the strip item.
```

- [ ] **Step 2: Amend UIDR-046** — set `amended: 2026-10-21` in the frontmatter and append:

```markdown
## Amendment 2026-10-21 — the page card links; the Feed's glyph takes its grade (UIDR-054)

Rule 5's "on the Friends page a press on the card opens it in place to every act as a row ... and, for a friend, the foot with the key, the added date and Remove friend" is retired: the card is the head and the strip at both widths, and the head links to the person's page, where every act is a row (the Feed row, folded one per title) and the reader's view lives. Rule 1's "the sentiment glyph after the verb" is now drawn at its grade like every other social glyph; the Feed was the one surface that drew a glyph plain regardless of count.
```

Then `scripts/gen-decisions-index`.

- [ ] **Step 3: Glossary** — under `## Social` in `docs/GLOSSARY.md` add rows:

```markdown
| **Person page** | One page per known person, the reader included, at `/social/friends/<npub>` or `/social/friends/you` (`SocialLive.PersonPage`): their activity folded one row per title on the left, the reader's view of them on the right. Not "profile", which within Social is the published profile and at the front door a viewer profile. UIDR-054. |
| **Reader's view** | The settings a reader keeps about one person that nobody else sees — the name, whether their picture shows, the colour, hidden — drawn as one Settings card headed *Your view of <name>* (`Components.Social.ReaderView`). UIDR-054. |
| **Fold** | The projection of a person's activity as one row per title, newest act first, every act on the title behind it (`SocialLive.People`): the person card's strip and the person page's rows are both the fold; the Feed is not. UIDR-054. |
| **Toolbar slots** | The two resolved positions of a row's toolbar, List and Download, and the three facts they come from (the rung, library ownership, the acquisition state): facts about the reader and a title, one value per title (`Components.Social.ToolbarSlots`). UIDR-054. |
```

- [ ] **Step 4: `docs/social.md`** — in the Friends bullet, replace from "Every poster and opened-card row opens the title modal" to the end of that bullet with:

"Every poster opens the title modal with `?title=<ref>&activity=<id>` so the modal speaks for that act; a card's head links to the **person page** (`/social/friends/<npub>`, `/social/friends/you`; `SocialLive.PersonPage`, UIDR-054): the person's acts as Feed rows folded one per title (`Act.row`, drawn by `FeedRow` without the identity tile — the newest act's verb, every flag at its grade, the episode's name on a series, the review's words) beside the reader's view (`Components.Social.ReaderView`, from the Settings kit): the reader's name for them (`Social.set_name_override/2`, `set_friend_name`), **Show their picture** (`Social.set_show_avatar/2`), **Colour** (`HueSwatches`, `Social.set_hue_override/2`), **Hide** as a switch (`Social.set_hidden/2`, which the hidden group's Show also sends), the key and provenance, and Remove friend for a friend (`Social.remove_friend/1`, which returns to Friends). A hidden person's page loads no rows. Delete on an own activity → `Activities.delete/1` lives in the modal."

- [ ] **Step 5: `docs/storybook.md`** — replace the two rows:

```markdown
| `social.feed_row/1` | ✅ covered | Every slot state, both subjects, the grade, no artwork, the person page's row and a series row, the hovered seat pinned |
| `social.person_card/1` | ✅ covered | Rail and page widths, each flag alone and together, the grade, quiet; the head links to the person page |
| `social.reader_view/1` | ✅ covered | A friend, a published name, the picture off, a hue override, a member, hidden |
```

- [ ] **Step 6: Wiki** — in `../media-centaur.wiki/Social.md`:
  - Feed section, last sentence: "Beside the Feed, a rail shows the same person cards the Friends tab has, three titles each, newest activity first; press a name to open that person's page."
  - Friends section: replace the paragraph beginning "Press a card to open it in place" with:

"Press a person's name to open their page. The left side is everything they did, one row per title, newest first: *watched S01E07 of Sample Show* with the episode's name, *reviewed Movie B* with every glyph for what they did with it and their review in full, *wants to watch Show F*. A series shows once, at the last episode they finished, and moves to the top each time they finish another, so you can see what a friend is watching lately. Press a row to open the title with that person's latest act at the top and the same actions as everywhere else. The right side is **Your view of** them, which only you see: your name for them (**Rename** saves it; the empty field shows the name it replaces, and saving it empty goes back to the name they publish), **Show their picture** (on by default; off, their initial stands in), **Colour** (**Theirs**, the first swatch, is the colour they chose), **Hide**, which takes their activity off every page (their card moves to **Hidden** at the end of the Friends tab, where **Show** brings it back; their page then says so until you switch Hide off), the key, *added* and the date for a friend or *on* the relay for someone you follow through a relay set to Everyone on this relay, and **Remove friend**, for a friend. Hiding someone is yours alone; they are not told. A friend who has shared nothing shows the name alone; nothing says what a person chooses not to share. A friend you removed keeps nothing on this tab; their past activity is kept but shown nowhere."

  - "**Your card**" paragraph: "**Your page** is your acts like anyone's ... behind the filled blue circle; its rows are in the second person (*want to watch Show F*, *reviewed Movie B*), and your name, picture and colour are under Settings → Social." Keep the Delete sentences.
  - "Adding a friend you already have changes nothing; rename them from their page."

```bash
cd ~/src/media-centaur/media-centaur.wiki && git add -A && git commit -m "wiki: the person page" && git push
```

- [ ] **Step 7: Commit the records**

```bash
git add decisions docs/GLOSSARY.md docs/social.md docs/storybook.md
git commit -m "docs(social): UIDR-054 the person page; UIDR-046 amended"
```

---

### Task 10: Precommit and the visual check

- [ ] **Step 1: Precommit**

Run: `~/scripts/agents/agent-mix precommit`
Expected: clean. Fix every warning and Credo finding (MC0009 wants a story for every component under `components/**`: `ToolbarSlots` has no `~H` so it is not a component; if the check flags it anyway, add the four `@storybook_status :skip` lines with reason "View-model struct, not a function component").

- [ ] **Step 2: Shoot the pages on the dev server**

```bash
~/scripts/agents/page-shot --url http://127.0.0.1:2160/social/friends/you --viewport 1920x1080 --wait-ms 3000 -o /tmp/person-you.png
~/scripts/agents/page-shot --url http://127.0.0.1:2160/social/friends --viewport 1920x1080 --wait-ms 3000 -o /tmp/friends.png
```

Then a friend's page: take the first `a[data-role='head']` href under `#friends-grid` that is not `/social/friends/you` (`chromium-probe http://127.0.0.1:2160/social/friends "[...document.querySelectorAll('#friends-grid a[data-role=head]')].map(a => a.getAttribute('href'))"`) and shoot it. Read the three PNGs. Check against the mockup: the rows carry no identity tile, a series row shows the episode's name, the card sits at 440 on the right at 1920, the grid card has no foot. A hover state cannot be captured; the story's `:hovered` variation covers the seat.

- [ ] **Step 3: Final commit if the check changed anything**

```bash
git add -A && git commit -m "fix(social): person page visual pass"
```

---

## Self-review

**Spec coverage.** The address (Task 6, 8), the fold (4), one row (2), the grade on the Feed (2), the reader's view (5), hidden pages (6), empty states (6), keyboard and gamepad (7), the grid and rail link (8), the person card trimmed (8), UIDR-046 amended and UIDR-054 (9), stories per component (2, 4, 5, 8), smoke (6), docs and wiki (9). Deferred items are untouched.

**Placeholders.** None; every code step carries its code. Step 8 of Task 2 and Step 6 of Task 8 name existing tests to edit by their titles, with the replacement given.

**Type consistency.** `FeedEntry` fields `author | subject | kind | episode | glyphs | text | slots` are used by the same names in `FeedEntries` (Task 2), `People` (Task 4), `FeedRow` (Task 2), `PersonPage` (Task 6) and every test and story. A card's `acts` are `FeedEntry` rows (Task 4), which `PersonCard` and `PersonPage` both read. `PersonPage.path/1` and `find/2` (Task 6) are what `SocialLive` (6, 8) calls. `ToolbarSlots.resolve/1` (Task 1) is called in Tasks 2 and 4.
