---
description: Add a new parser rule — test-first, then fix
argument-hint: <entity name as it appears in the database>
allowed-tools: Read, Edit, Glob, Grep, Bash(mix test:*), Bash(mix precommit:*), mcp__tidewave__project_eval, mcp__tidewave__execute_sql_query
---

You are adding a new filename pattern to the media file parser. Follow the test-first workflow from `CLAUDE.md` § Parser exactly.

The user says: $ARGUMENTS

## Step 1: Look up the entity and its files

1. Use `mcp__tidewave__project_eval` to query the database via Ash. Find the Entity whose name matches the user's input (case-insensitive partial match is fine — use `Ash.read!` with a filter):

   ```elixir
   require Ash.Query
   MediaManager.Library.WatchedFile
   |> Ash.Query.filter(contains(entity.name, "<user input>"))
   |> Ash.Query.load(:entity)
   |> Ash.read!()
   ```

2. Show the user a summary of what was found:
   - Entity name, type, year (`date_published`), and any other relevant entity fields
   - Every `WatchedFile` associated with this entity — show `file_path`, `parsed_title`, `parsed_year`, `parsed_type`, `season_number`, `episode_number`, and `state`

3. Read `lib/media_manager/parser.ex` and `test/media_manager/parser_test.exs` for context.

4. For each watched file, evaluate `MediaManager.Parser.parse(file_path)` to show what the parser currently produces.

5. Present the results clearly so the user can compare entity data vs. parse results and identify which files are misparsed.

## Step 2: Wait for user instructions

Ask the user: which file(s) are misparsed, and what should the correct parse result be? Do **not** proceed until the user tells you the expected values.

## Step 3: Write the failing test(s)

1. Determine the correct `describe` block for each test — use an existing block if the pattern fits, or create a new one with a descriptive `describe` name following existing conventions.
2. Write a test with:
   - A descriptive test name explaining what makes this pattern unique
   - The exact real file path from the database
   - Assertions for all expected fields (title, year, type, season, episode) based on the user's instructions
3. Run `mix test test/media_manager/parser_test.exs` — confirm the new test(s) **fail** and all existing tests still pass.
4. Show the user the failure output.

## Step 4: Fix the parser

1. Analyze *why* the parser misclassifies this path — trace through `candidate_name/1` and the pattern matching chain.
2. Make the **minimum change** needed to fix this pattern without breaking existing tests.
3. Prefer adding to existing helper functions over creating new ones.
4. If a new helper is needed, follow existing naming conventions and place it near related helpers.

## Step 5: Verify

1. Run `mix test test/media_manager/parser_test.exs` — all tests must pass.
2. Run `mix precommit` — no warnings, no failures.
3. For each fixed file, evaluate `MediaManager.Parser.parse(file_path)` again and show the user the corrected result.
