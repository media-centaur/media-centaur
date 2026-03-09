---
status: accepted
date: 2026-03-09
---
# Left wall enters sidebar

## Context and Problem Statement

The keyboard spatial navigation system has multiple horizontal control rows: zone tabs (Continue Watching / Library), the filter toolbar, and the card grid. When the user presses Left at the leftmost item in the grid, focus correctly moves into the sidebar. But pressing Left at the leftmost zone tab or toolbar control does nothing — the cursor is clamped and stuck.

This violates the user's spatial model: the sidebar is physically to the left of all page content, so pressing Left at the left edge of *any* row should enter it.

## Decision Outcome

Pressing Left at index 0 of any horizontal content row (zone tabs, toolbar, grid) enters the sidebar. The rule is universal — no row silently swallows a left-arrow at its left edge.

When returning from the sidebar (pressing Right), focus restores to the context the user came from (zone tabs, toolbar, or grid) at the remembered position.
