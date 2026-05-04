# Movie Cast Strip Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show a horizontal strip of cast cards (photo + actor + character) at the bottom of the movie detail modal, sourced from TMDB credits already returned by the existing client.

**Architecture:** Cast is stored as a JSON array column on `library_movies` — no person/credit normalization. TMDB profile photos are hotlinked from `image.tmdb.org/t/p/w185` (matching the existing review-UI pattern). A new `MediaCentarrWeb.Components.Detail.CastStrip` component renders the section, mounted by `DetailPanel` only when `entity.type == :movie`. A backfill maintenance action populates `cast` for movies imported before this change by re-fetching TMDB metadata in place (without disturbing watch state, files, or images).

**Tech Stack:** Elixir / Phoenix LiveView / Ecto / SQLite / Tailwind / DaisyUI / Phoenix Storybook / Jujutsu (jj) for VCS.

**Spec:** `docs/superpowers/specs/2026-05-04-movie-cast-strip-design.md`

---

## File Map

**Created:**
- `priv/repo/migrations/<timestamp>_add_cast_to_library_movies.exs` — adds `cast` column
- `lib/media_centarr_web/components/detail/cast_strip.ex` — new strip component
- `test/media_centarr_web/components/detail/cast_strip_test.exs` — component test
- `storybook/detail/cast_strip.story.exs` — story for the component catalog

**Modified:**
- `lib/media_centarr/library/movie.ex` — add `cast` field + include in changeset
- `lib/media_centarr/tmdb/mapper.ex` — add `extract_cast/1`, wire into `movie_attrs/3`
- `test/media_centarr/tmdb/mapper_test.exs` — assertions for extracted cast
- `lib/media_centarr_web/components/detail_panel.ex` — slot CastStrip below the play card section for movies
- `test/media_centarr_web/components/detail_panel_test.exs` — integration assertion
- `lib/media_centarr/maintenance.ex` — add `refresh_movie_cast/0`
- `lib/media_centarr_web/live/settings_live.ex` — add maintenance button + handler
- `storybook/detail/_detail.index.exs` — register the new story (if it lists entries explicitly)

---

## Task 1: TMDB Mapper — extract_cast

**Files:**
- Modify: `lib/media_centarr/tmdb/mapper.ex`
- Modify: `test/media_centarr/tmdb/mapper_test.exs`

- [ ] **Step 1.1: Add failing test for `extract_cast/1`**

Append a `describe "extract_cast/1"` block to `test/media_centarr/tmdb/mapper_test.exs`:

```elixir
describe "extract_cast/1" do
  test "extracts cast members ordered by :order ascending" do
    credits = %{
      "cast" => [
        %{"name" => "Actor B", "character" => "Char B", "id" => 2, "profile_path" => "/b.jpg", "order" => 1},
        %{"name" => "Actor A", "character" => "Char A", "id" => 1, "profile_path" => "/a.jpg", "order" => 0},
        %{"name" => "Actor C", "character" => "Char C", "id" => 3, "profile_path" => nil, "order" => 2}
      ]
    }

    assert Mapper.extract_cast(credits) == [
             %{"name" => "Actor A", "character" => "Char A", "tmdb_person_id" => 1, "profile_path" => "/a.jpg", "order" => 0},
             %{"name" => "Actor B", "character" => "Char B", "tmdb_person_id" => 2, "profile_path" => "/b.jpg", "order" => 1},
             %{"name" => "Actor C", "character" => "Char C", "tmdb_person_id" => 3, "profile_path" => nil, "order" => 2}
           ]
  end

  test "returns [] when credits is nil" do
    assert Mapper.extract_cast(nil) == []
  end

  test "returns [] when cast key is missing" do
    assert Mapper.extract_cast(%{"crew" => []}) == []
  end

  test "returns [] when cast is empty list" do
    assert Mapper.extract_cast(%{"cast" => []}) == []
  end
end
```

Also update the existing `"maps full TMDB movie response to domain attributes"` test in the `movie_attrs/3` describe block to add `cast` data and assert the extracted shape on the result. Append to the `data` map:

```elixir
"cast" => [
  %{"name" => "Sample Actor", "character" => "Sample Role", "id" => 99, "profile_path" => "/p.jpg", "order" => 0}
]
```

And after the existing assertions, add:

```elixir
assert result.cast == [
         %{"name" => "Sample Actor", "character" => "Sample Role", "tmdb_person_id" => 99, "profile_path" => "/p.jpg", "order" => 0}
       ]
```

- [ ] **Step 1.2: Run mapper test, verify it fails**

```bash
mix test test/media_centarr/tmdb/mapper_test.exs
```

Expected: failures referencing `Mapper.extract_cast/1` undefined and missing `:cast` key on `movie_attrs/3` result.

- [ ] **Step 1.3: Implement `extract_cast/1` and wire into `movie_attrs/3`**

In `lib/media_centarr/tmdb/mapper.ex`, after the `extract_director/1` block (around line 232), add:

```elixir
@doc """
Extracts the cast list from a TMDB credits payload. Returns a list of
maps sorted by `order` ascending — the TMDB importance ranking. String
keys (not atoms) so the value round-trips through SQLite/JSON without
atom conversion friction.
"""
def extract_cast(nil), do: []

def extract_cast(%{"cast" => cast}) when is_list(cast) do
  cast
  |> Enum.sort_by(& &1["order"])
  |> Enum.map(fn person ->
    %{
      "name" => person["name"],
      "character" => person["character"],
      "tmdb_person_id" => person["id"],
      "profile_path" => person["profile_path"],
      "order" => person["order"]
    }
  end)
end

def extract_cast(_), do: []
```

In `movie_attrs/3` (around line 11), add a `cast:` line alongside `director:`:

```elixir
director: extract_director(movie["credits"]),
cast: extract_cast(movie["credits"]),
```

(Do **not** add cast to `child_movie_attrs/5` — child movies inside a movie series are out of scope per the spec; revisit later.)

- [ ] **Step 1.4: Run mapper test, verify it passes**

```bash
mix test test/media_centarr/tmdb/mapper_test.exs
```

Expected: all tests pass, no warnings.

- [ ] **Step 1.5: Commit**

```bash
jj describe -m "feat(tmdb): extract cast list from movie credits"
jj new
```

---

## Task 2: Schema + Migration

**Files:**
- Create: `priv/repo/migrations/<timestamp>_add_cast_to_library_movies.exs`
- Modify: `lib/media_centarr/library/movie.ex`

- [ ] **Step 2.1: Generate the migration**

```bash
mix ecto.gen.migration add_cast_to_library_movies
```

The exact filename will be `priv/repo/migrations/<UTC-timestamp>_add_cast_to_library_movies.exs`. Use the timestamp Mix generated.

- [ ] **Step 2.2: Fill in the migration**

Replace the generated body with:

```elixir
defmodule MediaCentarr.Repo.Migrations.AddCastToLibraryMovies do
  use Ecto.Migration

  def change do
    alter table(:library_movies) do
      add :cast, :map
    end
  end
end
```

No DB-level default. Existing rows post-migration carry `nil`; the schema field default and changeset coerce `nil` to `[]`, so the component never has to defend against `nil`.

- [ ] **Step 2.3: Add `cast` field to `Movie` schema and changeset**

In `lib/media_centarr/library/movie.ex`:

a) Inside the `schema "library_movies"` block, after the `field :genres, {:array, :string}` line (~line 32), add:

```elixir
field :cast, {:array, :map}, default: []
```

b) In the `cast/1` arg list of `create_changeset/1` (~lines 49-70), add `:cast` to the list of permitted fields. The list should now end with:

```elixir
:movie_series_id,
:status,
:cast
```

c) After the existing `validate_required([:name])` line, append a coercion that rewrites `nil` → `[]` so callers feeding through this changeset (and the backfill action) never end up with `nil`:

```elixir
|> coerce_cast_default()
```

And add at the bottom of the module, before the final `end`:

```elixir
defp coerce_cast_default(changeset) do
  case get_field(changeset, :cast) do
    nil -> put_change(changeset, :cast, [])
    _   -> changeset
  end
end
```

- [ ] **Step 2.4: Run migration**

```bash
mix ecto.migrate
```

Expected: success, "library_movies" altered.

- [ ] **Step 2.5: Add round-trip test**

If `test/media_centarr/library/movie_test.exs` does not yet exist, create it with the round-trip; if it does, append a `describe "cast"` block. Skeleton (adjust `use` line to match neighbouring schema tests in the project — likely `MediaCentarr.DataCase`):

```elixir
defmodule MediaCentarr.Library.MovieTest do
  use MediaCentarr.DataCase, async: true

  alias MediaCentarr.Library.Movie
  alias MediaCentarr.Repo

  describe "cast field" do
    test "round-trips a list-of-maps through SQLite" do
      cast_data = [
        %{"name" => "Actor A", "character" => "Role A", "tmdb_person_id" => 1, "profile_path" => "/a.jpg", "order" => 0}
      ]

      assert {:ok, movie} =
               %{name: "Sample Movie", cast: cast_data}
               |> Movie.create_changeset()
               |> Repo.insert()

      assert reloaded = Repo.get!(Movie, movie.id)
      assert reloaded.cast == cast_data
    end

    test "defaults to [] when not provided" do
      assert {:ok, movie} =
               %{name: "Sample Movie B"}
               |> Movie.create_changeset()
               |> Repo.insert()

      assert Repo.get!(Movie, movie.id).cast == []
    end

    test "coerces nil cast to []" do
      assert {:ok, movie} =
               %{name: "Sample Movie C", cast: nil}
               |> Movie.create_changeset()
               |> Repo.insert()

      assert Repo.get!(Movie, movie.id).cast == []
    end
  end
end
```

If `Movie` requires `movie_series_id` for FK reasons in this project, mirror what existing movie tests do — check neighbouring tests under `test/media_centarr/library/` for the pattern before locking it in.

- [ ] **Step 2.6: Run schema test, verify pass**

```bash
mix test test/media_centarr/library/movie_test.exs
```

Expected: all three cases pass.

- [ ] **Step 2.7: Commit**

```bash
jj describe -m "feat(library): add cast column to movies"
jj new
```

---

## Task 3: CastStrip Component

**Files:**
- Create: `lib/media_centarr_web/components/detail/cast_strip.ex`
- Create: `test/media_centarr_web/components/detail/cast_strip_test.exs`

- [ ] **Step 3.1: Write failing component test**

Create `test/media_centarr_web/components/detail/cast_strip_test.exs`:

```elixir
defmodule MediaCentarrWeb.Components.Detail.CastStripTest do
  use MediaCentarrWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias MediaCentarrWeb.Components.Detail.CastStrip

  defp render_strip(cast) do
    assigns = %{cast: cast}
    rendered_to_string(~H"<CastStrip.cast_strip cast={@cast} />")
  end

  describe "cast_strip/1" do
    test "renders nothing when cast is empty" do
      assert render_strip([]) == ""
    end

    test "renders one card per cast member with name and character" do
      cast = [
        %{"name" => "Actor A", "character" => "Role A", "tmdb_person_id" => 1, "profile_path" => "/a.jpg", "order" => 0},
        %{"name" => "Actor B", "character" => "Role B", "tmdb_person_id" => 2, "profile_path" => "/b.jpg", "order" => 1}
      ]

      html = render_strip(cast)

      assert html =~ "Actor A"
      assert html =~ "Role A"
      assert html =~ "Actor B"
      assert html =~ "Role B"
    end

    test "links each card to the TMDB person page in a new tab" do
      cast = [
        %{"name" => "Actor A", "character" => "Role A", "tmdb_person_id" => 1234, "profile_path" => "/a.jpg", "order" => 0}
      ]

      html = render_strip(cast)

      assert html =~ ~s{href="https://www.themoviedb.org/person/1234"}
      assert html =~ ~s{target="_blank"}
      assert html =~ ~s{rel="noopener}
    end

    test "uses TMDB w185 image URL for the photo" do
      cast = [
        %{"name" => "Actor A", "character" => "Role A", "tmdb_person_id" => 1, "profile_path" => "/abc.jpg", "order" => 0}
      ]

      assert render_strip(cast) =~ "https://image.tmdb.org/t/p/w185/abc.jpg"
    end

    test "renders silhouette fallback when profile_path is nil" do
      cast = [
        %{"name" => "Actor A", "character" => "Role A", "tmdb_person_id" => 1, "profile_path" => nil, "order" => 0}
      ]

      html = render_strip(cast)

      refute html =~ "image.tmdb.org"
      assert html =~ "hero-user"
    end

    test "renders cards with no tmdb_person_id as non-interactive" do
      cast = [
        %{"name" => "Actor A", "character" => "Role A", "tmdb_person_id" => nil, "profile_path" => "/a.jpg", "order" => 0}
      ]

      html = render_strip(cast)

      refute html =~ "themoviedb.org/person"
      assert html =~ "Actor A"
    end
  end
end
```

The exact `~H` import path may need adjustment — check `MediaCentarrWeb.ConnCase` for what's already imported. If `~H` requires a `use MediaCentarrWeb, :html` shim, copy whatever the existing `detail_panel_test.exs` does for rendering components.

- [ ] **Step 3.2: Run component test, verify it fails**

```bash
mix test test/media_centarr_web/components/detail/cast_strip_test.exs
```

Expected: module `MediaCentarrWeb.Components.Detail.CastStrip` not found.

- [ ] **Step 3.3: Implement CastStrip component**

Create `lib/media_centarr_web/components/detail/cast_strip.ex`:

```elixir
defmodule MediaCentarrWeb.Components.Detail.CastStrip do
  @moduledoc """
  Horizontal scrollable strip of cast cards rendered at the bottom of
  the movie detail modal. Each card shows a TMDB profile photo, actor
  name, and character name; clicking opens the TMDB person page in a
  new tab.

  Photos are hotlinked from `image.tmdb.org/t/p/w185{path}` — same
  pattern the review UI uses for unimported posters. Cast members
  without a `profile_path` get a silhouette icon. Cards without a
  `tmdb_person_id` (defensive) render as non-interactive.
  """

  use MediaCentarrWeb, :html

  @cast_doc "list of maps as stored on `MediaCentarr.Library.Movie.cast` — string keys: `name`, `character`, `tmdb_person_id`, `profile_path`, `order`."

  attr :cast, :list, required: true, doc: @cast_doc

  def cast_strip(assigns) do
    ~H"""
    <section :if={@cast != []} class="pt-4 pb-2">
      <h3 class="text-xs font-semibold uppercase tracking-wider text-base-content/60 mb-3">
        Cast
      </h3>
      <div class="flex gap-3 overflow-x-auto pb-2 -mx-1 px-1 scroll-smooth">
        <.card :for={person <- @cast} person={person} />
      </div>
    </section>
    """
  end

  attr :person, :map, required: true

  defp card(%{person: %{"tmdb_person_id" => id}} = assigns) when is_integer(id) do
    ~H"""
    <a
      href={"https://www.themoviedb.org/person/#{@person["tmdb_person_id"]}"}
      target="_blank"
      rel="noopener noreferrer"
      class="shrink-0 w-[110px] group focus:outline-none focus:ring-2 focus:ring-primary rounded-md"
    >
      <.photo person={@person} />
      <p class="mt-1.5 text-xs font-semibold leading-tight text-base-content line-clamp-2 group-hover:text-primary transition-colors">
        {@person["name"]}
      </p>
      <p :if={@person["character"]} class="mt-0.5 text-[11px] leading-tight text-base-content/60 line-clamp-2">
        {@person["character"]}
      </p>
    </a>
    """
  end

  defp card(assigns) do
    ~H"""
    <div class="shrink-0 w-[110px]">
      <.photo person={@person} />
      <p class="mt-1.5 text-xs font-semibold leading-tight text-base-content line-clamp-2">
        {@person["name"]}
      </p>
      <p :if={@person["character"]} class="mt-0.5 text-[11px] leading-tight text-base-content/60 line-clamp-2">
        {@person["character"]}
      </p>
    </div>
    """
  end

  attr :person, :map, required: true

  defp photo(%{person: %{"profile_path" => path}} = assigns) when is_binary(path) do
    ~H"""
    <img
      src={"https://image.tmdb.org/t/p/w185#{@person["profile_path"]}"}
      alt={@person["name"]}
      loading="lazy"
      class="w-[110px] h-[140px] rounded-md object-cover bg-base-300"
    />
    """
  end

  defp photo(assigns) do
    ~H"""
    <div class="w-[110px] h-[140px] rounded-md bg-base-300/60 flex items-center justify-center">
      <.icon name="hero-user" class="size-10 text-base-content/30" />
    </div>
    """
  end
end
```

- [ ] **Step 3.4: Run component test, verify all cases pass**

```bash
mix test test/media_centarr_web/components/detail/cast_strip_test.exs
```

Expected: 6 tests pass.

- [ ] **Step 3.5: Commit**

```bash
jj describe -m "feat(detail): cast strip component"
jj new
```

---

## Task 4: DetailPanel integration

**Files:**
- Modify: `lib/media_centarr_web/components/detail_panel.ex`
- Modify: `test/media_centarr_web/components/detail_panel_test.exs`

- [ ] **Step 4.1: Write failing integration test**

Append to `test/media_centarr_web/components/detail_panel_test.exs` (consult existing patterns — likely there's a `render_panel_for/1` helper or similar). Skeleton:

```elixir
describe "cast strip" do
  test "renders cast strip for a movie with non-empty cast" do
    movie = build(:movie,
      type: :movie,
      cast: [
        %{"name" => "Sample Actor", "character" => "Sample Role", "tmdb_person_id" => 7, "profile_path" => "/x.jpg", "order" => 0}
      ]
    )

    html = render_panel(entity: movie)

    assert html =~ "Sample Actor"
    assert html =~ "Sample Role"
  end

  test "does not render the strip when cast is empty" do
    movie = build(:movie, type: :movie, cast: [])
    html = render_panel(entity: movie)
    refute html =~ ">Cast<"
  end

  test "does not render the strip for a tv_series" do
    tv = build(:tv_series, type: :tv_series)
    html = render_panel(entity: tv)
    refute html =~ ">Cast<"
  end
end
```

Use the existing `render_panel` helper / factory style from the rest of the file (read its top before adapting). If the `:movie` factory doesn't yet accept `:cast`, extend it minimally inside `test/support/factory.ex` (default `cast: []`).

- [ ] **Step 4.2: Run integration test, verify it fails**

```bash
mix test test/media_centarr_web/components/detail_panel_test.exs
```

Expected: assertions for "Sample Actor" / "Sample Role" fail (strip not rendered).

- [ ] **Step 4.3: Wire CastStrip into DetailPanel**

In `lib/media_centarr_web/components/detail_panel.ex`:

a) Add the alias near the top (alphabetised within the `MediaCentarrWeb.Components.Detail.*` block, ~lines 19-23):

```elixir
alias MediaCentarrWeb.Components.Detail.CastStrip
```

b) Inside the `~H` template of `detail_panel/1`, locate the closing `</div>` of `id="detail-header"` (around line 187). Immediately **before** that closing tag (so the strip lives inside the header section, below the description/facets row), insert:

```elixir
<CastStrip.cast_strip :if={@entity.type == :movie} cast={Map.get(@entity, :cast) || []} />
```

The `Map.get(@entity, :cast) || []` defends against entities loaded via paths that don't carry the field — strictly defensive; the schema default ensures it'll always be a list in practice.

- [ ] **Step 4.4: Run integration test, verify pass**

```bash
mix test test/media_centarr_web/components/detail_panel_test.exs
```

Expected: all three new tests pass; existing tests still pass.

- [ ] **Step 4.5: Manual smoke check**

In an iex session attached to the dev server (recompile if running):

```elixir
recompile()
```

Then in a browser, open a movie detail modal that has cast (any newly-imported one once Task 1's mapper change is in effect — for now, use a movie inserted manually via iex with cast data). Verify the strip appears, scrolls horizontally, links open TMDB in a new tab, and silhouette renders for entries without a profile_path.

If no movie with cast exists yet, this verification can be deferred to after Task 6 runs the backfill — note that and move on.

- [ ] **Step 4.6: Commit**

```bash
jj describe -m "feat(detail-panel): mount cast strip on movie detail"
jj new
```

---

## Task 5: Storybook story

**Files:**
- Create: `storybook/detail/cast_strip.story.exs`
- Modify (if applicable): `storybook/detail/_detail.index.exs`

- [ ] **Step 5.1: Write the story**

Read `storybook/detail/facet_strip.story.exs` first for the canonical structure, then create `storybook/detail/cast_strip.story.exs`:

```elixir
defmodule MediaCentarrWeb.Storybook.Detail.CastStrip do
  @moduledoc """
  Horizontal cast strip rendered at the bottom of the movie detail
  modal. Each card is a TMDB profile photo + actor name + character
  name; click opens TMDB's person page in a new tab.

  ## Variations

    * `:default` — eight cast members with photos. The most common
      shape — exercises horizontal overflow scrolling.
    * `:mixed` — three with photos, two without (silhouette
      fallback). Pins the no-photo branch.
    * `:empty` — empty cast list; the component renders nothing.
  """

  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentarrWeb.Components.Detail.CastStrip.cast_strip/1
  def render_source, do: :function
  def layout, do: :one_column

  def template do
    """
    <div class="w-full max-w-3xl">
      <.psb-variation/>
    </div>
    """
  end

  def variations do
    [
      %Variation{
        id: :default,
        description: "Eight cast members with profile photos.",
        attributes: %{
          cast: sample_cast_with_photos()
        }
      },
      %Variation{
        id: :mixed,
        description: "Some cast members lack profile photos — silhouette fallback.",
        attributes: %{
          cast: sample_cast_mixed()
        }
      },
      %Variation{
        id: :empty,
        description: "Empty cast — component renders nothing.",
        attributes: %{cast: []}
      }
    ]
  end

  defp sample_cast_with_photos do
    for n <- 0..7 do
      %{
        "name" => "Sample Actor #{n + 1}",
        "character" => "Sample Role #{n + 1}",
        "tmdb_person_id" => 1000 + n,
        "profile_path" => "/example#{n}.jpg",
        "order" => n
      }
    end
  end

  defp sample_cast_mixed do
    [
      %{"name" => "Sample Actor One", "character" => "Sample Role One", "tmdb_person_id" => 2001, "profile_path" => "/a.jpg", "order" => 0},
      %{"name" => "Sample Actor Two", "character" => "Sample Role Two", "tmdb_person_id" => 2002, "profile_path" => nil, "order" => 1},
      %{"name" => "Sample Actor Three", "character" => "Sample Role Three", "tmdb_person_id" => 2003, "profile_path" => "/c.jpg", "order" => 2},
      %{"name" => "Sample Actor Four", "character" => "Sample Role Four", "tmdb_person_id" => 2004, "profile_path" => nil, "order" => 3},
      %{"name" => "Sample Actor Five", "character" => "Sample Role Five", "tmdb_person_id" => 2005, "profile_path" => "/e.jpg", "order" => 4}
    ]
  end
end
```

The hotlinked photos won't actually load in storybook (the placeholder paths don't exist on TMDB CDN). That's accurate — storybook is a structural catalog, and `<img>` tags with broken `src` show the browser's broken-image icon. If the project's existing stories use a known-valid PD/CC poster path (check `defaults/media-centarr-showcase.toml` or `lib/media_centarr/showcase.ex` for one) and you'd rather show real photos, switch to that — but only if the CC license allows it.

- [ ] **Step 5.2: Register the story (if the index requires explicit listing)**

Read `storybook/detail/_detail.index.exs`. If it explicitly enumerates entries, add the new story; if it auto-discovers, no change.

- [ ] **Step 5.3: Manually verify in browser**

```bash
mix phx.server
```

Open `http://localhost:1080/storybook/detail/cast_strip`. Confirm all three variations render. The default variation should show a horizontally scrollable row of eight cards with broken-image icons (or real photos if you swapped them in step 5.1).

- [ ] **Step 5.4: Commit**

```bash
jj describe -m "feat(storybook): cast strip variations"
jj new
```

---

## Task 6: Backfill maintenance action

**Files:**
- Modify: `lib/media_centarr/maintenance.ex`
- Modify: `lib/media_centarr_web/live/settings_live.ex`
- Create: `test/media_centarr/maintenance_test.exs` (or extend if it already exists)

- [ ] **Step 6.1: Write failing test for `Maintenance.refresh_movie_cast/0`**

Skeleton (adapt to the existing test conventions — read other maintenance tests if present, and `test/support/tmdb_stubs.ex` for the stub pattern). The stub must short-circuit `MediaCentarr.TMDB.Client.get_movie/1` so no real network calls happen.

```elixir
describe "refresh_movie_cast/0" do
  test "populates cast on movies with empty cast and a tmdb_id" do
    {:ok, movie} =
      %{name: "Sample Movie", tmdb_id: "123", cast: []}
      |> Movie.create_changeset()
      |> Repo.insert()

    stub_tmdb_get_movie("123", %{
      "credits" => %{
        "cast" => [
          %{"name" => "Sample Actor", "character" => "Sample Role", "id" => 7, "profile_path" => "/p.jpg", "order" => 0}
        ]
      }
    })

    assert {:ok, %{updated: 1, skipped: 0, failed: 0}} = Maintenance.refresh_movie_cast()

    reloaded = Repo.get!(Movie, movie.id)
    assert [%{"name" => "Sample Actor"} | _] = reloaded.cast
  end

  test "skips movies that already have non-empty cast" do
    {:ok, _} =
      %{
        name: "Sample Movie",
        tmdb_id: "456",
        cast: [%{"name" => "Existing", "character" => "Existing", "tmdb_person_id" => 1, "profile_path" => nil, "order" => 0}]
      }
      |> Movie.create_changeset()
      |> Repo.insert()

    assert {:ok, %{updated: 0, skipped: 1, failed: 0}} = Maintenance.refresh_movie_cast()
  end

  test "skips movies without a tmdb_id" do
    {:ok, _} =
      %{name: "Sample Movie", tmdb_id: nil, cast: []}
      |> Movie.create_changeset()
      |> Repo.insert()

    assert {:ok, %{updated: 0, skipped: 1, failed: 0}} = Maintenance.refresh_movie_cast()
  end
end
```

(Use `MediaCentarr.DataCase`. `stub_tmdb_get_movie/2` is illustrative — the real helper name lives in `test/support/tmdb_stubs.ex`; read it before locking in the call.)

- [ ] **Step 6.2: Run, verify it fails**

```bash
mix test test/media_centarr/maintenance_test.exs
```

Expected: `Maintenance.refresh_movie_cast/0` undefined.

- [ ] **Step 6.3: Implement `refresh_movie_cast/0`**

In `lib/media_centarr/maintenance.ex`, add the `Mapper` and `Client` aliases at the top:

```elixir
alias MediaCentarr.TMDB.{Client, Mapper}
```

(Verify boundary deps allow this — `use Boundary, deps: [...]` may need `MediaCentarr.TMDB` added if not already permitted.)

Then add the function:

```elixir
@doc """
Backfills the `cast` field on movies that were imported before the
field existed. Iterates movies with empty `cast` and a non-nil
`tmdb_id`, re-fetches TMDB metadata, and updates `cast` in place via
a focused changeset — no images, watch progress, or files are
touched.

Idempotent: subsequent runs skip movies that already have non-empty
cast. Rate-limited automatically by `MediaCentarr.TMDB.RateLimiter`
inside `Client.get_movie/1`.

Returns `{:ok, %{updated: n, skipped: n, failed: n}}`.
"""
@spec refresh_movie_cast() :: {:ok, %{updated: non_neg_integer(), skipped: non_neg_integer(), failed: non_neg_integer()}}
def refresh_movie_cast do
  import Ecto.Query
  Log.info(:library, "refreshing movie cast")

  movies = Repo.all(from m in Movie, where: not is_nil(m.tmdb_id))

  result =
    Enum.reduce(movies, %{updated: 0, skipped: 0, failed: 0}, fn movie, acc ->
      cond do
        movie.cast not in [nil, []] ->
          Map.update!(acc, :skipped, &(&1 + 1))

        is_nil(movie.tmdb_id) ->
          Map.update!(acc, :skipped, &(&1 + 1))

        true ->
          case Client.get_movie(movie.tmdb_id) do
            {:ok, body} ->
              cast = Mapper.extract_cast(body["credits"])

              movie
              |> Ecto.Changeset.change(cast: cast)
              |> Repo.update()
              |> case do
                {:ok, _} -> Map.update!(acc, :updated, &(&1 + 1))
                {:error, _} -> Map.update!(acc, :failed, &(&1 + 1))
              end

            {:error, reason} ->
              Log.warning(:library, "cast refresh failed for movie #{movie.id}: #{inspect(reason)}")
              Map.update!(acc, :failed, &(&1 + 1))
          end
      end
    end)

  Log.info(:library, "movie cast refresh — #{result.updated} updated, #{result.skipped} skipped, #{result.failed} failed")
  {:ok, result}
end
```

The query intentionally pulls all movies with a tmdb_id (even ones with non-empty cast) so the skip-counter is meaningful in the UI. If movie counts ever climb high enough that this is wasteful, switch the WHERE to `is_nil(m.cast) or m.cast == ^[]`.

- [ ] **Step 6.4: Run, verify pass**

```bash
mix test test/media_centarr/maintenance_test.exs
```

Expected: all three cases pass.

- [ ] **Step 6.5: Wire button into Settings page**

In `lib/media_centarr_web/live/settings_live.ex`:

a) Find the existing `mount/3` (or relevant assigns initialization) and ensure there's a `:refreshing_cast` flag (default `false`) — mirror how `@refreshing_images` and `@repairing_images` are initialised.

b) Find the maintenance section block where `refresh_image_cache` and `repair_missing_images` buttons live (around lines 2500-2570). Add a sibling row, immediately above the Refresh-image-cache row:

```elixir
<div class="flex items-start justify-between gap-4 py-3">
  <div class="min-w-0">
    <p class="text-sm font-medium">Refresh movie cast</p>
    <p class="text-xs text-base-content/50 mt-0.5">
      Backfills cast for movies imported before the cast strip existed. Skips movies that already have cast — safe to re-run.
    </p>
  </div>
  <.button
    variant="neutral"
    size="sm"
    class="shrink-0"
    phx-click="refresh_movie_cast"
    disabled={@refreshing_cast}
    data-nav-item
    tabindex="0"
  >
    {if @refreshing_cast, do: "Refreshing…", else: "Refresh"}
  </.button>
</div>
```

c) Add a handler near the existing `refresh_image_cache` handler (~line 476):

```elixir
def handle_event("refresh_movie_cast", _params, socket) do
  socket = assign(socket, :refreshing_cast, true)

  Task.start(fn ->
    {:ok, _result} = Maintenance.refresh_movie_cast()
    send(self(), :cast_refresh_done)
  end)

  {:noreply, socket}
end

def handle_info(:cast_refresh_done, socket) do
  {:noreply, assign(socket, :refreshing_cast, false)}
end
```

Compare with the existing `refresh_image_cache` handler — if it uses a different pattern (e.g. a flash or a result count), align with it for consistency.

- [ ] **Step 6.6: Compile and click the button**

```bash
mix compile
```

Then with the dev server running, open Settings → Library Maintenance, click "Refresh". Verify:
- Button text changes to "Refreshing…"
- Logs show movie count and skip/update counts
- A previously-imported movie's detail modal now shows the cast strip

- [ ] **Step 6.7: Commit**

```bash
jj describe -m "feat(maintenance): backfill movie cast"
jj new
```

---

## Task 7: Wiki + Precommit + Ship

- [ ] **Step 7.1: Update wiki — Settings reference**

In `~/src/media-centarr/media-centarr.wiki/`, edit `Settings-Reference.md` (or whatever page documents Library Maintenance buttons — grep for "Refresh image cache"). Add an entry for "Refresh movie cast" mirroring the style of neighbouring entries: what it does, when to use, idempotency note.

- [ ] **Step 7.2: Commit wiki**

```bash
cd ~/src/media-centarr/media-centarr.wiki
jj describe -m "wiki: document refresh-movie-cast maintenance action"
jj bookmark set master -r @
jj git push
cd -
```

- [ ] **Step 7.3: Run precommit, fix anything it reports**

```bash
mix precommit
```

Zero warnings policy. Address every warning, every Credo issue, every Sobelow finding. Do not skip.

If `mix boundaries` complains about `Maintenance` reaching `MediaCentarr.TMDB`, update the `use Boundary, deps:` line in `lib/media_centarr/maintenance.ex` to add `MediaCentarr.TMDB`.

- [ ] **Step 7.4: Final commit if precommit caused fixes**

```bash
jj describe -m "chore: precommit fixes for cast strip feature"
jj new
```

(If `mix precommit` produced no changes, skip this step.)

- [ ] **Step 7.5: Hand off to user**

The feature is now complete. Surface to the user:

- Summary of files changed.
- Whether `/ship` is appropriate (per the user's standing instruction to ship without asking after green precommit).
- Any deferred items: child movies inside `MovieSeries` do not yet show cast; TV cast is out of scope per spec.

---

## Self-Review Notes (filled in during plan-writing)

- **Spec coverage:** All seven sections of the spec map to tasks — Mapper (T1), schema/migration (T2), component (T3), DetailPanel integration (T4), Storybook (T5), backfill (T6), wiki/ship (T7).
- **Placeholder scan:** No "TBD" / "implement later" / "similar to". Each step contains the actual code to write.
- **Type consistency:**
  - Cast map keys are string-keyed throughout: `"name"`, `"character"`, `"tmdb_person_id"`, `"profile_path"`, `"order"`.
  - Schema field is `field :cast, {:array, :map}, default: []`.
  - Component receives the same shape; mapper produces it; tests assert it.
  - Maintenance return type `%{updated: n, skipped: n, failed: n}` matches across implementation and tests.
- **Known fuzzy areas the executor must check first** (called out inline in steps):
  - Exact `~H` import for component test (Step 3.1)
  - Existing `render_panel_for/1` helper convention (Step 4.1)
  - Storybook auto-discovery vs explicit index (Step 5.2)
  - `tmdb_stubs.ex` helper signature (Step 6.1)
  - Boundary deps update for Maintenance → TMDB (Step 7.3)
