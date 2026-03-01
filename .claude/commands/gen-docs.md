---
description: Generate public-facing release documentation for the backend
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Task
---

# Generate Release Documentation

Generate comprehensive public-facing documentation for `backend/`. This produces a professional README and detailed subsystem docs with mermaid diagrams, suitable for shipping with a release.

## Output Structure

```
backend/
├── README.md                      # Project overview + doc TOC
├── docs/
│   ├── .instructions/             # Human-editable supplements (never overwritten)
│   │   ├── global.md              # Style/tone/audience defaults
│   │   └── <doc-name>.md          # Per-doc additional context (optional)
│   ├── getting-started.md         # Installation, dependencies, quick start
│   ├── configuration.md           # All config options, embedded defaults, setup
│   ├── architecture.md            # System overview, mermaid component diagrams
│   ├── watcher.md                 # File detection subsystem
│   ├── pipeline.md                # Broadway processing pipeline
│   ├── tmdb.md                    # TMDB integration
│   ├── playback.md                # MPV playback engine
│   ├── channel.md                 # Phoenix Channels WebSocket API
│   └── library.md                 # Ash domain, entities, resources
```

## Step 1: Bootstrap Instruction Files

Create `backend/docs/.instructions/` if it doesn't exist.

If `backend/docs/.instructions/global.md` does NOT exist, create it with these defaults:

```markdown
# Documentation Style Guide

## Audience
Linux-daily-driver programmers. Comfortable with the terminal, package managers, and reading code.

## Tone
Technical, direct, factual. Like Arch Wiki or man pages. No marketing speak, no fluff, no hand-holding.

## Conventions
- Mermaid diagrams over prose for relationships and flows
- Code examples where they clarify faster than words
- Link between docs rather than duplicating content
- Configuration doc embeds full defaults/backend.toml as a fenced code block
- Each subsystem doc must have at least one mermaid diagram
```

**CRITICAL: Never overwrite any file in `docs/.instructions/`.** If it exists, leave it untouched. These are human-authored.

## Step 2: Read Instruction Files

Read `backend/docs/.instructions/global.md` for style guidance that applies to ALL docs.

For each doc you're about to generate, check if a matching instruction file exists at `backend/docs/.instructions/<doc-name>.md` (e.g., `pipeline.md` for `docs/pipeline.md`). If it exists, read it — its content must be incorporated into the corresponding doc.

## Step 3: Generate Each Doc

For each doc file listed below, follow this process:

1. **Read source files** listed in the source mapping table
2. **Read instruction files** (global + per-doc if exists)
3. **If the doc already exists**: read it, compare against what the current source code says, and apply surgical edits (use Edit tool). Preserve unchanged prose. Add new content, update changed content, remove outdated content.
4. **If the doc does not exist**: create it fresh with Write tool.

### Source File Mapping

| Doc | Primary Sources to Read |
|-----|------------------------|
| getting-started.md | mix.exs, defaults/backend.toml, CLAUDE.md (Build & Run section) |
| configuration.md | defaults/backend.toml, lib/media_centaur/config.ex |
| architecture.md | CLAUDE.md (Architecture Principles, Repository Layout), lib/media_centaur/application.ex, specifications/ directory listing |
| watcher.md | lib/media_centaur/watcher.ex, lib/media_centaur/watcher/supervisor.ex, PIPELINE.md (watcher-relevant sections) |
| pipeline.md | PIPELINE.md, lib/media_centaur/pipeline.ex, lib/media_centaur/pipeline/stages/ (all stage files), lib/media_centaur/pipeline/producer.ex |
| tmdb.md | lib/media_centaur/tmdb/ (all files: client, confidence, mapper, rate_limiter) |
| playback.md | lib/media_centaur/playback/ (all files), specifications/PLAYBACK.md (if exists) |
| channel.md | lib/media_centaur_web/channels/ (all files), specifications/API.md (if exists) |
| library.md | lib/media_centaur/library/ (domain, resources, ingress, helpers), lib/media_centaur/review/ |

### Doc Template (each subsystem doc)

Each subsystem doc should follow this structure. Adapt section depth and content to the subsystem — not every section applies equally to every doc.

```markdown
# <Subsystem Name>

<2-3 sentence purpose statement>

## Architecture

<mermaid diagram(s) showing component relationships, data flow, or supervision tree>

## Key Concepts

<core concepts and terminology specific to this subsystem>

## Configuration

<relevant config options with cross-link to configuration.md>

## How It Works

<detailed walkthrough of the subsystem's behavior, flows, and use cases>

## Module Reference

| Module | Description | Path |
|--------|-------------|------|
| ... | ... | ... |
```

If the instruction file for this doc contains supplementary content, integrate it naturally — append a section, weave it into existing sections, or follow its explicit placement instructions.

### Navigation and Structure

Every doc (including README.md) must have:

1. **Table of contents** — immediately after the title and purpose statement. List all `##`-level headings as markdown links. Example:

   ```markdown
   ## Contents

   - [Architecture](#architecture)
   - [Key Concepts](#key-concepts)
   - [Configuration](#configuration)
   - [How It Works](#how-it-works)
   - [Module Reference](#module-reference)
   ```

2. **Back / forward links** — at the very bottom of the page. Use the doc order from the Output Structure section above. Example:

   ```markdown
   ---

   [← Configuration](configuration.md) | [Architecture →](architecture.md)
   ```

   The first doc (getting-started.md) links back to README.md. The last doc (library.md) has no forward link. README.md has no back link, only a forward to getting-started.md.

**Doc order for navigation:** README → getting-started → configuration → architecture → watcher → pipeline → tmdb → playback → channel → library

### Specification Links

The `../specifications/` directory does not exist in the backend repo — specifications live in a separate repository. All links to specification files must point to the GitHub repository:

`https://github.com/media-centaur/specifications/blob/main/<filename>`

For example:
- `[DATA-FORMAT.md](https://github.com/media-centaur/specifications/blob/main/DATA-FORMAT.md)` — not `../specifications/DATA-FORMAT.md`
- `[PLAYBACK.md](https://github.com/media-centaur/specifications/blob/main/PLAYBACK.md)` — not `../specifications/PLAYBACK.md`

This applies everywhere: README.md, architecture.md, and any doc that references specification files.

### Special Rules

- **configuration.md**: Must embed the full contents of `defaults/backend.toml` as a fenced TOML code block with inline annotations explaining each section.
- **architecture.md**: Must include a top-level mermaid diagram showing how all subsystems relate.
- **getting-started.md**: Must list system dependencies (Erlang/OTP, Elixir versions from mix.exs, SQLite).

## Step 4: Generate README.md

Generate `backend/README.md` with this structure:

1. **One-line description** — what Media Centaur Backend is
2. **What it does** — 3-5 bullet points of key capabilities
3. **Quick start** — minimal commands to get running (from CLAUDE.md build section)
4. **Documentation** — linked table of all `docs/` files with one-line descriptions
5. **Tech stack** — compact table (Elixir, Phoenix, Ash, SQLite, Broadway, etc.)
6. **License** — read mix.exs or LICENSE file for license type; if none found, leave a TODO placeholder

If README.md already exists, apply surgical edits to update it rather than full rewrite.

## Step 5: Summary

After all files are generated/updated, output a summary:

- List each file and whether it was **created** (new) or **updated** (edited existing)
- Note any instruction files that were read and incorporated
- Flag any source files that were referenced but don't exist (suggesting docs may need review)

## Parallelism

Use the Task tool to parallelize where possible:
- Read all source files for independent docs in parallel
- Generate docs that don't depend on each other in parallel
- README.md must be generated LAST (it references all other docs)

## Quality Checks

Before finishing, verify:
- [ ] Every doc in `docs/` is linked from README.md
- [ ] Every subsystem doc has at least one mermaid diagram
- [ ] configuration.md contains the full embedded backend.toml
- [ ] No instruction files were overwritten
- [ ] getting-started.md lists Elixir/OTP version requirements
- [ ] Every doc has a table of contents after the title
- [ ] Every doc has back/forward navigation links at the bottom
- [ ] All specification links point to `https://github.com/media-centaur/specifications/blob/main/` (not relative `../specifications/` paths)
