# Parser System Redesign — Implementation Plan

## Context

The parser (`lib/media_manager/parser.ex`) is a ~588-line pure function module that transforms file paths into `%Parser.Result{}` structs. It works — 40+ real-world filename patterns pass — but its internal structure is hard to reason about because **four concerns are interleaved**: pre-processing (candidate name selection), classification (regex cascade), field extraction (type-specific post-processing), and title cleaning. Touching one concern requires understanding all four.

The goal is to find a design that "masters" this subdomain — making the parser understandable, maintainable, and pleasant to work with.

---

## Chosen Approach: Phase Separation (Option 1)

Restructure the existing logic into four explicit, independently testable phases. Same algorithms, clearer boundaries.

### The Phases

```
Path
  |
  v
1. Context      -- extract directory context once, pick candidate text
                   Output: %Context{text, season_dir?, season_num, show_from_dir, extras?, ...}

2. Classify     -- try patterns in priority order against context.candidate
                   Output: {type, raw_captures} | :unknown

3. Extract      -- convert captures to fields, merge directory context
                   (year from TV title, show name fallback, compact episode splitting)
                   Output: raw field map %{title: "raw", season: 5, episode: 1, ...}

4. Clean        -- uniform cleaning pipeline on all string fields, once, at the end
                   (strip quality, release group, title_case)
                   Output: %Parser.Result{}
```

### What changes

| Concern | Current | After |
|---------|---------|-------|
| Directory walking | Done in `candidate_name/1`, `extras_file?/2`, `parse_compact_episode/1`, `extract_tv_title/2` (4 places) | Done once in Phase 1, stored in `%Context{}` |
| Classification | `cond` chain with inline `Regex.run` calls | Explicit ordered list of pattern matches iterated in `Classifier` |
| Field extraction | Mixed into `parse_tv/3`, `parse_movie/3`, etc. | Separate `Extractor` module with clauses per type |
| Cleaning | `clean_title/1` called at different points; `extract_episode_title/1` has its own cleaning | Single `Cleaner` module applied once at the end |

### What stays the same

- All regex patterns unchanged
- All test cases unchanged (same inputs, same outputs)
- Same `Result` struct
- Still a pure function module, no GenServer or config

---

## Phase 1: Extract `Parser.Context`

**New module:** `lib/media_manager/parser/context.ex`

**What it captures:**

```elixir
%Context{
  file_path: String.t(),
  base: String.t(),                 # filename without media extension
  candidate: String.t(),            # best text to classify (current candidate_name logic)
  parent: String.t() | nil,         # immediate parent dir name
  grandparent: String.t() | nil,    # grandparent dir name
  season_dir?: boolean(),           # parent is "Season N" or "S01"
  season_from_dir: integer() | nil, # season number from parent dir
  extras_ancestor: integer() | nil, # index of extras dir in path, or nil
  generic_base?: boolean(),         # filename is generic/short lowercase
  bare_episode?: boolean()          # filename is bare "S01E03"
}
```

**What moves here:**
- `candidate_name/1` logic
- `season_directory?/1`, `bare_episode?/1`, `generic_base?/1`
- `base_without_media_extension/1`
- `extras_file?/2`, `find_extras_ancestor/2`
- `extract_season_number/1`
- `strip_url_prefix/1` (applied to candidate)

**Key benefit:** Every downstream phase receives a single `%Context{}` instead of re-walking `Path.split/1`. The context is computed once.

**Tests:** New unit tests for `Context.new/2` — given a path, assert the context fields. These are additive tests; all existing parser tests remain untouched.

---

## Phase 2: Extract `Parser.Classifier`

**New module:** `lib/media_manager/parser/classifier.ex`

**Purpose:** Given a `%Context{}`, return `{type, captures}` or `:unknown`.

**What moves here:**
- The `cond` chain from `parse/2` that tries patterns in order
- All regex module attributes (`@tv_pattern`, `@tv_nxnn_pattern`, `@tv_spelled_pattern`, `@season_pack_pattern`, `@year_pattern`, `@compact_episode_pattern`)
- The compact-episode detection logic (currently `parse_compact_episode/1` does both detection AND extraction — split it)

**Structure:**

```elixir
def classify(%Context{} = ctx) do
  cond do
    ctx.extras_ancestor != nil -> {:extra, nil}
    compact = match_compact(ctx) -> {:tv_compact, compact}
    match = try_tv_patterns(ctx.candidate) -> {:tv, match}
    match = try_season_pack(ctx.candidate) -> {:season_pack, match}
    match = try_movie_year(ctx.candidate) -> {:movie, match}
    true -> {:unknown, nil}
  end
end
```

**Tests:** Given a `%Context{}`, assert that classification returns the right type+captures. E.g., "candidate `Sample.Show.Two.S02E01.Sample.Episode.Two.2160p...` classifies as `{:tv, [...]}`".

---

## Phase 3: Extract `Parser.Extractor`

**New module:** `lib/media_manager/parser/extractor.ex`

**Purpose:** Given `{type, captures}` + `%Context{}`, produce a raw field map.

**What moves here:**
- `parse_tv/3` → `extract_tv/2`
- `parse_movie/3` → `extract_movie/2`
- `parse_extra/2` → `extract_extra/2`
- `parse_season_pack/2` → `extract_season_pack/2`
- `parse_compact_episode` extraction half → `extract_compact/2`
- `parse_unknown/2` → `extract_unknown/2`
- `extract_tv_title/2`, `extract_year_from_tv_title/1`, `extract_episode_title/1`
- `parse_extra_parent/2`, `parse_parent_movie/1`, etc.

**Output:** A plain map like `%{title: "raw title", year: 2024, season: 1, episode: 3, episode_title: "raw ep title", type: :tv}` — **uncleaned strings**.

**Key change:** Extraction no longer calls `clean_title/1` or `title_case/1`. It returns raw strings. Cleaning happens in the next phase.

**Tests:** Given a classification result + context, assert the raw extracted fields.

---

## Phase 4: Extract `Parser.Cleaner`

**New module:** `lib/media_manager/parser/cleaner.ex`

**Purpose:** Single pass over all string fields in the raw map, producing the final `%Result{}`.

**What moves here:**
- `clean_title/1`
- `title_case/1`, `capitalize_word/1`
- `@quality_pattern`, `@quality_bracket_pattern`, `@release_group_pattern` (used by cleaning)
- The parallel cleaning in `extract_episode_title/1` (currently duplicates `clean_title` logic)

**Structure:**

```elixir
def clean(raw_fields) do
  %Result{
    file_path: raw_fields.file_path,
    title: clean_string(raw_fields.title),
    year: raw_fields.year,
    type: raw_fields.type,
    season: raw_fields.season,
    episode: raw_fields.episode,
    episode_title: clean_string(raw_fields.episode_title),
    parent_title: clean_string(raw_fields.parent_title),
    parent_year: raw_fields.parent_year
  }
end
```

**Key benefit:** `clean_title` and `extract_episode_title` currently have separate but overlapping cleaning pipelines. Unifying them into one `clean_string/1` eliminates the duplication.

**Tests:** Given raw strings with dots, quality tokens, release groups — assert cleaned output.

---

## Phase 5: Wire it together

`Parser.parse/2` becomes:

```elixir
def parse(file_path, opts \\ []) do
  file_path
  |> Context.new(opts)
  |> Classifier.classify()
  |> then(fn {type, captures, ctx} -> Extractor.extract(type, captures, ctx) end)
  |> Cleaner.clean()
end
```

All 40+ existing tests pass unchanged — same inputs, same outputs.

---

## File layout

```
lib/media_manager/parser.ex              # public API, Result struct, 4-step pipe
lib/media_manager/parser/context.ex      # directory analysis, candidate selection
lib/media_manager/parser/classifier.ex   # regex patterns, type classification
lib/media_manager/parser/extractor.ex    # type-specific field extraction
lib/media_manager/parser/cleaner.ex      # title cleaning, title_case

test/media_manager/parser_test.exs       # existing tests, unchanged
test/media_manager/parser/context_test.exs
test/media_manager/parser/classifier_test.exs
test/media_manager/parser/extractor_test.exs
test/media_manager/parser/cleaner_test.exs
```

---

## Execution order

1. Write `Context` + its tests (no changes to existing code)
2. Write `Classifier` + its tests (no changes to existing code)
3. Write `Extractor` + its tests (no changes to existing code)
4. Write `Cleaner` + its tests (no changes to existing code)
5. Rewire `Parser.parse/2` to use the four phases — existing tests validate
6. Delete dead private functions from `parser.ex`
7. Run `mix precommit`, fix any warnings

Steps 1–4 are purely additive. Step 5 is the switchover. Step 6 is cleanup. At no point do existing tests break or get modified.

---

## What this does NOT change

- All regex patterns stay identical
- `%Parser.Result{}` struct unchanged
- Public API `Parser.parse/2` unchanged
- All 40+ test cases pass with zero modifications
- Still pure functions, no GenServer or config

---

## Future: Option 2 bridge

If after Phase Separation we want to evolve toward tokenization, the `Classifier` module is the natural insertion point — replace the regex cascade with a tokenizer without touching `Context`, `Extractor`, or `Cleaner`. The phase boundaries make this incremental rather than a rewrite.

---

## Option 2 reference: Tokenizer / Rule Engine

Preserved here for future reference. Fundamentally different approach inspired by Guessit (Python).

### Architecture

```
Path → Segment → Tokenize → Identify → Resolve → Assemble → %Result{}
```

1. **Segment** — split path into segments with provenance (`{:parent_dir, "Sample Show One"}`, `{:filename, "501 My Title"}`)
2. **Tokenize** — classify each word/token independently (`:word`, `:digits`, `:separator`)
3. **Identify** — tag known tokens (quality, codec, source, streaming service, release group) via dictionary lookup
4. **Resolve** — disambiguation rules via Elixir pattern matching function clauses
5. **Assemble** — collect resolved tokens into `%Parser.Result{}`

### Key insight: "title = the gap"

After all known tokens (quality, codec, year, season/episode, release group) are identified, the title is whatever words are left in the gap before the first technical token.

### Pros

- Each token type independently testable
- Adding vocabulary is trivial (one map entry, no regex editing)
- Directory context is structured, not a candidate-name-prepending hack
- Leverages Elixir's strengths (binary pattern matching, function clauses, pipes)

### Cons

- Significantly more code (~700-900 lines across 5-6 modules)
- Higher risk — fundamentally different approach
- Separator ambiguity (`.` is word separator in `Movie.Name.2024` but part of `H.264`)
- May be over-engineered for current scale (~50 patterns vs Guessit's thousands)
- ~1-2 week effort

### Comparison

| Dimension | Option 1: Phase Separation | Option 2: Tokenizer |
|-----------|---------------------------|---------------------|
| Risk | Low | Medium-high |
| Effort | ~2-3 days | ~1-2 weeks |
| Code size | ~600 lines, better organized | ~700-900 lines, 5-6 modules |
| Testability | Better (4 testable phases) | Best (every token independently) |
| Extensibility | Modest improvement | Significant |
| Regression risk | Minimal | Moderate |
