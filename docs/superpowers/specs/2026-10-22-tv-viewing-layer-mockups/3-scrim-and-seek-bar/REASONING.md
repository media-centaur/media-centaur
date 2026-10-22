# 3 — Scrim and seek bar

**Style.** The shape every TV player has taught viewers: a bottom
gradient scrim, the title and episode line above a full-width seek bar
with a round handle, chapter ticks on the bar, the clock at both ends.
Pausing drops a large glyph in the centre of the picture for a moment
and turns the fill amber. Prompts sit at the top right as a rounded
primary button with its key hint. The track menu is a centred glass
modal over a dimmed picture, two columns under one heading, the same
shape as the desktop's TAB menu.

**Decisions.** The seek bar is the one place the viewer scrubs, so it
gets the full width and a handle; chapter ticks make Skip Intro's
target visible. The scrim guarantees legibility over any picture
without a panel. Prompts at the top keep the bottom for the bar and
the subtitles. The modal is the desktop menu's shape so a user who
knows one knows the other.

**Requirements.** Bar, pills, subtitles and the two-column menu all
present; bitmap tracks disabled with their words; the PGS-only note in
the modal. The seek handle moves only with the 1 Hz tick, so nothing
animates continuously; the centre glyph fades once.

**Trade-offs.** Gains familiarity and the richest scrubbing feedback.
Costs the most screen while the bar shows (a 200 px scrim) and dims the
picture while the menu is open; a modal in the centre is the biggest
interruption of the three. Two columns mean LEFT/RIGHT switch columns
in the menu, the desktop's rule, which is one more thing the remote's
D-pad must do.
