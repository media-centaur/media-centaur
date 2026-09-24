# Firefox parity and controller layout

**Status:** in progress — started 2026-09-24
**Trigger:** a user report that gamepad control works in Chromium but not Firefox.

## Glossary

Terms defined before first use. "Mapping" already has two meanings in this area,
so it is split.

| Term | Meaning |
|---|---|
| **`gamepad.mapping`** | The browser's own string on a `Gamepad` snapshot — `"standard"` or `""`. Platform-supplied, read-only. Never our value. |
| **Controller layout** | Our derived value type: which button index carries which action, where the directional input lives (stick axes vs. hat axes), and which label family the hint bar shows. Derived once per connect from `(id, mapping, buttons.length, axes.length)`. |
| **Hat axes** | A pair of axes carrying D-pad state as discrete −1 / 0 / +1 values, instead of buttons 12–15. How Linux evdev reports a D-pad when the browser does not remap to standard. |
| **Input gate** | Existing term, kept. The policy deciding whether this surface may consume gamepad input at all. |
| **Declared entitlement** | An automation surface's explicit statement that it is the intended driver of gamepad input. Replaces sniffing `navigator.webdriver` as a proxy for "nobody is watching". |

## Core idea

A gamepad source turns one physical device's snapshot into semantic actions, for
whichever surface is entitled to that device. Two nouns — what the snapshot
*means* (controller layout), and who *gets* it (input gate). Neither existed as a
thing in the code, which is why the Firefox bug and the inert gamepad E2E project
are the same bug.

## Diff against the code, and dispositions

| # | Incoherence | Disposition |
|---|---|---|
| 1 | Device knowledge split across three unrelated constants — `DEFAULT_BUTTON_MAP`, `_pollAxes`'s hardcoded `axes[0]`/`axes[1]`, and `detectControllerType`'s id sniffing. `gamepad.mapping` never read | Fix now — promote to controller layout |
| 2 | The input gate sniffs `navigator.webdriver` as a proxy for "unattended agent browser". Measured `true` under Playwright Chromium, so the whole gamepad E2E project is inert | Fix now — declared entitlement |
| 3 | Three places encode one device shape: the E2E mock, and `gamepad.test.js` (844 lines, `mapping` appears zero times, every fixture 17 buttons / 4 axes / Chrome-format id) | Fix now — unit owns layout variants, Playwright owns integration |
| 4 | The E2E suite targets `127.0.0.1:2160`, the dev daily driver's live database. Un-runnable in CI, un-gateable — which is why it rotted | Fix now — `webServer` booting the showcase override |
| 5 | `status.spec.js` asserts `[data-nav-zone='sections']`, gone from /status. All 5 fail in the keyboard project too | Fix now, falls out of 4 |
| 6 | Nothing runs the E2E suite: `test.all` is `mix test` + `bun test assets/js/`; no CI workflow mentions playwright | Fix now — otherwise everything above rots again |
| 7 | `.orientation-backing-sheet` uses `animation-timeline` unguarded. Firefox drops the declaration, the animation falls to duration `0s` with `fill-mode: both`, and the sheet snaps permanently to its fully-risen position | Fix now — `@supports` guard, as its `.row-scroll` sibling already has |
| 8 | Real-device verification of Firefox's own gamepad backend via `/dev/uinput` | **Scheduled.** Convergence point: a real capture disagrees with the fixtures, or a Gecko row in the layout table needs proving |

## Decisions

- **Firefox is a supported browser.** `First-Run.md:32` already publishes "Open
  the listed URL in any browser", the product is self-hosted Linux where Firefox
  is the distro default, and playback is handed to mpv so there is no codec
  surface in the browser. The measured gap is two defects (#1 and #7), not a
  porting effort.
- **Equal support, not equal verification.** Mirroring the whole E2E suite across
  two browsers doubles its cost forever to catch a rare class of bug. Firefox gets
  a smoke pass over the pages using the risky features, not a duplicated matrix.
- **Layout fixtures are reconstructions until proven.** The Gecko rows are derived
  from Mozilla bug reports, not from a capture. That is the named risk behind
  item 8.

## Measured facts

- `navigator.webdriver === true` under a default `chromium.launch()` in
  Playwright — so `gamepadInputAllowed` returns false for every E2E run.
- `~/.cache/ms-playwright/` holds chromium only; no Firefox binary installed.
- `/dev/uinput` exists, module loaded, owner holds an ACL grant.
- Firefox still ships scroll-driven animations behind
  `layout.css.scroll-driven-animations.enabled` in stable as of mid-2026.
- Frontend's effective Firefox floor is ~128 (`@property`), everything else older.

## Order of work

Each step leaves a working product. Ordered so every step's regression test can
be written before its code — which puts the `@supports` guard *after* the
browser that proves it, not first as originally sketched.

1. ✅ **Controller layout** (#1, #3) — pure, unit-testable red→green today.
2. ✅ **Declared entitlement** in the input gate (#2) — same.
3. E2E owned server + drifted selectors (#4, #5) — makes the harness real.
4. Firefox smoke project, carrying the `@supports` guard (#7) with the test
   that proves it.
5. Gate that runs the suite (#6).
6. Wiki: `Keyboard-and-Gamepad.md`.

## What landed

**Controller layout** (`assets/js/input/core/controller_layout.js`). The design
that fell out of the code is *normalization*, not a per-layout action map:
`Settings.Controls.Catalog` already hardcodes standard-layout button indices and
calls itself the single source of truth, and user rebindings are stored against
those indices. So the layout's job is to translate a raw snapshot into standard
indices, and every layer above — catalog, saved overrides, `DEFAULT_BUTTON_MAP`,
the wiki cheat-sheet — keeps speaking one vocabulary. Two consequences worth
noting:

- `DEFAULT_BUTTON_MAP` and the catalog needed **no change at all**. The fix
  removed a vocabulary rather than adding one.
- A binding captured in one browser now works in another. That portability was
  not a goal; it is what the coherent model gives for free.

A hat pair is normalized into D-pad *button* presses rather than getting its own
axis path, so it travels the same binding and key-repeat code as a real D-pad.

**Declared entitlement** (`assets/js/input/input_gate.js`). `webdriver` was a
proxy for "nobody is watching", which is false for an E2E run. Renamed to
`automation` (the probe is `navigator.webdriver`; the concept is automation),
and an automation context may now declare itself the intended driver via
`window.__inputAutomationDrivesGamepad`. Absent declaration it is still denied,
so mc-debug-browser is unchanged, and a declaration never substitutes for focus
or visibility.
