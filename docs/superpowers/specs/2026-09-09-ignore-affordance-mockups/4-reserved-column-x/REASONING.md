# 4 · × in a reserved column

**Style.** The current icon, moved inside the card: a 26px round hover target in a column of its own between the content and the mast, vertically centred like the mast. Hover-revealed; the row's own hover tint carries it.

**Decisions.** Keeps the icon vocabulary (the library toolbar's filter clear, the health incident dismiss both use `hero-x-mark-mini`) while getting off the pennants' hoist. Because the column is reserved, the mast's varying width (one name, two names, a count) never collides with it.

**Requirements.** One click. Pointer-only, as now.

**Trade-offs.** Gains: familiar glyph, inside the card, no gutter. Costs: a permanent ~32px gap on every Recommendations row for a control that is invisible until hover; it is still inside the `<button>`, so the card must become `div[role=button]` here too; an × next to a mast of names risks reading as "remove this friend's pennant".
