---
status: accepted
date: 2026-03-03
---
# Test through the public interface

## Context and Problem Statement

When a private function contains complex logic, there's a temptation to make it public (or use `@doc false`) just so tests can call it directly. This couples tests to implementation details, making refactoring painful — every internal restructure breaks tests even when external behavior hasn't changed.

Elixir's module system makes this especially important: a `defp` that's hard to test usually means the module is doing too much or the logic should live in its own module with a clear public API.

## Decision Outcome

Chosen option: "Test behavior through the public API; extract when needed", because it keeps tests resilient to refactoring and pushes toward better module design.

**Rules:**
1. **Never promote `defp` to `def` for testability.** If a private function needs direct testing, extract it into its own module with a proper public API.
2. **Test observable behavior.** Call the public function with inputs that exercise the private path you care about. If you can't reach a code path through the public API, question whether that path should exist.
3. **Extract pure logic into dedicated modules.** Complex computation hiding inside a GenServer callback or LiveView handler belongs in a pure-function module (e.g., `Parser`, `Confidence`, `Mapper`) that's trivially testable.
4. **Keep tests simple.** Modular code means each test targets a small public surface. If a test requires elaborate setup to reach a private code path, that's the design signal — extract, don't expose.

### Consequences

* Good, because tests survive internal refactoring — only public contract changes require test updates
* Good, because it drives modular design: complex private logic naturally migrates into focused, reusable modules
* Good, because it aligns with existing patterns (Parser, Confidence, Serializer are all pure modules extracted for this reason)
* Bad, because testing a specific edge case may require more thoughtful input construction to exercise it through the public API
