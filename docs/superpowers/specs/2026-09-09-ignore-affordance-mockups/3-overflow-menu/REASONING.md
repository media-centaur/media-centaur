# 3 · Overflow menu

**Style.** A ⋯ control, hover-revealed, sitting between the content column and the mast; it opens the `.glass-menu` idiom the title modal already uses for the Download scope. The menu holds "Ignore".

**Decisions.** Treats the row as a thing that may grow verbs. The kebab is a single stable affordance whatever the menu comes to hold, and a menu is a place for a consequence-bearing act to be read before it is clicked.

**Requirements.** Two clicks, not one — the menu is the second. The kebab itself could be a nav item, which would give keyboard and gamepad a row-level path.

**Trade-offs.** Gains: extensible, and the act is named in words. Costs: two clicks for the one verb we have; a menu with a single item reads as ceremony; the card is `overflow:hidden` for the mast bleed, so the menu must be a sibling of the card, not a child — the same structural cost as the gutter ×. UIDR-036 argues against row verbs multiplying, which undercuts the extensibility case.
