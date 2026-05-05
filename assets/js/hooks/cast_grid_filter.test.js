import { describe, expect, test } from "bun:test"
import { visibleIndices } from "./cast_grid_filter"

// Cards passed to `visibleIndices` are pre-lowercased on the server so the
// helper stays cheap (one allocation per query, no per-card .toLowerCase()).
const cards = [
  { name: "zach braff",      character: "j.d. dorian" },
  { name: "donald faison",   character: "christopher turk" },
  { name: "sarah chalke",    character: "elliot reid" },
  { name: "judy reyes",      character: "carla espinosa" },
  { name: "john c. mcginley", character: "perry cox" },
  { name: "ken jenkins",     character: "bob kelso" },
  { name: "neil flynn",      character: "the janitor" }
]

describe("visibleIndices", () => {
  test("empty query returns the first maxVisible indices", () => {
    expect(visibleIndices(cards, "", 3)).toEqual([0, 1, 2])
  })

  test("empty query is also returned when query is null/undefined", () => {
    expect(visibleIndices(cards, null, 3)).toEqual([0, 1, 2])
    expect(visibleIndices(cards, undefined, 3)).toEqual([0, 1, 2])
  })

  test("substring match in name", () => {
    // "braff" only matches Zach Braff
    expect(visibleIndices(cards, "braff", 24)).toEqual([0])
  })

  test("substring match in character", () => {
    // "turk" only matches Christopher Turk's character
    expect(visibleIndices(cards, "turk", 24)).toEqual([1])
  })

  test("case-insensitive matching", () => {
    // Query is lowercased; cards are pre-lowercased, so this works without
    // the helper having to canonicalise card sides.
    expect(visibleIndices(cards, "BRAFF", 24)).toEqual([0])
    expect(visibleIndices(cards, "Turk", 24)).toEqual([1])
  })

  test("matches across both name and character fields", () => {
    // "j" matches J.D. Dorian (character, idx 0), judy reyes (name, 3),
    // john c. mcginley (name, 4), ken jenkins (name, 5), neil flynn /
    // the janitor (character, 6).
    expect(visibleIndices(cards, "j", 24)).toEqual([0, 3, 4, 5, 6])
  })

  test("zero matches returns empty array", () => {
    expect(visibleIndices(cards, "xyzzy", 24)).toEqual([])
  })

  test("cap is enforced even when more than maxVisible match", () => {
    // Empty query = every card matches. With maxVisible=4 we get exactly 4.
    expect(visibleIndices(cards, "", 4)).toEqual([0, 1, 2, 3])
    expect(visibleIndices(cards, "", 4).length).toBe(4)
  })

  test("returned indices preserve original card order", () => {
    // "n" matches "donald faison" (1), "john c. mcginley" (4), "ken
    // jenkins" (5), "neil flynn" (6), "carla espinosa" (3 — character
    // contains "n"), "j.d. dorian" (0 — character contains "n").
    // The helper must return them in original index order, not match-order.
    const result = visibleIndices(cards, "n", 24)
    const sorted = [...result].sort((a, b) => a - b)
    expect(result).toEqual(sorted)
  })

  test("empty cards array returns empty array", () => {
    expect(visibleIndices([], "anything", 24)).toEqual([])
  })

  test("missing character field is treated as empty (no crash)", () => {
    const sparse = [
      { name: "linked person", character: null },
      { name: "another",       character: undefined },
      { name: "third",         /* no character key */ }
    ]
    // None of these have searchable characters; "linked" still matches
    // the first by name.
    expect(visibleIndices(sparse, "linked", 24)).toEqual([0])
    expect(visibleIndices(sparse, "third", 24)).toEqual([2])
  })

  test("maxVisible of 0 returns empty array", () => {
    expect(visibleIndices(cards, "", 0)).toEqual([])
    expect(visibleIndices(cards, "braff", 0)).toEqual([])
  })
})
