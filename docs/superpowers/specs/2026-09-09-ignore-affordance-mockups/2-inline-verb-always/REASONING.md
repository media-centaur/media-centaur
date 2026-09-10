# 2 · Inline verb, always visible

**Style.** Direction 1 without the reveal: "Ignore" sits at marker weight (55%) on every row, brightens with the row on hover, underlines under the pointer.

**Decisions.** Discoverability over quiet. A person scanning the tab sees that rows can be dismissed without having to hover one first. Because it wears the markers' colour and size, it reads as part of the metadata line until you want it.

**Requirements.** Same as 1.

**Trade-offs.** Gains: nothing hidden. Costs: every row carries a verb on a tab whose rows are otherwise all facts, which pulls against "a row wears a marker, never the control" (UIDR-036 §4) harder than a hover reveal does; four rows show four Ignores.
