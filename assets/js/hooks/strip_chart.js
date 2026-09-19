// StripChart — N uPlot strips sharing one window, one time axis and one
// synced cursor, drawn from frames the server pushes (contract in
// MediaCentaurWeb.Components.StripChart.Feed). The hook owns every element
// inside its container (phx-update="ignore"); the server changes them only
// by sending a frame.
//
// Sizing rule. The root runs under CSS zoom (--ui-scale) and uPlot 1.6.32
// knows nothing of zoom: it maps the pointer with getBoundingClientRect
// (visual px) against its CSS width (layout px) and sizes its canvas by
// devicePixelRatio alone, so under zoom its cursor drifts and its pixels
// blur. Each plot therefore sits in a wrapper whose `zoom: calc(1 /
// var(--ui-scale))` cancels the root zoom (app.css, .strip-chart-plot). At
// effective zoom 1 uPlot's px are physical px: the width comes from the
// wrapper's offsetWidth (already in that space), the backing store holds
// devicePixelRatio × --ui-scale pixels per layout px, and every length the
// hook hands uPlot is multiplied by --ui-scale (lengthsFor) so the strips
// keep their design size. No timers, no animation loop: a redraw happens on
// a frame, a resize or a UI-scale change.
import uPlot from "../../vendor/uplot"
import { parseUiScale } from "../ui_scale"

const FONT_FAMILY = "system-ui, sans-serif"

// --- pure helpers (bun-tested) ---

export function stackColumns(schema, strip) {
  const length = strip.t.length
  const bars = schema.bars
  const data = [strip.t]
  // back to front: the last declared series is the tallest (sum of all)
  for (let outer = bars.length - 1; outer >= 0; outer--) {
    const column = new Array(length)
    for (let i = 0; i < length; i++) {
      let total = 0
      for (let inner = 0; inner <= outer; inner++) total += strip[bars[inner].key][i] || 0
      // A zero bar is null: uPlot skips null, but draws a 0-value bar as a
      // sub-pixel rect that anti-aliases into a dash on the baseline.
      column[i] = total > 0 ? total : null
    }
    data.push(column)
  }
  if (schema.line) data.push(strip[schema.line.key])
  return data
}

export function formatDuration(ms) {
  if (ms == null) return null
  if (ms < 1000) return `${ms} ms`
  const seconds = Math.round(ms / 100) / 10
  return `${Number.isInteger(seconds) ? seconds.toFixed(0) : seconds.toFixed(1)} s`
}

export function formatCount(n) {
  return n.toLocaleString("en-US")
}

export function hoverFigures(schema, strip, idx, timeLabel) {
  const total = schema.bars.reduce((sum, bar) => sum + (strip[bar.key][idx] || 0), 0)
  const first = [{ text: `${formatCount(total)} ${schema.bars_total_label}` }]
  const second = []
  for (const bar of schema.bars) {
    const value = strip[bar.key][idx] || 0
    if (bar.tone === "error") {
      first.push(value > 0 ? { text: `${formatCount(value)} ${bar.label}`, tone: "error" } : { text: `0 ${bar.label}` })
    } else if (bar.tone === "muted" && value > 0) {
      second.push({ text: `${formatCount(value)} ${bar.label}` })
    }
  }
  if (schema.line) {
    const mean = strip[schema.line.key][idx]
    const worst = schema.line.worst_key ? strip[schema.line.worst_key][idx] : null
    if (mean != null) second.push({ text: `${formatDuration(mean)} mean` })
    if (worst != null) second.push({ text: `${formatDuration(worst)} worst` })
  }
  const lines = [[{ text: timeLabel }], first]
  if (second.length > 0) lines.push(second)
  return lines
}

export function niceMax(value) {
  if (!(value > 0)) return 1
  const power = Math.pow(10, Math.floor(Math.log10(value)))
  for (const step of [1, 2, 2.5, 5, 10]) if (step * power >= value) return step * power
  return 10 * power
}

export function integerIncrs() {
  return [1, 2, 5, 10, 20, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000, 50000, 100000]
}

export function axisValuesFor(window) {
  return window === "1w" || window === "1mo" ? "day" : "clock"
}

/**
 * The lengths uPlot receives, in its own (unzoomed) px: the design size
 * multiplied by --ui-scale. `pad` is the room above and below the plot for
 * the count axis's edge labels; it replaces uPlot's auto padding, which
 * differs between a strip with a time axis and one without.
 */
export function lengthsFor(scale) {
  return {
    plotHeight: 72 * scale,
    xAxis: 22 * scale,
    yAxis: 36 * scale,
    lineAxis: 46 * scale,
    pad: 6 * scale,
    axisGap: 4 * scale,
    xSpace: 60 * scale,
    ySpace: 28 * scale,
    // uPlot reads the size back with /(\d+)px/ — it must be whole.
    font: `${Math.round(10 * scale)}px ${FONT_FAMILY}`,
    lineWidth: 1.5 * scale,
    pointSize: 4 * scale,
    barMaxWidth: 100 * scale,
  }
}

/** Indices of values with no drawn neighbour — the only ones drawn as points. */
export function isolatedIndices(column) {
  const idxs = []
  for (let i = 0; i < column.length; i++) {
    if (column[i] != null && column[i - 1] == null && column[i + 1] == null) idxs.push(i)
  }
  return idxs
}

// --- DOM ---

const DAY_NAMES = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

function clockLabel(unix) {
  const date = new Date(unix * 1000)
  return `${String(date.getHours()).padStart(2, "0")}:${String(date.getMinutes()).padStart(2, "0")}`
}

function dayLabel(unix) {
  const date = new Date(unix * 1000)
  return `${DAY_NAMES[date.getDay()]} ${date.getDate()}`
}

// Colors come from registered <color> custom properties (app.css), so the
// computed values are resolved colors a canvas accepts.
function readTheme() {
  const style = getComputedStyle(document.documentElement)
  const token = (name) => style.getPropertyValue(name).trim()
  return {
    error: token("--strip-chart-bar-error"),
    solid: token("--strip-chart-bar-solid"),
    muted: token("--strip-chart-bar-muted"),
    line: token("--strip-chart-line"),
    grid: token("--strip-chart-grid"),
    axisText: token("--strip-chart-axis-text"),
    scale: parseUiScale(token("--ui-scale")),
  }
}

function renderFigures(container, lines) {
  container.replaceChildren()
  for (const line of lines) {
    const row = document.createElement("div")
    line.forEach((segment, index) => {
      if (index > 0) {
        const sep = document.createElement("span")
        sep.className = "strip-chart-sep"
        sep.textContent = " · "
        row.appendChild(sep)
      }
      const span = document.createElement("span")
      span.textContent = segment.text
      if (segment.tone) span.dataset.tone = segment.tone
      row.appendChild(span)
    })
    container.appendChild(row)
  }
}

export const StripChart = {
  mounted() {
    this.id = this.el.id
    this.strips = new Map()
    this.frame = null
    this.hoverIdx = null
    this.theme = readTheme()

    this.handleEvent("strip_chart:frame", (frame) => {
      if (frame.id !== this.id) return
      this.applyFrame(frame)
    })

    this.onVisibility = () => this.pushVisibility()
    document.addEventListener("visibilitychange", this.onVisibility)
    if (document.visibilityState === "hidden") this.pushVisibility()

    // Both converge on syncLayout. The settings event is needed on its own:
    // a card held at a max-width keeps its layout width when the scale
    // changes, so the observer alone would miss the new scale.
    this.onScale = () => this.syncLayout()
    window.addEventListener("phx:ui-scale", this.onScale)

    this.layoutPending = false
    this.observer = new ResizeObserver(() => {
      if (this.layoutPending) return
      this.layoutPending = true
      requestAnimationFrame(() => {
        this.layoutPending = false
        this.syncLayout()
      })
    })
    this.observer.observe(this.el)
  },

  destroyed() {
    document.removeEventListener("visibilitychange", this.onVisibility)
    window.removeEventListener("phx:ui-scale", this.onScale)
    this.observer?.disconnect()
    for (const { chart } of this.strips.values()) chart.destroy()
    this.strips.clear()
  },

  pushVisibility() {
    this.pushEvent("strip_chart:visibility", { id: this.id, visible: document.visibilityState === "visible" })
  },

  applyFrame(frame) {
    const ids = frame.strips.map((s) => s.id)
    const current = [...this.strips.keys()]
    const sameSet = ids.length === current.length && ids.every((id, i) => id === current[i])
    const windowChanged = this.frame != null && this.frame.window !== frame.window
    this.frame = frame
    if (!sameSet || windowChanged) this.rebuild()
    else frame.strips.forEach((strip) => this.updateStrip(strip))
  },

  rebuild() {
    const frame = this.frame
    for (const { chart } of this.strips.values()) chart.destroy()
    this.strips.clear()
    this.el.replaceChildren()
    frame.strips.forEach((strip, index) => {
      const row = document.createElement("div")
      row.className = "strip-chart-strip"
      row.dataset.strip = strip.id

      const name = document.createElement("div")
      const title = document.createElement("div")
      title.className = "strip-chart-name"
      const dot = document.createElement("span")
      dot.className = "strip-chart-dot"
      const label = document.createElement("span")
      label.textContent = strip.label
      const time = document.createElement("span")
      time.className = "strip-chart-time"
      title.append(dot, label, time)
      const figures = document.createElement("div")
      figures.className = "strip-chart-figures"
      name.append(title, figures)

      const plot = document.createElement("div")
      plot.className = "strip-chart-plot"
      row.append(name, plot)
      this.el.appendChild(row)

      const isLast = index === frame.strips.length - 1
      const chart = new uPlot(this.options(isLast, plot.offsetWidth), stackColumns(frame.schema, strip), plot)
      const entry = { chart, dot, time, figures, plot, strip }
      this.strips.set(strip.id, entry)
      this.paint(entry)
    })
  },

  updateStrip(strip) {
    const entry = this.strips.get(strip.id)
    if (!entry) return
    entry.strip = strip
    entry.chart.setData(stackColumns(this.frame.schema, strip))
    this.paint(entry)
  },

  paint(entry) {
    entry.dot.dataset.dot = entry.strip.dot
    this.renderHover(entry, this.hoverIdx)
  },

  renderHover(entry, idx) {
    const strip = entry.strip
    if (idx == null || idx >= strip.t.length) {
      entry.time.textContent = ""
      renderFigures(entry.figures, strip.figures)
      // Reserve the rest-state height: the hover readout has fewer lines,
      // and letting the column shrink would reflow every strip under the
      // pointer. Re-measured on each frame so a new line (the TMDB slots
      // budget appearing) still grows the row at a frame boundary.
      entry.figures.style.minHeight = ""
      const restHeight = entry.figures.offsetHeight
      if (restHeight > 0) entry.figures.style.minHeight = `${restHeight}px`
      return
    }
    const labeler = axisValuesFor(this.frame.window) === "day" ? dayLabel : clockLabel
    const lines = hoverFigures(this.frame.schema, strip, idx, labeler(strip.t[idx]))
    entry.time.textContent = lines[0][0].text
    renderFigures(entry.figures, lines.slice(1))
  },

  setHover(idx) {
    if (idx === this.hoverIdx) return
    this.hoverIdx = idx
    for (const entry of this.strips.values()) this.renderHover(entry, idx)
  },

  options(isLast, width) {
    const theme = this.theme
    const schema = this.frame.schema
    const lengths = lengthsFor(theme.scale)
    const labeler = axisValuesFor(this.frame.window) === "day" ? dayLabel : clockLabel
    const barTone = (tone) => theme[tone] || theme.solid
    const barsPath = uPlot.paths.bars({ size: [0.62, lengths.barMaxWidth], align: 0 })

    const series = [{}]
    for (let i = schema.bars.length - 1; i >= 0; i--) {
      const bar = schema.bars[i]
      series.push({
        scale: "y", paths: barsPath, fill: barTone(bar.tone), stroke: barTone(bar.tone), width: 0,
        points: { show: false },
      })
    }
    if (schema.line) {
      series.push({
        scale: "ms", stroke: theme.line, width: lengths.lineWidth, spanGaps: false,
        points: {
          show: false,
          filter: (u, seriesIdx) => isolatedIndices(u.data[seriesIdx]),
          size: lengths.pointSize, width: 0, fill: theme.line,
        },
      })
    }

    const axes = [
      {
        // Every strip draws the vertical grid so the plots read as one
        // picture; only the last strip spends height on time labels.
        scale: "x", size: isLast ? lengths.xAxis : 0, gap: isLast ? lengths.axisGap : 0,
        stroke: theme.axisText, font: lengths.font, ticks: { show: false },
        grid: { stroke: theme.grid, width: 1 }, space: lengths.xSpace,
        values: (u, splits) => (isLast ? splits.map(labeler) : splits.map(() => "")),
      },
      {
        scale: "y", size: lengths.yAxis, gap: lengths.axisGap, stroke: theme.axisText, font: lengths.font,
        ticks: { show: false }, grid: { stroke: theme.grid, width: 1 }, incrs: integerIncrs(), space: lengths.ySpace,
        values: (u, splits) => splits.map((v) => (Number.isInteger(v) ? formatCount(v) : "")),
      },
    ]
    const scales = { x: { time: true }, y: { range: (u, min, max) => [0, niceMax(max)] } }
    if (schema.line) {
      axes.push({
        scale: "ms", side: 1, size: lengths.lineAxis, gap: lengths.axisGap, stroke: theme.line, font: lengths.font,
        ticks: { show: false }, grid: { show: false }, space: lengths.ySpace,
        // An idle strip has no latency at all; its ms scale is scaffolding
        // (0–1) and labelling it would claim a measurement that never happened.
        values: (u, splits) => {
          const line = u.data[u.data.length - 1]
          if (!line || line.every((v) => v == null)) return splits.map(() => "")
          return splits.map((v) => (v > 0 && Number.isInteger(v) ? formatDuration(v) : ""))
        },
      })
      scales.ms = { range: (u, min, max) => [0, niceMax(max)] }
    }

    return {
      width,
      height: lengths.plotHeight + lengths.pad + (isLast ? lengths.xAxis : lengths.pad),
      // Explicit, so every strip's plot area is plotHeight tall: uPlot would
      // otherwise auto-pad the side without an axis.
      padding: [lengths.pad, 0, isLast ? 0 : lengths.pad, 0],
      legend: { show: false },
      cursor: {
        sync: { key: this.id }, x: true, y: false, points: { show: false },
        drag: { x: false, y: false },
      },
      hooks: { setCursor: [(u) => this.setHover(u.cursor.idx)] },
      scales, axes, series,
    }
  },

  // A width change resizes in place; a scale change rebuilds, because the
  // lengths in every uPlot option were computed for the old scale.
  syncLayout() {
    const theme = readTheme()
    const scaleChanged = theme.scale !== this.theme.scale
    this.theme = theme
    if (scaleChanged && this.frame) this.rebuild()
    else this.resizeAll()
  },

  resizeAll() {
    for (const { chart, plot } of this.strips.values()) {
      const width = plot.offsetWidth
      if (width > 0 && width !== chart.width) chart.setSize({ width, height: chart.height })
    }
  },
}
