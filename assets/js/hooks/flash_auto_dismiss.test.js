import { describe, expect, test } from "bun:test"
import { parseDelay } from "./flash_auto_dismiss"

// parseDelay reads the `data-dismiss-after` attribute. A positive integer
// arms the auto-dismiss countdown; anything else means "persistent" (the
// connection-state toasts that must linger until the condition resolves).
describe("parseDelay", () => {
  test("positive integer string → that many ms", () => {
    expect(parseDelay("4000")).toBe(4000)
  })

  test("absent attribute → null (persistent)", () => {
    expect(parseDelay(undefined)).toBe(null)
    expect(parseDelay(null)).toBe(null)
    expect(parseDelay("")).toBe(null)
  })

  test("zero and negative → null (never auto-dismiss)", () => {
    expect(parseDelay("0")).toBe(null)
    expect(parseDelay("-1000")).toBe(null)
  })

  test("non-numeric → null", () => {
    expect(parseDelay("soon")).toBe(null)
  })
})
