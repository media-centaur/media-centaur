# Title detail unification — research inventories (2026-09-14)

Raw research behind `../2026-09-14-title-detail-unification-design.md`,
read from the branch at `77714ea4`. Point-in-time; file:line references
go stale as the campaign lands. The spec carries every conclusion; these
hold the detail (per-event params, per-zone edges, per-test line numbers)
a phase needs while re-addressing tests or moving handlers.

| File | Covers |
|---|---|
| `sections.md` | every section of both modals: renderer, facts, source, local/remote, turn-on rule; the `DetailPanel`, `CinematicShell` and `Title.DetailModal` contracts; struct shapes; the four `Title.new!` mints; metadata/facet builders |
| `hosts.md` | every `handle_event`, `start_async`, `handle_info` and URL param of `EntityModal` and `TitleDetailHost`; the seven duplicated fact loads with their divergences; the assign inventory; what MC0011 enforces |
| `emitters.md` | every place that opens either modal and the identity it holds; page-root declarations; the bridges; card/row data shapes; the client side |
| `nav-overlays.md` | the `detail` and `title_detail` overlay config, every `data-nav-*` attribute in the templates, how absent zones are skipped, dismiss/BACK wiring, the JS tests, the hint bar |
| `tests-and-stories.md` | every test file that mounts or drives either modal, with URL forms, events and assertions; the pure-logic tests; every story variation; the factory and stub helpers; what ADR-027 covers |

Residue count (dev database, context functions): 15 series (all with a
TMDB id), 30 movies (all with one; 26 presentable), 14 collections (0 title
ids, 14 `tmdb_collection` ids; 3 presentable, one hoisted), 0 video objects.
