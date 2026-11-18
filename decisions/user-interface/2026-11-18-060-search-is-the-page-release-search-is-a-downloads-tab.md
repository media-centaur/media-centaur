---
status: accepted
date: 2026-11-18
---
# Search is the page; release search is a Downloads tab

Campaign `search-page.md` (M1). Amends UIDR-057 (the choose stage's name), UIDR-014 (where each search lives), UIDR-015 (the Downloads tabs) and UIDR-010 (the sidebar's Watch group), each with a dated amendment of its own.

## Context and Problem Statement

Two pages opened with the same wide, centred search field in the same position. Discovery's was media search, the TMDB title search. Downloads' was release search, the Prowlarr search for release names with brace expansion. The page called Downloads therefore presented the low-level file search as its main action, nothing on it said where a title is found, and the page that does find titles was labelled "Discovery" with a sparkles icon.

## Decision Outcome

1. **The choose stage's page is Search** at `/search`, sidebar label "Search", the magnifying-glass icon. Its content is what Discovery's was: media search over the hero and the shelves, a query owning the page. `/discovery` is removed with no redirect.
2. **Release search is the third tab of Downloads**, "Release search" (`?zone=release-search`), after Activity and History. The tab holds the field, the syntax line, the note and the results. Activity and History carry no search field, and a query hides nothing: the rule that a search owned the page and receded the tabs is removed.
3. **The note.** Under the syntax line: "Release search is a direct file search. It's recommended to use the media search in most cases.", "media search" linking to `/search`. An empty Activity tab also points to Search. Both are omitted while the Search page is off.
4. **Downloads opens on its download list.** The sidebar remembers each page's last URL; the Release search tab is excluded from it (`zone` is a transient param while that tab shows), so the entry returns to Activity or History.
5. **The two fields do not look alike.** Media search keeps the magnifying glass and "What do you want to watch?"; release search keeps the command-line glyph and the monospace field.

Rejected: a button in the tab row that expands the field in place (a new open/closed state with its own focus rules, and results still pushing the download list down); a link opening release search in a modal (UIDR-014 rejected a modal for search, and a result list with bulk grab is cramped in one).

### Consequences

* Good, because the app's first screens show one search field, on the page named for it.
* Good, because Downloads' first screen is the download list, and release results get a whole tab.
* Good, because the keyboard and remote path is the existing tab row: tabs, then the field, then the results.
* Bad, because a release search is one more action away, and a started download shows on Activity, one tab from the results.
* Bad, because the feature registry entry keeps the id `:discovery` (displayed as "Search") until the flags are reshaped in the campaign's next milestone.
* Bad, because links and bookmarks to `/discovery` broke on purpose.
