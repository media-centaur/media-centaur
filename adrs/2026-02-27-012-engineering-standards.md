---
status: accepted
date: 2026-02-27
---
# Engineering standards: test-first, spec-first, zero warnings

## Context and Problem Statement

The media manager's pipeline processes files silently in the background. Bugs are invisible — a malformed entity, a missing image, or a dropped file produces no visible error. The system needs engineering standards that catch problems before they reach production, not after.

## Decision Outcome

Chosen option: "test-first development, spec-first contracts, and zero warnings policy as complementary quality disciplines", because each addresses a different failure mode and they reinforce each other.

**Test-first:**
- Write tests before implementation for all new features and bug fixes
- Tests are the executable specification — if you can't write the test, the requirements aren't clear enough
- Parser tests use real file paths observed in the wild — never synthetic paths
- Pipeline tests are mandatory and must never be deleted or weakened
- Pipeline tests call stage functions directly — no Broadway topology in tests

**Spec-first contracts:**
- Every contract between the backend and UI must be documented in a specification file before implementation ships
- `DATA-FORMAT.md` is the canonical reference for entity serialization
- `IMAGE-CACHING.md` is the canonical reference for image storage conventions
- New entity fields must check schema.org first

**Zero warnings:**
- Application code and tests must compile and run with zero warnings
- This includes unused variables, unused aliases, unused imports, and log output indicating misconfiguration
- `mix precommit` enforces `--warnings-as-errors` before every change

### Consequences

* Good, because test-first catches pipeline bugs before they silently corrupt data
* Good, because spec-first prevents backend/UI contract drift — both sides code against the same document
* Good, because zero warnings eliminates dead code accumulation and catches misconfigured test stubs
* Bad, because test-first requires discipline — writing tests for every change adds up-front time
* Bad, because zero warnings can slow down exploratory work — every experiment must clean up after itself
