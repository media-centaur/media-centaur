# Feed 2 · Message cards, note first

**Style.** The recommendation as a message. Actor line on top (avatar, name, sentiment pill, time), the note at reading size as the body, and the title as an attached inset card below it with thumb, name, type/year and the markers. The Bluesky post shape, since this is the one kind that actually is a message.

**Decisions.** The note is promoted to the content because a recommendation without a reason is just a bookmark; the reason is what a friend gave you. When there is no note the attachment shows the overview so the card is never empty. "also from Cleo" in the attachment's meta line replaces the stacked pennants. The whole card opens the modal.

**Trade-offs.** Gains: the note is readable, the friend is the first thing you see, the card carries a long note without clamping. Costs: a new component instead of the shared title row, about twice the vertical space per item, and a feed of note-less recommendations is a column of attachments under empty headers. It also makes the feed look different from the watchlist next door, which shares the row today.
