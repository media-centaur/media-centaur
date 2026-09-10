# 1 · Inline verb, hover-revealed

**Style.** The verb is a word, not an icon: "Ignore" in the same 12px muted text as the markers, at the end of the lead line, revealed when the row is hovered. Underline on hover of the word itself. Nothing is added to the card's silhouette.

**Decisions.** The modal's action strip already "speaks in words" (Recommend, Delete recommendation); the row borrows that voice rather than inventing an icon. Placing it after the markers keeps it in the content column, so the pennant mast — which owns the right edge — is never in play, and rows with two or three pennants need no special casing.

**Requirements.** One click from the list. Pointer-only by design; the ladder in the modal is the keyboard and gamepad path. Undo toast unchanged.

**Trade-offs.** Gains: house idiom, no geometry conflicts, scales to a second row verb by adding a word. Costs: the card must become `div[role=button]` so a click target can live inside it (a `<button>` may not contain interactive content); hover-reveal is invisible until you know it is there.
