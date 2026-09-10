# 5 · Inline verb as a nav sub-item

**Style.** Direction 1's quiet "Ignore" at the end of the lead line, now with its input-system life drawn out: revealed on hover *and* while the row holds the cursor; the house 2px primary ring on the card when the row is focused, moving onto the word when RIGHT steps into it.

**Decisions.** The detail modal's episode rows already answer "a row with one secondary control": the row is the nav item, the control is a `data-nav-sub-item`, RIGHT enters, SELECT activates, LEFT leaves. Reusing that means one control serves mouse, keyboard and gamepad — no hidden CLEAR mapping, no second nav item per row. Showing the verb on row focus (not only hover) is what makes RIGHT's target visible before the press.

**Requirements.** One click with a pointer; RIGHT + SELECT from the pad. Undo toast unchanged. Nothing is added to the row silhouette; the mast is untouched.

**Trade-offs.** Gains: a single affordance with one behaviour everywhere; scales to a second sub-item by adding a word. Costs: the card becomes `div[role=button]` (a `<button>` may not contain a control); the Discovery rows zone changes from `grid` to a TREE so sub-items are walked — a nav change on a surface still marked early-preview; a cursor on the word means one more LEFT before UP/DOWN move rows.
