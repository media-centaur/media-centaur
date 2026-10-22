---
status: accepted
date: 2026-10-22
---
# A remote player's OSD is the host's page

Pairs with ADR-080 (one session type over two transports) and its 2026-10-22 amendment (per-file options, one viewing, one command door). Campaign: `campaigns/remote-players.md`, M5. Mockups: `docs/superpowers/specs/2026-10-22-tv-viewing-layer-mockups/` (direction 3, scrim and seek bar). The host–player contract: `docs/superpowers/specs/2026-10-22-remote-players-protocol-design.md`.

## Context and Problem Statement

On the desktop, mpv draws the viewing's on-screen display itself: its own seek and pause feedback, and the bundled Lua package's Skip Intro pill, Next Episode pill and countdown, and the TAB track menu (ADR-072). On the TV the same mpv, embedded as libmpv in the TV app, outputs through `vo=mediacodec_embed`: the decoder writes straight to the panel's surface, which is the only path that gives native 3840×2160 HDR10 at zero GPU cost on the Sony (the GPU path tone-maps to 1080p SDR and cannot present HDR on Android's EGL). On that path mpv draws nothing: no OSD, no scripts' pills, no track menu, no subtitles. The owner's calls: dropping quality for an overlay is not acceptable, so there is no GPU-path fallback; bitmap (PGS) subtitles are unsupported on the TV; full fidelity is the target.

The TV app shows the host's UI in a transparent WebView over the player's surface, and the host already knows everything a viewing shows: position, pause, chapters, tracks, the subtitle text, the prompt. The question was where the OSD lives.

## Decision Outcome

**The host's page is the TV's OSD.** The page stays over the video for the whole viewing, transparent, and draws what the desktop's mpv draws; every key goes to the page, which sends playback commands to the host, which sends them down the player channel. The player draws nothing and holds no key bindings and no scripts.

1. **One layer.** `Components.ViewingLayer`, rendered by `Layouts.app` on every page from the `viewing_layer` assign that `Live.ViewingAware` keeps from the player's viewing stream. While a viewing is on, `html` and `body` are transparent and the shell is hidden under it; the layer is the only thing on the page. Its parts, direction 3 of the mockup round: a scrim and lower bar with the title, the episode line, a seek bar with chapter ticks and a handle, and the clocks at both ends; the **prompt pill** at the top right — Skip Intro on an intro chapter, Next Episode during credits with a successor queued, the countdown in the last seconds — the layer's one nav item, with its key hint; the subtitle line above the bar, lifted while the bar shows; the Paused state as a label in the bar, a centre glyph and an amber fill. The bar shows on any key and hides after four seconds.
2. **The 1 Hz rule.** Nothing on the layer animates continuously. The seek handle and the clocks move with the session's once-a-second position tick; the only transitions are opacity. Measured on the Sony: a 60 fps page animation over native 4K video janks the video, a 1 Hz bar costs nothing. Every TV check prints the player's drop counters so a layer change that costs frames is seen.
3. **Keys to the page, always.** The remote's keys reach the page as ordinary key events (Back and Menu forwarded by the shell as Escape and ContextMenu, targeted at the focused element). While the layer is present the page's behaviour is wrapped by `viewing_behavior.js`: LEFT and RIGHT seek ±10 s, UP and DOWN ±60 s, SELECT activates the prompt while one shows and toggles pause otherwise, BACK closes the menu if open and otherwise stops the viewing, and four actions of the viewing's own — play/pause, seek forward and back by 30 s, the track menu — are Controls bindings in the category *During playback on a TV* (defaults: the remote's media keys and the Menu key the shell forwards as ContextMenu), rebindable on the TV's own Settings page to whatever key its remote has. There is no key map behind the user's: every key the app answers to is a catalog binding. Outside a viewing a Play/Pause key is Play. Each becomes a `Playback.Command` the session renders to IPC; the page never speaks to the player. The path page → host → channel → mpv measures ≈10 ms, below the threshold of felt latency. Nothing is bound on the player: no `input.conf`, no `keypress`.
4. **The track menu is the page's.** A centred glass modal of two `GlassMenu.menu_list` columns, Audio and Subtitles, opening on Subtitles (the desktop menu's rule), the active entries marked; a pick applies at once and the menu stays open; BACK closes it. It is a second overlay over the OSD's, nested in it (`data-detail-nested`), so BACK peels it alone. The desktop's Sound column (night mode, dialogue boost, the limiter) is not on the TV yet: its per-folder memory and the limiter rule live in Lua on the desktop player and need a host-side owner first (M6 of the campaign).
5. **Text subtitles only.** The page draws the current subtitle text from mpv's `sub-text`; a bitmap track (PGS, DVD) is listed disabled with "Not on this TV", a file with nothing else says so in the menu, and the session never enforces a bitmap track on a transport that draws no subtitles (`Transport.draws_subtitles?/1`).

### Consequences

* Good, because the TV shows the video at the panel's native resolution and HDR with nothing composited by mpv, and still has every surface the desktop has.
* Good, because one host-side `Playback.Viewing` and one `Playback.Command` door serve every reader; the Lua package and the page agree on the chapter words by test (`chapter_words_lua_sync_test.exs`).
* Good, because a page that is always up needs no mode switch in the shell: the WebView stays visible, keys always go one way.
* Bad, because bitmap subtitles cannot be shown on the TV, and the Sound column waits on a host-side owner.
* Bad, because feedback for a key is a LAN round trip; measured as imperceptible, but a congested network would show it.

## Anti-patterns

* **A second OSD on the player** — scripts, an `input.conf`, `keypress` commands, or a GPU render path "just for the pills".
* **Continuous animation on the layer** — a smooth seek handle, a progress tween, a pulsing pill.
* **Keys split between the page and the player** — a routing rule that depends on whether the page "is up".
* **Position or pause state kept on the page** — the layer is a projection of the viewing stream and holds no state of its own beyond the bar's timer and the menu's open flag.
* **A subtitle renderer on the player** — bitmap subtitles are unsupported, and said to be, rather than drawn by a second path.
