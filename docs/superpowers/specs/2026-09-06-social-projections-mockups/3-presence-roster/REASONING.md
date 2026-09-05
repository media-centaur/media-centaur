# 3 · Presence roster, expand in place

**Style.** A contact list. One line per friend inside one glass panel: avatar, name, a one-sentence presence line ("watched S02E05 of Sample Show"), relative time, chevron. Selecting a friend expands their shelves in place: an eight-up poster grid, Tracking, Recommended, then key + Remove at the bottom of the expansion. You is the first row and expands the same way.

**Decisions.** The presence line is the whole point of the closed state: a glance at the list says what everyone is into without any posters at all. Density scales to many friends. The expansion is where the per-friend page will come from: today it opens inline, later the same row navigates to `/discovery/friends/<key>`. Roster admin (key, remove) is hidden until you open the friend, so the list never reads as a settings table.

**Requirements.** Watched as a property of the friend: yes, literally the friend's status line. Inline first, page later: the expansion is the page in miniature. You as audit: first row, same shape.

**Trade-offs.** Gains: densest, cleanest at ten friends, best d-pad model (vertical list, one expansion at a time, no horizontal rail). Costs: posters are hidden by default so the tab is text until you open someone; the presence line has to carry two kinds when the latest act was not a watch (Alice's line shows the joined form); only one expansion open at a time is a rule we would have to keep.
