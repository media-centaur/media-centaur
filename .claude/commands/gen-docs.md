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
| architecture.md | CLAUDE.md (Architecture Principles, Repository Layout), lib/media_centaur/application.ex, specs/ directory listing |
| watcher.md | lib/media_centaur/watcher.ex, lib/media_centaur/watcher/supervisor.ex, PIPELINE.md (watcher-relevant sections) |
| pipeline.md | PIPELINE.md, lib/media_centaur/pipeline.ex, lib/media_centaur/pipeline/stages/ (all stage files), lib/media_centaur/pipeline/producer.ex |
| tmdb.md | lib/media_centaur/tmdb/ (all files: client, confidence, mapper, rate_limiter) |
| playback.md | lib/media_centaur/playback/ (all files), specs/PLAYBACK.md |
| channel.md | lib/media_centaur_web/channels/ (all files), specs/API.md |
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

Every doc in `docs/` must have two navigation elements immediately after the title and purpose statement:

1. **Cross-doc navigation bar** — a blockquote listing all docs separated by ` · `. The current page is **bold** (not linked); all others are linked. Example for `architecture.md`:

   ```markdown
   > [Getting Started](getting-started.md) · [Configuration](configuration.md) · **Architecture** · [Watcher](watcher.md) · [Pipeline](pipeline.md) · [TMDB](tmdb.md) · [Playback](playback.md) · [Channels](channel.md) · [Library](library.md)
   ```

2. **Page table of contents** — a bare bullet list of all `##`-level headings as anchor links. No heading above it — it flows directly after the nav bar.

**Doc order:** Getting Started · Configuration · Architecture · Watcher · Pipeline · TMDB · Playback · Channels · Library

**README.md** does NOT get a nav bar or page TOC — it links to `docs/getting-started.md` as the entry point and the docs handle their own cross-navigation.

Do NOT add:
- `## Contents` headings (visual clutter)
- Back/forward links at the bottom (the nav bar makes them redundant)
- Duplicate doc indexes in README

### Specification Links

Specifications live in `specs/` within the backend repo. All links to specification files must use relative paths to `specs/`:

For example:
- `[DATA-FORMAT.md](../specs/DATA-FORMAT.md)` from a file in `docs/`
- `[PLAYBACK.md](specs/PLAYBACK.md)` from a file in the backend root

This applies everywhere: README.md, architecture.md, and any doc that references specification files.

### Special Rules

- **configuration.md**: Must embed the full contents of `defaults/backend.toml` as a fenced TOML code block with inline annotations explaining each section.
- **architecture.md**: Must include a top-level mermaid diagram showing how all subsystems relate.
- **getting-started.md**: Must list system dependencies (Erlang/OTP, Elixir versions from mix.exs, SQLite).

## Step 4: Generate README.md

Generate `backend/README.md` with this structure:

1. **One-line description** — what Media Centaur Backend is
2. **What it does** — 3-5 bullet points of key capabilities
3. **Documentation link** — single line linking to `docs/getting-started.md` as the entry point (do NOT duplicate the quick start or the full doc index here — the docs have their own TOC and navigation)
4. **Tech stack** — compact table (Elixir, Phoenix, Ash, SQLite, Broadway, etc.)
5. **License** — read mix.exs or LICENSE file for license type; if none found, leave a TODO placeholder

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
- [ ] README.md links to `docs/getting-started.md` as the documentation entry point
- [ ] Every subsystem doc has at least one mermaid diagram
- [ ] configuration.md contains the full embedded backend.toml
- [ ] No instruction files were overwritten
- [ ] getting-started.md lists Elixir/OTP version requirements
- [ ] Every doc in `docs/` has a cross-doc nav bar and page TOC (no `## Contents` heading)
- [ ] No back/forward links at the bottom of any doc
- [ ] All specification links use relative paths to `specs/`
