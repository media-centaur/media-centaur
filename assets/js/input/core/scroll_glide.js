/**
 * Scroll glide — eases scroll containers toward a target offset.
 *
 * The cursor moves instantly; the viewport catches up. Focus is never where
 * the animation is, so SELECT mid-glide always activates the card the user is
 * actually on — only the eye is being led.
 *
 * **Why not the browser's own smooth scrolling.** Both native routes fail
 * under held input, measured on the home shelves:
 *
 * - `scrollIntoView({behavior: "smooth"})` stops retargeting entirely and
 *   strands the row mid-glide.
 * - CSS `scroll-behavior: smooth` retargets, but restarts its ease-in curve
 *   from rest on every new target. A held arrow repeats every ~33ms, far
 *   faster than the ~450ms curve, so the row never escapes the slow opening of
 *   the easing: the cursor ran 3015px off-screen while `scrollLeft` sat at 3,
 *   then the row lurched the whole distance the moment the key came up.
 *
 * The fix is to make speed a function of *distance remaining* rather than of
 * time-since-this-animation-started. Each frame closes a fixed fraction of the
 * gap, so a target that keeps running away is chased harder, never slower —
 * and there is no per-animation state to restart, because retargeting is just
 * a new number in the same map. A near target and a far one take about the
 * same time to arrive; the far one simply moves faster.
 *
 * Frame-rate independent: the fraction is derived from elapsed time, so a
 * dropped frame changes nothing about where the row ends up.
 *
 * A write the browser rounds back to the same offset ends the glide at the
 * target: under a root zoom, sub-device-pixel steps never close the gap.
 *
 * All external dependencies (`requestAnimationFrame`, a clock) are injected,
 * following the same DI pattern as the rest of the framework.
 */

/**
 * Time constant of the exponential approach, in ms. Each TAU closes ~63% of
 * the remaining distance, so a glide is ~95% done after 3×TAU. Tuned for a
 * screen watched from across a room: slow enough for the eye to follow the
 * movement, fast enough that a held direction doesn't feel like wading.
 */
const DEFAULT_TAU = 110

/** Below this many px the animation is over — snap and stop. */
const EPSILON = 0.5

/** The two scroll axes: the target key and the box properties it moves. */
const AXES = [
  { key: "left", offset: "scrollLeft", extent: "scrollWidth", port: "clientWidth" },
  { key: "top", offset: "scrollTop", extent: "scrollHeight", port: "clientHeight" },
]

/**
 * @param {Object} config
 * @param {function} config.requestAnimationFrame
 * @param {function(): number} config.now - Monotonic clock in ms
 * @param {number} [config.tau] - Time constant override
 */
export function createScrollGlide({ requestAnimationFrame, now, tau = DEFAULT_TAU } = {}) {
  /** box -> { left?: number, top?: number } — the offsets it is heading for. */
  const targets = new Map()
  let running = false
  let lastTime = 0

  function glide(box, { left, top } = {}) {
    const target = {}
    if (left != null && Math.abs(left - box.scrollLeft) > EPSILON) target.left = left
    if (top != null && Math.abs(top - box.scrollTop) > EPSILON) target.top = top

    // Already there on every requested axis — nothing to animate. Note this
    // does NOT clear an existing target: a caller asking for the current
    // position has expressed no opinion about an axis still in flight.
    if (target.left == null && target.top == null) return

    targets.set(box, { ...targets.get(box), ...target })
    start()
  }

  function cancel(box) {
    targets.delete(box)
  }

  /** Stop every glide where it stands — the user has taken the scroll. */
  function cancelAll() {
    targets.clear()
  }

  function isGliding(box) {
    return targets.has(box)
  }

  function start() {
    if (running) return
    running = true
    lastTime = now()
    requestAnimationFrame(tick)
  }

  /**
   * The target actually reachable this frame. A recorded target was valid when
   * it was measured, but the content can shrink under an in-flight glide (a
   * LiveView patch, or a live navigation swapping the page inside the same
   * scroll container) — the browser then clamps every write, `remaining` never
   * shrinks, and the loop would run forever fighting every other scroll
   * writer. Chasing the clamped value instead means the glide always arrives.
   * Re-read per tick, so bounds that change mid-flight are tracked.
   */
  function reachable(value, extent, port) {
    if (extent == null || port == null) return value
    return Math.min(Math.max(value, 0), Math.max(0, extent - port))
  }

  /**
   * Move one axis of `box` a frame closer to `value`. Returns whether the
   * axis has arrived.
   */
  function settle(box, axis, value, fraction) {
    const goal = reachable(value, box[axis.extent], box[axis.port])
    const remaining = goal - box[axis.offset]
    if (Math.abs(remaining) <= EPSILON) {
      box[axis.offset] = goal
      return true
    }

    const before = box[axis.offset]
    box[axis.offset] = before + remaining * fraction
    // The browser snaps offsets to device pixels; under a root zoom a step
    // below half a device pixel rounds back to where it was, and the gap
    // would never close. A write that moved nothing is the end: land on the
    // target (its nearest representable offset).
    if (box[axis.offset] !== before) return false
    box[axis.offset] = goal
    return true
  }

  function tick() {
    const time = now()
    const elapsed = time - lastTime
    lastTime = time

    // Fraction of the remaining gap to close this frame. Derived from elapsed
    // time so the trajectory is identical whether it ran in one long frame or
    // twelve short ones.
    const fraction = 1 - Math.exp(-elapsed / tau)

    for (const [box, target] of targets) {
      let arrived = true
      for (const axis of AXES) {
        if (target[axis.key] == null) continue
        if (!settle(box, axis, target[axis.key], fraction)) arrived = false
      }
      if (arrived) targets.delete(box)
    }

    if (targets.size > 0) {
      requestAnimationFrame(tick)
    } else {
      running = false
    }
  }

  return { glide, cancel, cancelAll, isGliding }
}
