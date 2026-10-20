# C — a modal over the grid

**Style.** The Friends grid stays as it is under the app's modal backdrop; the person opens in the modal panel the title detail uses, with A's anatomy inside it, scrolling within the panel.

**Decisions.**
- The grid never reflows: the card's press opens the panel, Escape or the backdrop closes it.
- The address stays a query param on the Friends tab, as `?person=` is today.
- The head carries the key and provenance; the card's foot repeats the key beside Remove friend, as A does.

**Requirements.** One surface per person: yes, but a transient one. The override card: yes. The reader's page: the same panel for You. Members: as A.

**Trade-offs.**
- Gains: the smallest change from today; the grid is always behind the person.
- Sacrifices: no route, so the rail's press and a link land on a tab with a param rather than a page. A poster press inside the panel would open the title modal over this one, and the app has no modal-over-modal today. On a TV a long scroll inside a panel is weaker than a page scroll.
