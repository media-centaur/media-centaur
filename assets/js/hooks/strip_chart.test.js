import { describe, expect, test } from "bun:test"
import {
  stackColumns, hoverFigures, formatDuration, niceMax, integerIncrs, axisValuesFor, lengthsFor,
  isolatedIndices,
} from "./strip_chart"

const schema = {
  bars: [
    { key: "failed", label: "failed", tone: "error" },
    { key: "went_out", label: "went out", tone: "solid" },
    { key: "cached", label: "from cache", tone: "muted" },
  ],
  bars_total_label: "requests",
  line: { key: "mean_us", worst_key: "worst_us", label: "mean latency" },
}

const strip = {
  t: [100, 160], failed: [1, 0], went_out: [2, 3], cached: [4, 0], mean_us: [180_000, 90_000], worst_us: [400_000, 90_000],
}

describe("stackColumns", () => {
  test("returns uPlot data: x, then bars back to front as cumulative heights, then the line", () => {
    expect(stackColumns(schema, strip)).toEqual([
      [100, 160],
      [7, 3],      // cached total = failed + went_out + cached
      [3, 3],      // went_out total = failed + went_out
      [1, null],   // failed; a zero bar is null so uPlot draws nothing for it
      [180_000, 90_000],
    ])
  })
  test("a bucket without requests has no bars at all", () => {
    const quiet = { t: [100], failed: [0], went_out: [0], cached: [0], mean_us: [null], worst_us: [null] }
    expect(stackColumns(schema, quiet)).toEqual([[100], [null], [null], [null], [null]])
  })
  test("omits the line when the schema has none", () => {
    expect(stackColumns({ ...schema, line: undefined }, strip)).toHaveLength(4)
  })
})

describe("hoverFigures", () => {
  test("formats the bucket's figures from the columns", () => {
    expect(hoverFigures(schema, strip, 0, "13:26")).toEqual([
      [{ text: "13:26" }],
      [{ text: "7 requests" }, { text: "1 failed", tone: "error" }],
      [{ text: "4 from cache" }, { text: "180 ms mean" }, { text: "400 ms worst" }],
    ])
  })
  test("a bucket without requests has no latency and says 0 failed", () => {
    const quiet = { ...strip, failed: [0], went_out: [0], cached: [0], mean_us: [null], worst_us: [null] }
    expect(hoverFigures(schema, quiet, 0, "13:26")).toEqual([
      [{ text: "13:26" }],
      [{ text: "0 requests" }, { text: "0 failed" }],
    ])
  })
})

// The same table as StatusHelpers.format_duration/1's tests: the server
// formats the rest-state figures, this formats the hover readout and axis.
describe("formatDuration (microseconds)", () => {
  test("tenths of a millisecond under ten milliseconds", () => {
    expect(formatDuration(420)).toBe("0.4 ms")
    expect(formatDuration(2350)).toBe("2.4 ms")
    expect(formatDuration(1000)).toBe("1 ms")
    expect(formatDuration(30)).toBe("0 ms")
  })
  test("whole milliseconds under a second", () => {
    expect(formatDuration(9960)).toBe("10 ms")
    expect(formatDuration(279400)).toBe("279 ms")
  })
  test("tenths of a second under a minute", () => {
    expect(formatDuration(999600)).toBe("1 s")
    expect(formatDuration(1650000)).toBe("1.7 s")
    expect(formatDuration(3000000)).toBe("3 s")
  })
  test("tenths of a minute from a minute", () => {
    expect(formatDuration(59970000)).toBe("1 min")
    expect(formatDuration(150000000)).toBe("2.5 min")
  })
})

describe("axes", () => {
  test("niceMax rounds up to 1/2/2.5/5/10 steps and never below 1", () => {
    expect(niceMax(0)).toBe(1)
    expect(niceMax(3)).toBe(5)
    expect(niceMax(7)).toBe(10)
    expect(niceMax(23)).toBe(25)
    expect(niceMax(120)).toBe(200)
  })
  test("integer increments only", () => {
    expect(integerIncrs().every(Number.isInteger)).toBe(true)
    expect(integerIncrs().slice(0, 4)).toEqual([1, 2, 5, 10])
  })
  test("clock labels up to a day, day labels for a week and a month", () => {
    expect(axisValuesFor("1h")).toBe("clock")
    expect(axisValuesFor("1d")).toBe("clock")
    expect(axisValuesFor("1w")).toBe("day")
    expect(axisValuesFor("1mo")).toBe("day")
  })
})

// The plots live in a wrapper that cancels the root zoom, so every length the
// hook hands uPlot is multiplied by --ui-scale itself.
describe("lengthsFor", () => {
  test("scale 1 is the design size: 72px plot, 22px time axis", () => {
    const lengths = lengthsFor(1)
    expect(lengths.plotHeight).toBe(72)
    expect(lengths.xAxis).toBe(22)
    expect(lengths.font).toBe("10px system-ui, sans-serif")
  })
  test("lengths scale linearly", () => {
    const lengths = lengthsFor(2)
    expect(lengths.plotHeight).toBe(144)
    expect(lengths.yAxis).toBe(lengthsFor(1).yAxis * 2)
    expect(lengths.lineWidth).toBe(3)
  })
  test("the font size is a whole number of px (uPlot parses it with \\d+px)", () => {
    expect(lengthsFor(1.25).font).toBe("13px system-ui, sans-serif")
    expect(lengthsFor(0.7).font).toBe("7px system-ui, sans-serif")
  })
})

// A line value with a drawn neighbour is already visible as a segment; only a
// value alone between gaps needs a point.
describe("isolatedIndices", () => {
  test("values with no neighbour on either side", () => {
    expect(isolatedIndices([null, 120, null, 90, 80, null, null, 70])).toEqual([1, 7])
  })
  test("a continuous line has no isolated values", () => {
    expect(isolatedIndices([1, 2, 3])).toEqual([])
    expect(isolatedIndices([])).toEqual([])
  })
  test("a single value is isolated", () => {
    expect(isolatedIndices([5])).toEqual([0])
  })
})
