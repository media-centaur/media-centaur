# Settings readout kit — design

Date: 2026-09-13. Follows the settings-coherence campaign (shipped v0.126.5,
which settled section ids, service names and the sidebar grouping) and the
download-button default-action spec (`2026-09-12-download-button-default-action-design.md`),
whose decision 11 (a native select on a "Download button" card) this spec
replaces. Enacted by [UIDR-041](../../../decisions/user-interface/2026-09-13-041-settings-cards-are-readouts-with-actions.md).
Approved against the HTML mockup shown to the owner on 2026-09-13 (three
artboards: Acquisition configured, Acquisition fresh, Social).

## Glossary

Working terms, defined before use. Each names the control or module the
app already has where one exists.

- **Section** (existing) — one entry in the Settings page's left nav; thirteen today (`SettingsLive`'s `@sections`). Reached by `?section=<id>`.
- **Section intro** — the section's title and one-line description at the top of its content column. Rendered by the Settings shell from the section list, not by the section module.
- **Settings kit** — the shared function components every section composes from. Today `MediaCentaurWeb.SettingsLive.Components` (no stories, outside the components tree); after this spec `MediaCentaurWeb.Components.Settings`, under `lib/media_centaur_web/components/settings/`, one story per component.
- **Card** — one glass surface inside a section: an uppercase title (`settings_card_header`'s treatment), an optional one-line description, an optional right-aligned action, and a body of rows. `settings_card/1`.
- **Row** — one setting inside a card: label and description on the left, its control on the right. Four kinds:
  - **Toggle row** (existing `settings_row/1`) — a boolean, saved on click.
  - **Stepper row** (existing `settings_stepper/1`) — a bounded number over a fixed ladder of values, −/value/+/Reset, saved on click.
  - **Choice row** — a pick-one-of-N enum (N ≤ 4) as the house segmented pill (`.tabs.tabs-boxed.segmented-control`, `aria-pressed`), saved on click. `settings_choice/1`, restored from git history (removed in `d18694cf`) and re-skinned onto the pill.
  - **Connection row** — the readout for one external endpoint (below). `connection_row/1`.
- **Text row** — a free-text setting (a path, a name) shown as its input, committed on Enter or blur. No Save button. Used for the few single-value text settings that survive (data directory, mpv path, IPC socket directory).
- **List setting** — a setting whose value is a list of strings, shown as one row per entry with a Remove, plus an inline input and Add beneath. The idiom Excluded directories and Relays already use; Media Import's folder-name lists adopt it.
- **Select row** — an enum with more than four options as a native `<select>` on the right of the row, saved on change. The Language section's policy selects.
- **Connection** — an external endpoint the app talks to: TMDB, Prowlarr, the torrent client, the usenet client, and each relay. The first four are **integrations** in `MediaCentaur.Capabilities`' sense (they have a persisted connection test); a relay is not.
- **Readiness** (existing) — `Capabilities`' predicate: configured and the most recently persisted connection test passed.
- **Readout state** — a connection row showing what is configured (name, address, credential presence) and its state, with no input fields on screen.
- **Edit state** — the same row expanded beneath its readout into the form for that connection. At most one row is in its edit state on the page; the LiveView holds it as `editing` (`nil | :tmdb | :prowlarr | :torrent | :usenet`).
- **Pending detection** — values Detect from Prowlarr found for a slot that have not been saved. Shown on the slot's row; never persisted on its own.
- **Save on the act** — a control persists the moment it changes. The page's default. A Save button exists only inside an edit form.
- **Disclosure** — a `<details>` element hiding rare content (the secret key, service details) behind a caret and a label. `settings_disclosure/1`, replacing the `.release-notes-disclosure` class both current sites borrow.
- **Gated card** — a card whose controls only mean something once Prowlarr is ready (Download button, Auto-acquisition). It stays on the page and states why its controls are absent.

## Problem

Settings has two visual idioms on one page. Form cards (an `h2` title, Save
at the top right, uppercase field labels, monospace inputs, a footer with a
test) are used by Prowlarr, both download clients, TMDB, Media Import,
Playback and Language. Readout cards (an uppercase title, one explanatory
line, rows that save on the act, disclosures for rare actions) are used by
Social, Library, Preferences and Services. System is a third idiom and
Controls a fourth.

Acquisition is the worst case: five forms and five Save buttons for values
that are entered once. What matters afterwards (which client, where,
connected or not, since when) is buried under blank password inputs. The
integration form skeleton is written four times; the field markup about
twenty; readiness is drawn four ways; the kit has no stories because it
lives outside the components tree.

Control by control, Acquisition also carries a select with one real option
per slot, a Detect action on the torrent card that fills both slots, three
controls (minimum quality, maximum quality, 4K patience) describing one
policy with one invalid combination, four number inputs where the house has
a stepper, and two cards that vanish when Prowlarr is not ready without
saying why.

## Decisions

### Page structure

1. **The shell renders the section intro.** Each `@sections` entry gains a `description`; the shell renders `h2` + one line above the section's cards. Section modules render cards only. No section module renders an `h2`. Danger Zone's intro is the same shape; its card keeps its error border and red glyph.
2. **Every card is `settings_card/1`**: `glass-surface rounded-xl p-5`, an uppercase `h3` title, optional `description` (`text-xs text-base-content/55 max-w-[60ch]`), optional `:action` slot right-aligned on the title line, body slot. Social's single card with dividers becomes three cards (Your identity, Relays, Sharing).
3. **Rows are the only way a setting appears in a card**: toggle, stepper, choice, connection, text, select, or a list setting. Labels are sentence case, `font-medium`; descriptions `text-xs text-base-content/55`. The uppercase field label goes.
4. **Save on the act everywhere a control is atomic.** Toggles, steppers, choices, selects and text rows persist on change. A Save button exists only inside a connection row's edit form. No card carries a Save in its header.
5. **The kit moves to `lib/media_centaur_web/components/settings/`** as `MediaCentaurWeb.Components.Settings` with one story each under `storybook/settings/`: `settings_card`, `connection_row`, `settings_row`, `settings_stepper`, `settings_choice`, `settings_text_row`, `settings_select_row`, `settings_field` (the label/control/help unit used inside edit forms), `settings_disclosure`, `path_status`. `MediaCentaurWeb.SettingsLive.Components` is retired. `connection_status/1` and `status_dot/1` are absorbed by the connection row.

### Connection row

6. **Anatomy.** Left to right: a state dot; an identity block (name in `text-sm font-medium`, an optional kind tag such as *torrent* in `text-xs text-base-content/55`, and a detail line in `text-xs`); the state text; the actions. The detail line carries the address as a link to the endpoint's own web UI (external-link glyph after it; this replaces the Open buttons) followed by credential presence in words ("API key set", "admin · password set"). The state text is the state word with the test's age in `text-base-content/40`.
7. **States and what each shows.**

   | State | Dot | State text | Actions |
   |---|---|---|---|
   | Not configured | `bg-base-content/20` | Not configured | Set up |
   | Configured, not tested | `bg-base-content/30` | Not tested | Test · Edit |
   | Connected | `bg-success` | Connected · tested N ago | Test · Edit |
   | Unreachable | `bg-error` | the integration's failure word (Unreachable; Unreachable or auth failed; Unreachable or bad API key) · tested N ago | Test · Edit |
   | Pending detection | as underlying | Detected from Prowlarr, not saved | Review · Dismiss |
   | Editing | as underlying | the detail line reads "Editing. Saving clears the last test; test again afterwards." | none on the readout line; the form's footer carries them |

   The state vocabulary is the one `Capabilities` already persists. The row draws it; nothing else on Settings draws readiness.
8. **Test in the readout re-tests the saved values** and updates the state and age in place. It never opens the form and never changes stored values.
9. **Edit opens the form beneath the readout**, indented under a left hairline the way Social's secret-key disclosure body is. Fields per connection:

   | Connection | Fields |
   |---|---|
   | TMDB | API key (password; help links to themoviedb.org/settings/api) |
   | Prowlarr | Address; API key (password; help: Prowlarr → Settings → General → Security → API Key) |
   | Torrent client | Client (select; qBittorrent); Address (help: must be reachable from this machine; a detected address is often a hostname that only resolves inside Docker); Username; Password |
   | Usenet client | Client (select; SABnzbd); Address (same help); API key (help: SABnzbd → Config → General → API Key) |

   A password field's placeholder reads "Leave blank to keep the current key" (or "current password") when one is stored and names what to enter otherwise. The select's "Not configured" option goes; clearing a slot is the Remove client action. The footer is Cancel (ghost), Save and test (soft), Save (soft primary); a client slot's footer also carries Remove client (ghost, error text) at the left. Save persists through `Capabilities.save_integration/2` (which clears the stored test when anything changed) and returns the row to its readout. Save and test keeps today's save-then-test semantics, so a failed test leaves the typed values in the form and the form open. Cancel discards and returns to the readout. Escape while editing is Cancel. Opening the form focuses its first field.
10. **One edit at a time.** Opening Edit or Set up on another row closes the open one (discarding its unsaved typing). Navigating to another section closes it.
11. **Set up is Edit on an unconfigured row.** Same form, empty, with each field's placeholder naming what to enter. The row also carries a one-line description of what the connection does while nothing is configured (Prowlarr: "Searches your indexers and forwards each grab to a download client."; torrent: "qBittorrent. Also powers the download progress on Incoming."; usenet: "SABnzbd. Repairs and unpacks; the finished file imports like any other download."; TMDB: "Metadata and artwork for everything in the library.").
12. **Remove client** clears the slot's type, address and credentials, clears its stored test, and returns the row to Not configured. It is inside the edit form, at the footer's left, and needs no second confirmation: the credentials are re-enterable and nothing downstream is deleted.
13. **Detect from Prowlarr lives on the Download clients card's action slot**, enabled once Prowlarr is configured. Its result puts each found client on its slot's row as a pending detection. Review opens the edit form pre-filled with the detected type, address and username; Dismiss drops the pending values. A save from a pre-filled form is an ordinary save. Pending detections are page state and vanish on navigation, as today.
14. **Every integration is a connection row.** The TMDB section is its intro plus one card ("TMDB") holding the TMDB row. Acquisition's Search card holds Prowlarr; its Download clients card holds the torrent and usenet rows in that order.
15. **A relay is a connection row without an edit state.** Name is the URL in monospace; no kind tag; the detail line carries the last error when there is one; the state text is `RelayStatusRow.state_label/1`; the dot is success for Synced and Connected, neutral for Connecting, error for Not connected and Rejected; the one action is Remove. Add relay stays the list setting's inline input and Add beneath the rows. The Social section's header dot goes with the section-level `h2`.

### Acquisition section

16. **Five cards in order:** Search, Download clients, Download button, Auto-acquisition, Release tracking. The section intro reads "Where releases are searched for and downloaded, and what happens when a tracked title's release appears."
17. **Gated cards stay on the page.** While Prowlarr is not ready, Download button and Auto-acquisition render their title and the one line "Available once Prowlarr's connection test passes." and no controls. The server-side gate in the save handlers stays.
18. **Download button is one choice row**: label "Default action on a title you don't own yet", description "The other choice stays in the button's menu.", options in the words `Title.Logic.planning_mode_label/1` already gives the button's menu ("Manually select release", "Auto-select best release"). Replaces decision 11 of the download-button spec.
19. **Auto-acquisition is five rows**, card description "Applied when a tracked title's release appears. A title's own tracking controls take precedence."

   | Row | Kind | Options or ladder | Setting |
   |---|---|---|---|
   | When a release appears | choice | Grab it · Ask first · Notify only | `auto_grab.default_mode` (`all_releases` · `ask` · `off`) |
   | Highest resolution | choice | 4K · 1080p | `auto_grab.default_max_quality` |
   | Within a resolution | choice | Best fidelity · Save space | `auto_grab.size_preference` |
   | Season packs | stepper | 5 % steps, 5–100, default 75 | `auto_grab.pack_min_fit` |
   | Search attempts | stepper | 1–50, default 12 | `auto_grab.max_attempts` |

   Descriptions: "Ask first parks the plan on Incoming until you approve it." · "The best available is taken right away. Nothing found at this resolution falls back to 1080p; anything lower needs the title's own acceptance." · "Best fidelity takes a remux first. Save space takes compact encodes first, and still takes a remux when nothing smaller exists." · "Take a pack only when you want at least this share of its episodes. Below it, episodes are grabbed one by one and the pack is offered." · "Failed search cycles before a release is given up on."
20. **The quality policy loses its floor and its patience window** (owner decision, 2026-09-13). `auto_grab.default_min_quality` and `auto_grab.4k_patience_hours` are removed from Settings, `AutoGrabSettings` and every consumer: `WantSchedule` keeps its age-band schedule and drops `floor_elevated?/3` and patience-expiry due-ness; `DropPlanner` drops `floor_for/5`; `PlanUnit`, `Plans`, `Board` and `RunPlan` lose the "patience elevation" path. The automatic floor is the constant `hd_1080p`. Per-title params (`DownloadParams`) keep `min_quality` for the lower-quality acceptance (`"any"`, ADR-063 §2) and lose `max_quality` and `quality_4k_patience_hours`, which nothing in the UI writes; a one-shot data migration strips the two keys from stored `title_download_params` rows and deletes rows left empty. Existing `auto_grab.default_min_quality` and `auto_grab.4k_patience_hours` settings rows are deleted by the same migration. Accepted consequence, stated to the owner: a tracked episode grabbed at 1080p on air night stays at 1080p when its 4K lands later, since nothing upgrades today. ADR-061's invariant (gates bound, ladders order) stands; the floor gate is now fixed rather than configurable.
21. **Release tracking is one stepper row**, label "Check TMDB for new release dates", value shown as "every Nh", ladder 1 · 2 · 3 · 4 · 6 · 8 · 12 · 24 hours, default 6, description "A change applies after the current cycle finishes." Its own card, because it is not gated on Prowlarr.

### The other sections

Mechanical adoption of decisions 1–5. The plan confirms control counts per file; the rules are:

| Section | What changes |
|---|---|
| System | Cards (Service, Health Check, Guide, Updates) become `settings_card`; the app identity block stays as it is. The Updates card's interval input becomes a stepper row; its toggles are already rows. The grouped status lists keep their list treatment. |
| Services, Preferences | Card `h2` goes (the intro carries it); body unchanged. |
| Controls | The `text-2xl` heading goes; each binding group becomes a card. Binding controls unchanged. |
| Library | Already on the kit. Data directory becomes a text row (commit on Enter or blur) and loses its Save. Cleanup's two day counts become stepper rows (1–90 days, step 1 below 14, step 7 above) and lose their Save. |
| TMDB | One card, one connection row (decision 14). |
| Social | Three cards, relays as connection rows (decisions 2, 15). |
| Media Import | Extras folder names and Ignored folder names become list settings. Auto-approve threshold becomes a stepper row (0.50–1.00 in 0.05 steps). Artwork resolution becomes a choice row (4K · 1080p). No Save. |
| Playback | mpv path and IPC socket directory become text rows carrying their `path_status` glyph beside the label; timeout becomes a stepper row (100–5000 ms, step 100). No Save. |
| Language | "Languages you understand" is already a list setting. "Audio & subtitles" becomes select rows (each select saves on change); the Save goes. |
| Maintenance | Becomes a card of action rows (label, description, the button on the right); the `h2` goes. |
| Danger Zone | One card with the error border; the action row as today; the `h2` goes. |

### Copy

Row labels and descriptions in this spec are final unless the writing-copy
pass at implementation finds a gate failure (obvious, or resting on an
unintroduced term). Flash messages after a save name the setting
("Prowlarr saved", "Auto-acquisition saved"); a save-on-the-act control
that succeeds shows no flash, since the control is the state.

### Wiki, guide, tour

The Settings-Reference page's Acquisition, TMDB and Social entries, and
Release-Tracking's quality paragraph, are rewritten to the rows above in
the same commit as the code. The screenshot tour's Acquisition locators
(`#settings-download-client`, `#settings-prowlarr`) move to the new row ids;
no screenshots are regenerated.

## Acceptance criteria

- Acquisition with every integration configured shows no `<input>` or `<select>` until Edit is pressed.
- Each connection row shows its name, its address as a link, its credential presence in words, its state word and the test's age.
- Test on a readout row re-runs the connection test and updates the state text; stored values are unchanged.
- Edit opens exactly one form; a second Edit closes the first. Cancel and Escape return the row to its readout with stored values unchanged.
- Save persists and clears the stored test; the row shows Not tested. Save and test persists, then tests; a failed test keeps the typed values in the still-open form.
- An unconfigured row shows Not configured, its one-line description and Set up; Set up opens the same form.
- Detect from Prowlarr puts found clients on their rows as pending detections; nothing is persisted until a save. Review opens the pre-filled form; Dismiss clears it.
- Remove client returns the slot to Not configured and clears its stored test.
- With Prowlarr not ready, Download button and Auto-acquisition show their title and the reason line and no controls; their save handlers still refuse.
- Auto-acquisition shows five rows and no Save; each change persists on click. `auto_grab.default_min_quality` and `auto_grab.4k_patience_hours` exist nowhere in `lib/`, the settings table or the wiki.
- The planner's automatic floor is `hd_1080p` in every path (drop planner, plan runner, pursuit retry); `WantSchedule.due?/2` depends on age bands only.
- Every section shows the shell's intro; no section module contains an `h2`; every card is `settings_card`; no card header contains a Save.
- Every kit component has a story; MC0009 and `storybook_render_test` pass.
- Every action on the page is a nav item inside the `grid` zone; opening a form focuses its first field.
- Settings-Reference and Release-Tracking on the wiki describe the rows as shipped.

## Anti-patterns this design names

- **The form as the resting state.** Inputs on screen for values entered once. The readout is the resting state; the form is a state you enter.
- **Save in the header.** A Save button above the fields it saves. A Save sits at the bottom of the form it belongs to, and only there.
- **The one-option select.** A `<select>` whose only real choice is the one shown. Show the name; keep the select for the day a second driver exists.
- **Four readiness vocabularies.** A dot here, an icon and word there. One row draws readiness.
- **Vanishing gated features.** A card that disappears when its prerequisite is missing. It stays and says what it needs (the stance of UIDR-034).
- **Section-local header dialects.** An `h2` in one section, an uppercase `h3` in the next, a `text-2xl` in a third.
- **Three ways to add an entry.** A list setting is rows plus an inline input and Add. The media-directory dialog is the one exception, because its entry has three fields.

## Deferred and rejected

- **Live connectivity in the readout** (the queue monitor's per-slot liveness, indexer health beside the manual test age). Owner: not necessary. The row shows the persisted test.
- **A modal edit dialog** instead of inline expansion. Rejected: inline keeps the row in view and the form is short. The media-directory dialog stays for its three-field entry.
- **Quality upgrades** after a lower-resolution grab. Out of scope; the consequence of dropping patience is accepted (decision 20).
- **Folding TMDB into Acquisition's nav entry.** Rejected: TMDB serves the library; only its row shape is shared.
- **A second client per protocol.** Unchanged two-slot model.
