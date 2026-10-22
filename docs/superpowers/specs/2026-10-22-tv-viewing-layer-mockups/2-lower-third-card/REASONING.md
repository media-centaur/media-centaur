# 2 — Lower-third card

**Style.** The bar is a glass card (`.glass-surface`) centred on the
lower third, carrying the title the way the app's title surfaces do:
a small poster, the name, the episode line, a 4 px progress bar and the
clock, with the remaining time as a quieter second line. Paused adds a
warning-coloured pause glyph above the clock. The prompt pill attaches
to the card's right end while the card is up and sits alone at the
bottom-right corner when it is hidden. The track menu is a right-hand
drawer with the sidebar's heavy blur, Audio over Subtitles.

**Decisions.** The card gives the viewer the title's identity (poster
and name) at a glance, which matters when a chain has auto-advanced
while nobody watched. The drawer is the app's existing idiom for a
side panel and leaves the picture's centre clear; one column at a time
means UP/DOWN alone walks the whole menu, with no column switching to
learn. The pill follows the card so the two never fight for the
corner.

**Requirements.** Bar, pills, subtitles and the two-column menu all
present; bitmap tracks disabled with their words; the PGS-only note
under Subtitles. Nothing animates continuously; the card's appearance
is a short fade.

**Trade-offs.** Gains identity and legibility: a card reads well from a
couch and matches the rest of the app. Costs the most coverage of the
picture while it shows (a 720 px glass card), and its blur is the one
rendering cost the measurement did not include (a `backdrop-filter`
over a composited video layer may force GPU composition on the Mali;
to measure before choosing). The drawer covers a third of the frame
while open.
