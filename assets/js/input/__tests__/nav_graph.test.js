import { describe, expect, test } from "bun:test"
import { buildNavGraph, resolveCursorStart } from "../nav_graph"

/** Counts where everything is populated */
function fullCounts() {
  return { grid: 12, toolbar: 3, zone_tabs: 2, sidebar: 4, drawer: 5 }
}

describe("buildNavGraph", () => {
  describe("library zone, all populated", () => {
    const graph = buildNavGraph("library", fullCounts(), { drawerOpen: true })

    test("toolbar down goes to grid", () => {
      expect(graph.toolbar.down).toBe("grid")
    })

    test("toolbar up goes to zone_tabs", () => {
      expect(graph.toolbar.up).toBe("zone_tabs")
    })

    test("toolbar left goes to sidebar", () => {
      expect(graph.toolbar.left).toBe("sidebar")
    })

    test("zone_tabs down goes to toolbar (first candidate)", () => {
      expect(graph.zone_tabs.down).toBe("toolbar")
    })

    test("zone_tabs left goes to sidebar", () => {
      expect(graph.zone_tabs.left).toBe("sidebar")
    })

    test("grid up goes to toolbar (first candidate)", () => {
      expect(graph.grid.up).toBe("toolbar")
    })

    test("grid left goes to sidebar", () => {
      expect(graph.grid.left).toBe("sidebar")
    })

    test("grid right goes to drawer when open", () => {
      expect(graph.grid.right).toBe("drawer")
    })

    test("sidebar right goes to grid (first candidate)", () => {
      expect(graph.sidebar.right).toBe("grid")
    })

    test("drawer left goes to grid (first candidate)", () => {
      expect(graph.drawer.left).toBe("grid")
    })
  })

  describe("library zone, empty grid", () => {
    const counts = { grid: 0, toolbar: 3, zone_tabs: 2, sidebar: 4 }
    const graph = buildNavGraph("library", counts)

    test("toolbar down blocked (grid is only candidate)", () => {
      expect(graph.toolbar.down).toBeUndefined()
    })

    test("zone_tabs down skips empty toolbar? no — toolbar is populated, goes there", () => {
      expect(graph.zone_tabs.down).toBe("toolbar")
    })

    test("grid up still goes to toolbar", () => {
      expect(graph.grid.up).toBe("toolbar")
    })

    test("sidebar right skips empty grid, goes to toolbar", () => {
      expect(graph.sidebar.right).toBe("toolbar")
    })

    test("drawer left skips empty grid, goes to toolbar", () => {
      const withDrawer = buildNavGraph("library", counts, { drawerOpen: true })
      expect(withDrawer.drawer.left).toBe("toolbar")
    })
  })

  describe("library zone, empty grid and toolbar", () => {
    const counts = { grid: 0, toolbar: 0, zone_tabs: 2, sidebar: 4 }
    const graph = buildNavGraph("library", counts)

    test("zone_tabs down skips both empty candidates, blocked", () => {
      expect(graph.zone_tabs.down).toBeUndefined()
    })

    test("sidebar right skips grid and toolbar, goes to zone_tabs", () => {
      expect(graph.sidebar.right).toBe("zone_tabs")
    })

    test("grid up skips toolbar, goes to zone_tabs", () => {
      expect(graph.grid.up).toBe("zone_tabs")
    })
  })

  describe("library zone, only sidebar populated", () => {
    const counts = { grid: 0, toolbar: 0, zone_tabs: 0, sidebar: 4 }
    const graph = buildNavGraph("library", counts)

    test("zone_tabs down blocked", () => {
      expect(graph.zone_tabs.down).toBeUndefined()
    })

    test("zone_tabs left goes to sidebar", () => {
      expect(graph.zone_tabs.left).toBe("sidebar")
    })

    test("sidebar right blocked (all candidates empty)", () => {
      expect(graph.sidebar.right).toBeUndefined()
    })
  })

  describe("watching zone, all populated", () => {
    const graph = buildNavGraph("watching", fullCounts())

    test("zone_tabs down goes to grid", () => {
      expect(graph.zone_tabs.down).toBe("grid")
    })

    test("grid up goes to zone_tabs", () => {
      expect(graph.grid.up).toBe("zone_tabs")
    })

    test("grid left goes to sidebar", () => {
      expect(graph.grid.left).toBe("sidebar")
    })

    test("sidebar right goes to grid", () => {
      expect(graph.sidebar.right).toBe("grid")
    })

    test("no toolbar in watching layout", () => {
      expect(graph.toolbar).toBeUndefined()
    })
  })

  describe("watching zone, empty grid", () => {
    const counts = { grid: 0, zone_tabs: 2, sidebar: 4 }
    const graph = buildNavGraph("watching", counts)

    test("zone_tabs down blocked (grid is only candidate)", () => {
      expect(graph.zone_tabs.down).toBeUndefined()
    })

    test("sidebar right skips empty grid, goes to zone_tabs", () => {
      expect(graph.sidebar.right).toBe("zone_tabs")
    })
  })

  describe("watching zone, only sidebar populated", () => {
    const counts = { grid: 0, zone_tabs: 0, sidebar: 4 }
    const graph = buildNavGraph("watching", counts)

    test("sidebar right blocked", () => {
      expect(graph.sidebar.right).toBeUndefined()
    })
  })

  describe("drawer edges", () => {
    test("grid right has no edge when drawer is closed", () => {
      const graph = buildNavGraph("library", fullCounts(), { drawerOpen: false })
      expect(graph.grid.right).toBeUndefined()
    })

    test("grid right goes to drawer when open", () => {
      const graph = buildNavGraph("library", fullCounts(), { drawerOpen: true })
      expect(graph.grid.right).toBe("drawer")
    })

    test("drawer context excluded entirely when closed", () => {
      const graph = buildNavGraph("library", fullCounts(), { drawerOpen: false })
      expect(graph.drawer).toBeUndefined()
    })

    test("drawer left goes to grid when open and populated", () => {
      const graph = buildNavGraph("library", fullCounts(), { drawerOpen: true })
      expect(graph.drawer.left).toBe("grid")
    })

    test("drawer left skips empty grid, goes to toolbar", () => {
      const counts = { grid: 0, toolbar: 3, zone_tabs: 2, sidebar: 4, drawer: 5 }
      const graph = buildNavGraph("library", counts, { drawerOpen: true })
      expect(graph.drawer.left).toBe("toolbar")
    })

    test("drawer left skips empty grid and toolbar, blocked (no more candidates)", () => {
      const counts = { grid: 0, toolbar: 0, zone_tabs: 2, sidebar: 4, drawer: 5 }
      const graph = buildNavGraph("library", counts, { drawerOpen: true })
      expect(graph.drawer.left).toBeUndefined()
    })
  })

  describe("edge cases", () => {
    test("unknown zone returns empty graph", () => {
      expect(buildNavGraph("unknown", fullCounts())).toEqual({})
    })
  })
})

describe("resolveCursorStart", () => {
  test("library zone with full counts returns grid", () => {
    expect(resolveCursorStart("library", fullCounts())).toBe("grid")
  })

  test("library zone with empty grid returns toolbar", () => {
    expect(resolveCursorStart("library", { grid: 0, toolbar: 3, zone_tabs: 2, sidebar: 4 })).toBe("toolbar")
  })

  test("library zone with empty grid and toolbar returns zone_tabs", () => {
    expect(resolveCursorStart("library", { grid: 0, toolbar: 0, zone_tabs: 2, sidebar: 4 })).toBe("zone_tabs")
  })

  test("library zone with only sidebar returns sidebar", () => {
    expect(resolveCursorStart("library", { grid: 0, toolbar: 0, zone_tabs: 0, sidebar: 4 })).toBe("sidebar")
  })

  test("watching zone with full counts returns grid", () => {
    expect(resolveCursorStart("watching", fullCounts())).toBe("grid")
  })

  test("watching zone with empty grid returns zone_tabs", () => {
    expect(resolveCursorStart("watching", { grid: 0, zone_tabs: 2, sidebar: 4 })).toBe("zone_tabs")
  })

  test("watching zone with only sidebar returns sidebar", () => {
    expect(resolveCursorStart("watching", { grid: 0, zone_tabs: 0, sidebar: 4 })).toBe("sidebar")
  })

  test("unknown zone returns null", () => {
    expect(resolveCursorStart("unknown", fullCounts())).toBeNull()
  })
})
