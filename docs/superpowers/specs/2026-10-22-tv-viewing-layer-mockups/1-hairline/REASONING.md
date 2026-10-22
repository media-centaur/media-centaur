# 1 — Hairline

**Style.** The page draws as little as it can over the video: the app's
progress hairline (UIDR-024) along the screen's bottom edge, one line
of text above it with the title, the episode and the clock, no panel
and no scrim. Text sits on the image with the `.text-on-image` shadow.
The one pill (Skip Intro, Next Episode) is the primary button in pill
shape at the bottom right, carrying its key hint. The track menu is
the only glass surface: a panel rising from the hairline at the
bottom left, two columns, the kit's menu-list idiom.

**Decisions.** The hairline is already the app's "how far" language on
every title surface, so the TV reads the same mark it knows. The bar
hides itself and the video is unobstructed most of the time; paused
turns the hairline amber (the kit's playing/paused colours) and holds
the line on screen. The menu sits bottom-left so it never covers the
subtitle line's usual place and the pill's corner. Column headers use
the section-header treatment.

**Requirements.** Bar: the line and the hairline. Pills: one pill,
bottom right, the modal's one nav item. Subtitles: centred text at
28 px over the vignette. Track menu: two columns, active marked, None
first, bitmap tracks disabled with "Not on this TV" and the PGS-only
note under the columns. Nothing animates; the bar's appearance is a
short opacity fade.

**Trade-offs.** Gains the quietest screen and the least drawing (the
measured cost is nil at 1 Hz). Loses the at-a-glance seek bar a lean-
back viewer may expect to see while scrubbing; the hairline is thin
from the couch. The clock is small for a 42" panel at a distance; a
larger type scale is one variable to tune.
