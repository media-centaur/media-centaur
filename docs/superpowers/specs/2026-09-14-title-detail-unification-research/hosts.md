# Host inventory (subagent report, 2026-09-14). EM = live/entity_modal.ex, TDH = live/title_detail_host.ex

Use sites: EM — home_live.ex:10, library_live.ex:32. TDH — discovery_live.ex:58, incoming_live.ex:84 (Incoming also uses IntentAware after TDH, :85; Discovery subscribes Discovery itself, discovery_live.ex:99).

## 1. Events

### EntityModal (EM:113–320)
| Event | Params | Reads | Writes | Needs library half? | TDH equivalent |
|---|---|---|---|---|---|
| select_entity EM:114 | id | selected_entity_id | push_patch build_modal_path(%{selected: id-or-nil, movie: nil}) | yes | open_title |
| select_movie EM:124 | id | — | push_patch %{movie: id} | yes (member) | none |
| close_detail EM:128 | _ | selected_entry, detail_view via close_detail_target/1 EM:1338 | :close → rematch_confirm nil; push_patch %{selected: nil, view: root} or %{view: root} | partly (tab set) | close_title |
| select_detail_view EM:134 | view | — | push_patch %{view: parse_view(view)} | partly | none |
| filter_cast EM:139→1354 | cast_filter | — | cast_filter | partly | none |
| show_more_cast EM:143→1365 | _ | cast_limit | cast_limit += page | partly | none |
| toggle_season EM:147→1108 | season | expanded_seasons | expanded_seasons | partly | none |
| download_missing_episode EM:151→1134 | season, episode | download_pending, entity.tmdb_id, PlanningMode.value() | download_pending {:missing_episode, id, unit}; start_async → Targeting.series_selection/1 + Plans.create_series_plan/3 EM:1157 | partly (needs only tmdb id) | title_download (title-level) |
| toggle_file_group EM:155→1235 | dir | detail_files, expanded_file_groups, media_dirs | expanded_file_groups | yes | none |
| toggle_item_details EM:159→1258 | item-id | expanded_item_details | assign | partly | none |
| toggle_all_episode_details EM:163→1278 | _ | all_episode_details_open | negate | partly | none |
| play EM:169 | id | — | Playback.play(id); flash | yes | none |
| toggle_watched EM:187→1088 | entity-id, container-type, container-id | ProgressRecords.fetch_for_container/2 | mark_completed!/incomplete!; ProgressBroadcaster.broadcast/2 | yes | none |
| toggle_extra_watched EM:191→1620 | extra-id, entity-id | fetch_for_extra/1 | mark_*; broadcast_extra/2 | yes | none |
| rematch EM:202 | id | rematch_confirm | 1st: rematch_confirm id; 2nd: Review.Rematch.rematch_entity/1, push_navigate /review | yes | none |
| refresh_artwork EM:219 | id | entity.type | Pipeline.ImageRefresh.enqueue_refresh/2; flash | yes | none |
| set_rung EM:228→1667 | choice(off/list/follow/grab), ref | TitleRef.parse, find_tmdb_id(selected_entry) must equal ref, entity.name | mints Title.new! EM:1671; ReleaseTracking.set_rung_async/2 EM:1680; reload_tracking/1 EM:2011 → tracking, rung, lower_quality_accepted? | no | set_rung TDH:552 |
| reset_lower_quality EM:232→1696 | ref | parse + identity match | TitleDownloadParams.put(id, type, %{min_quality: nil}) EM:1699; reload_tracking | no | reset_lower_quality TDH:566 |
| modal_watchlist_toggle EM:238→1403 | choice(list/off) | watchlist_subject/2 EM:1531 (collection → member), watchlist_ref/1 EM:1547 | ReleaseTracking.set_rung/2 sync with minted Title.new! (EM:1412 off; EM:1421 list); reload_tracking | no (subject resolution library-shaped) | set_rung (title bookmark fires set_rung directly, detail_modal.ex:163) |
| modal_review_open EM:246→1454 | _ | subject; LiveHelpers.image_url(subject, "poster") | ReviewFlow.open/3 with minted Title.new! EM:1464 | no | title_review_open TDH:577 |
| review_cancel/review_sentiment/review_send (use ReviewFlow EM:244; review_flow.ex:53–59) | _/choice/text | review_subject, review_sentiment | ReviewFlow.close/choose/submit → Activities.review/3 | no | identical TDH:122 |
| reset_track_override EM:251→1377 | _ | entity.{id,type} | MediaTrackOverrides.clear/2; put_entry_track_override(nil) EM:1564 | yes | none |
| delete_file_prompt EM:267 | path | playback, selected_entity_id, delete_confirm | delete_confirm {:file, path} or run_pending_delete/1 EM:1875 (deleting; start_async {:delete, id}) | yes | none |
| delete_folder_prompt EM:283 | path, count | + media_dirs | {:folder, path} | yes | none |
| delete_all_prompt EM:302 | _ | same | :all | yes | none |
| delete_cancel EM:318 | _ | — | delete_confirm nil | yes | none |

### TitleDetailHost (handle_title_event/3 TDH:473–586; halts)
| Event | Params | Reads | Writes | Needs library half? | EM equivalent |
|---|---|---|---|---|---|
| open_title TDH:473 | ref (+activity) | — | push_patch title_detail_path([title: ref, activity: id]) | no | select_entity |
| close_title TDH:483 | _ | — | push_close/1 TDH:638 | no | close_detail |
| title_mode_toggle TDH:485 | guard title_detail | open_menu | ↔ :mode | no | none |
| title_scope_toggle TDH:491 | | open_menu | ↔ :scope | no | none |
| title_menu_close TDH:497 | | — | open_menu nil | no | none |
| title_scope TDH:505 | choice(first_season/everything) | — | download_scope, open_menu nil | no | none |
| title_download TDH:517 | optional mode | title_detail.{planning_mode, scoped?, title}, download_scope, download_pending | start_download/4 TDH:607: auto → Plans.plan_title/2 sync + flash + push_close; manual → download_pending {:title_download, ref, name} + start_async → Plans.create_title_plan/2 | no | download_missing_episode |
| title_activity_delete TDH:534 | guard activity_id | title_detail.{activity_id, kind} | Activities.delete/1; flash; push_close | no | none |
| set_rung TDH:552 | choice, ref | title_for_param/2 TDH:654 (open detail → intent → page snapshot); provenance/1 TDH:633 | apply_rung/4 TDH:668: :off → set_rung(title, :off) sync; else set_rung_async/3 when needs_calendar? (+flash) or set_rung/3 sync with provenance; refresh_title_detail/1 | no | set_rung EM:1667 |
| reset_lower_quality TDH:566 | ref | TitleRef.parse only — NO identity match | TitleDownloadParams.put/3; refresh_title_detail/1 | no | EM:1696 (matches identity) |
| title_review_open TDH:577 | guard open | title_detail.{title, poster_url} | ReviewFlow.open/3 | no | modal_review_open |
| any @modal_events TDH:115 with no open modal TDH:584 | | | halt no-op | | |

Page-level caller outside trait: feed_download discovery_live.ex:222 calls TitleDetailHost.start_download/4 directly.

## 2. Async
| Name | Host | Started from | Work | Lands | Cancel/dedupe |
|---|---|---|---|---|---|
| {:detail_files, entity_id} | EM | apply_modal_params EM:750 → start_async_files_load/2 EM:1769 | load_entity_files/1 EM:1739 (Files.list_by_entity_id + File.stat, Task.async_stream 8-way 1.5s) | EM:326/329 → apply_detail_files/3 EM:1779 (detail_files, detail_files_status :loaded) / failure EM:1791; keyed selected_entity_id == entity_id | once per selection change EM:711; stale dropped; never cancel_async |
| {:delete, entity_id} | EM | run_pending_delete/1 EM:1875 | run_delete/1 EM:1805 | EM:332/335 → apply_delete_result/3 EM:1894 (deleting nil; none left → push_patch selected nil; else detail_files reloaded synchronously) / crash EM:1918 | deleting disables buttons; NO identity check on result; never cancelled |
| {:missing_episode, entity_id, unit} | EM | EM:1134→1145 | plan_missing_episode/3 EM:1157 | EM:338/341 → apply_missing_episode_result/2 EM:1196–1214 (download_pending nil; auto → flash; manual → push_navigate /incoming?plan=) / crash EM:1217 | download_pending guard EM:1139; no identity check; never cancelled; download_pending not cleared on switch/close |
| catch-all {:exit, _} | EM | | | __before_compile__ EM:359–375 warns | |
| {:title_open, ref} | TDH | apply_title_params TDH:166 → open_from_tmdb/2 TDH:216 (connected only) | fetch_title/1 TDH:341 (Capabilities.tmdb_ready?, TMDBClient.get_movie/get_tv, Title.from_tmdb/2) | TDH:403–434: dropped if title_opening != ref; ok → build_detail/4 + preview_from_payload/4; errors → abandon_open/2 TDH:640 (flash + push_close) | no-op if title_opening == ref TDH:214; reset_detail/1 TDH:229 cancels |
| {:title_preview, ref} | TDH | open_from_snapshot/4 TDH:204 → fetch_preview/2 TDH:319 (if tmdb_ready?) | load_preview/3 TDH:331 (fetch_payload/1, TitlePreview.movie/tv, ReleaseWindow.from_payload/2) | TDH:436–458: title_detail.preview + .release_window if ref matches, else dropped | same-title re-patch doesn't restart TDH:193; never cancelled |
| {:title_download, ref, name} | TDH | start_download/4 manual TDH:618 | Plans.create_title_plan/2 | TDH:368–398: dropped if download_pending != name; ok → open_menu nil, open_plan_board/2 (download_pending STAYS set TDH:375); error → download_pending nil + flash | guard TDH:607; close/1 TDH:237 cancels; reset_detail/1 does not |

## 3. PubSub / handle_info
Subscriptions: EM on_mount EM:392–396 → Library.subscribe() (library:updates), Playback.subscribe() (playback:events), ReleaseTracking.subscribe() (release_tracking:updates), Activities.subscribe() (activities:updates), Acquisition.subscribe() (acquisition:updates). TDH on_mount TDH:129 → ReleaseTracking.subscribe() only. Topics: lib/media_centaur/topics.ex:152–182.

| Message | Host | Topic (subscriber) | Reaction | Key |
|---|---|---|---|---|
| {:entity_progress_updated, %{entity_id}} EM:413 | EM | playback:events (trait) | refresh_from_progress_payload/2 EM:550 — in-memory merge (SeriesDetail/CollectionDetail.with_progress), DB fallback | selected == entity_id |
| {:extra_progress_updated, %{entity_id}} EM:421 | EM | playback:events | refresh_from_extra_payload/2 EM:586 | entity id |
| {:entities_changed, %{entity_ids}} EM:429 | EM | library:updates (trait) | refresh_selected_entry/1 EM:853 (full load_entry/1) | selected ∈ ids |
| {tag, _} activity_received/sent/deleted EM:454 | EM | activities:updates (trait) | assign_friend_activity/1 EM:1516 | subject ref |
| %PlanEvents.Changed{} EM:463 | EM | acquisition:updates (trait) | refresh_open_series/1 EM:869 — only if %SeriesDetail{} | none |
| %struct{} Pursuits.Events.is_event/1 EM:465 | EM | acquisition:updates | same | none |
| {:library_view_updated, :detail, _} EM:468 | EM | library:views — NOT subscribed by trait; hosts do (home_live.ex:54, library_live.ex:67) | refresh_selected_entry/1 | none |
| {:playback_state_changed, %{entity_id, state, now_playing}} EM:476 | EM | playback:events | LiveHelpers.apply_playback_change/4 → playback | map by entity id |
| {:track_override_changed, %{owner_type, owner_id}} EM:496 | EM | playback:events | put_entry_track_override/2 | selected == owner_id |
| {:releases_updated, _item_ids} EM:511 | EM | release_tracking:updates (trait) | if tv_series/movie_series: refresh_selected_entry + reload_tracking | none (deliberately loose EM:504–510) |
| {:item_removed, _, _} EM:519 | EM | release_tracking:updates | refresh_selected_entry only — no reload_tracking | none |
| {tag, _} tag ∈ [:releases_updated, :title_intent_changed, :entities_changed] TDH:466 | TDH | release_tracking:updates (trait); discovery:updates (Discovery itself :99; Incoming via IntentAware, which HALTS :title_intent_changed intent_aware.ex:39–41 — hence "use TDH first" TDH:30–32); library:updates (discovery_live.ex:100, incoming_live.ex:205) | refresh_title_detail/1 TDH:263 — rebuilds every fact by identity, keeps snapshot + preview | title_detail.ref |

Not handled in TDH hook: activities:updates and acquisition:updates. Discovery covers via page clauses (discovery_live.ex:272–274 → load_activities → stamp_acquisition_states → TitleDetailHost.refresh_title_detail() :363/:418; :289–291 plan/pursuit → same). Incoming: ZERO calls to refresh_title_detail — pennants and primary acquisition state in an open title modal on Incoming go stale until a rung/releases/entities message. Not handled in EM: :title_intent_changed — EM's rung assign refreshes only via reload_tracking; subject_rung/3 (bookmark) reads host title_rungs from IntentAware, so two rung readouts can disagree.

## 4. URL / handle_params
| | EM | TDH |
|---|---|---|
| Params | selected (uuid), view (info/cast; :main omitted), movie (member uuid) — modal_query_params/2 EM:807 | title (<media_type>-<tmdb_id>), activity (uuid, consumed only via page_facts/3) |
| Entry | host calls apply_modal_params/2 EM:659 from its own handle_params (home_live.ex:299/304, library_live.ex:122) | :handle_params hook apply_title_params/3 TDH:159 attached in on_mount TDH:141 — runs BEFORE host's handle_params |
| Resolution | selected → load_entry_or_nil/1 EM:1938 → load_entry/1 EM:1960 → Presentable.resolve/1 → SeriesDetail.compose / CollectionDetail.compose / ModalEntry.load_resolved + put_resume_target/1. view → parse_view/1 EM:1934, resolve_view/2 EM:1300 (Detail.Logic.resolve_view/2); entity switch forces :main EM:664–665. movie → params["movie"] || implied_member_id/2 EM:759. expanded_seasons seeded from Orientation EM:788; per-selection UI reset EM:773 | snapshot/3 TDH:180–183: (1) open detail's own title if same ref → (2) Discovery.get_intent/2 embedded Title TDH:185 → (3) page copy page_facts/3 (Discovery: activity row's activity.title discovery_live.ex:138–153; Incoming: plan_title + omnibox_results incoming_live.ex:451–457) → (4) TMDB open_from_tmdb/2 TDH:216 (async, connected only). Snapshot hit → open_from_snapshot/4 TDH:193 (build_detail/4 + fetch_preview/2; same-ref re-patch keeps preview) |
| Unknown | :not_found → selected_entry nil but selected_entity_id STAYS set, detail_presentation :modal (EM:735–738); modal renders closed (EM:1006); URL keeps stale selected. Later refresh_selected_entry :not_found clears EM:858 | TitleRef.parse :error → close/1 TDH:170 — no flash, URL keeps bad param. Unknown TMDB id → async {:error, :not_found} → abandon_open/2 TDH:640: flash "TMDB has no movie/TV series with that id." + push_close. No key → flash TDH:644 + push_close |
| Close | close_detail → close_detail_target/1 EM:1338 → %{selected: nil, view: root}; modal_query_params drops all three when selected nil EM:813–815. apply_delete_result EM:1900 pushes selected nil. Path builders: home_live.ex:326, library_live.ex:599/604 | push_close/1 TDH:638 → title_detail_path(socket, []): discovery_path/2 discovery_live.ex:157; incoming_path/2 incoming_live.ex:460. No title param → close/1 TDH:174 (cancels download_pending + title_open, resets title_detail/open_menu/download_scope). Incoming open_plan_board/2 :466 patches plan= which drops title |

Home extra `zone` param redirects to /incoming or /library before modal params (home_live.ex:285–301).

## 5. Shared fact loads
| Load | EM | TDH | Divergence |
|---|---|---|---|
| Tracking half | EM:1993–2005 load_tracking/1: TrackingDetail.load(ref, %{today: Date.utc_today(), acquisition_ready?: Capabilities.acquisition_ready?(), approval_policy: PlanningMode.approval_policy(PlanningMode.value())}) → tracking | TDH:290–294 build_detail/4: same map with today: socket.assigns.today → facts.tracking | ref: EM find_tmdb_id/1 EM:1648 (collection yields {collection_id, :movie}) vs TDH Title.ref. today: fresh vs mount-time. Refresh: EM on selection (EM:722) + reload_tracking; TDH every build |
| Rung | EM:1507 entry_rung/1 → Discovery.rung → rung (ladder); separately subject_rung/3 EM:1483 reads host title_rungs (bookmark) | TDH:280 Discovery.rung → facts.rung (feeds both, detail_modal.ex:160–163, 219) | EM two rung sources, different subjects/refresh; EM no refresh on :title_intent_changed |
| Pennants | EM:1522 Map.get(Activities.friend_activity_for([ref]), ref, []) assign_friend_activity/1 → friend_activity (member for collection) | TDH:299 identical → facts.friend_activity | EM refreshes on activity tags + every apply; TDH only inside refresh_title_detail (page-dependent) |
| Quality acceptance | EM:1716–1717 TitleDownloadParams.get |> DownloadParams.lower_quality_accepted?() → lower_quality_accepted?; write EM:1699 | TDH:281–282 same → facts; write TDH:568 | EM write identity-guarded; TDH write accepts any ref |
| Approval policy | EM:634 approval_policy at on_mount, never refreshed; EM:1148, EM:1999 re-read PlanningMode.value() | TDH:275 PlanningMode.value() per build → facts.planning_mode + TDH:293 policy in tracking ctx; TDH:611/619 | EM mount-time, no :setting_changed reaction; EM exposes policy string, TDH mode atom |
| Acquisition readiness | EM:635 acquisition? at on_mount, never refreshed; EM:1998 fresh inside tracking ctx | TDH:274 per build → facts.acquisition?; prowlarr_ready?() TDH:284 (release_mode_available), tmdb_ready?() TDH:320/353 | EM stale after capability change (tmdb_ready from router-level CapabilitiesAware router.ex:22–29) |
| Review flow | EM:244 use ReviewFlow; EM:613 init; EM:1454 open_review/1 → ReviewFlow.open(socket, Title.new!(…), image_url(subject, "poster")) | TDH:122; TDH:140; TDH:581 ReviewFlow.open(socket, detail.title, detail.poster_url) | EM mints, TDH resolved title. Poster: library image vs TMDB |

Other duplicates:
| Item | EM | TDH |
|---|---|---|
| Title.new! minting (FOUR sites) | EM:1412, 1421, 1464, 1671 | none — Title.from_tmdb/2 TDH:344 or resolved |
| rung_atom/1 + @rungs | EM:1664, 1690–1693 | TDH:116, 687–690 (verbatim copy) |
| ReleaseTracking.set_rung* | ladder always set_rung_async/2 EM:1680; bookmark sync set_rung/2 EM:1411/1421; no provenance | sync vs async by needs_calendar? TDH:674; provenance TDH:633 |
| download_pending guard + planning start_async | EM:1139–1153 | TDH:607–625 |
| PlanFlow.download_flash/failure_flash | EM:1199, 1213, 1222 | TDH:388, 397, 614 |
| TDH-only facts | — | ExternalIds.tmdb_owners/1 TDH:279, TitleStates.for_refs/1 TDH:283, ReleaseTracking.complete?/2 TDH:296, TmdbArtwork.urls/2 TDH:273, intent note Discovery.get_intent/2 TDH:310 |

## 6. Assigns
### EM (assign_modal_defaults/1 EM:611–640 + ReviewFlow.init/1)
| Group | Assign | Set | Reset on subject change? |
|---|---|---|---|
| Subject | selected_entity_id, selected_member_id, selected_entry, detail_presentation | EM:735–738 | yes |
| View-model | selected_entry (map | SeriesDetail | CollectionDetail) | EM:679, 856, merges 563/568/580/596/1567 | yes |
| Per-selection UI | detail_view | EM:739 (URL; :main on switch EM:665) | yes |
| | detail_files, detail_files_status | EM:713–720, 1781/1798/1904 | yes |
| | expanded_seasons | EM:673–684 (Orientation); EM:1117 | yes |
| | expanded_file_groups, cast_filter, cast_limit, expanded_item_details, all_episode_details_open | @per_selection_defaults EM:773–784 | yes |
| | rematch_confirm | EM:130 (cleared on :close only), 210/213 | NO |
| | delete_confirm | EM:279/298/314/319, 1882 | NO |
| | deleting | EM:1882, 1895, 1922 | no (cleared on result) |
| Facts | tracking, rung, lower_quality_accepted? | EM:722–730, reload_tracking EM:2011 | yes |
| | friend_activity | EM:748, 456 | yes |
| | approval_policy, acquisition? | EM:634–635 mount only | never |
| Async/menus | download_pending | EM:1152, 1198/1204/1212/1221 | NO |
| | playback | EM:488; Home seeds home_live.ex:319 | page-wide |
| Review | review_subject, review_poster_url, review_sentiment, review_relay_counts | review_flow.ex:75–100 | NO — close_detail does not close a review |
| Host-owned read by renderer | media_dirs, availability_map, tmdb_ready, spoiler_free, letterboxd_links, title_rungs, show_discovery | EM:31–35, attrs EM:985–1001 | n/a |

### TDH (on_mount TDH:133–140)
| Group | Assign | Set | Reset? |
|---|---|---|---|
| Subject + VM | title_detail (%TitleDetail{}) | TDH:198/203/266/413/443 | yes (reset_detail/1 TDH:229) |
| Fetched-open | title_opening (ref) | TDH:221, 231, 414, 641 | yes |
| Menus | open_menu (:mode | :scope | nil), download_scope | TDH:232, 378, 415–416, 489–512, 531 | yes |
| Async | download_pending | TDH:239, 387/396, 623 | NO — reset_detail leaves it; success leaves it set TDH:375 |
| Review | four ReviewFlow assigns | TDH:140 | no |
| Host-owned | today (required TDH:48; discovery_live.ex:120, incoming_live.ex:217); snapshot sources omnibox_results, plan_title (Incoming), activity rows (Discovery) | pages | n/a |

## 7. MC0011 credo_checks/entity_modal_contract.ex
Scope: files under lib/media_centaur_web/live/ (:80–82). Trigger: a `use` whose alias equals a key in @trait_subscribes (:90–95). Map: EntityModal => [:Library, :Playback]; SpoilerFreeAware => [:Settings]; CapabilitiesAware => [:Capabilities]; WatchlistAware => [:Discovery] (:57–62). Forbidden: Foo.subscribe(...) with single-segment alias (:101). Not covered: TDH (ReleaseTracking.subscribe TDH:129); EM's other three subscribes; IntentAware (Discovery.subscribe intent_aware.ex:29) — WatchlistAware entry is dead (no such file); multi-segment call MediaCentaur.Library.subscribe() (incoming_live.ex:205) never matches. Renaming the trait: change key :58 and prose :15/:28/:37; forgetting fails nothing. event_chokepoint.ex is a shared AST matcher for MC0012/13/26 (broadcast chokepoints), does not constrain hosts.

## Findings
- Subscription asymmetry: EM subscribes 5, depends on a 6th (library:views) hosts subscribe; TDH subscribes 1, depends on 2 hosts subscribe. Incoming ordering rule exists only because IntentAware halts :title_intent_changed.
- Refresh coverage differs by page for the same modal (Incoming never refreshes title detail on activity or plan/pursuit events).
- Mount-time facts in EM: approval_policy, acquisition? never refreshed.
- Two rung readouts in EM.
- Stale-state leaks in EM: rematch_confirm, delete_confirm, download_pending, review assigns survive entity switch; TDH leaks download_pending across subject switch.
- Identity guards differ: EM guards set_rung/reset_lower_quality; TDH reset_lower_quality accepts any ref.
- Title.new! minted in four EM sites.
- Collection identity: find_tmdb_id/1 EM:1655–1659 stamps tmdb_collection id as {id, :movie}, flowing into TrackingDetail.load, Discovery.rung, TitleDownloadParams.get, set_rung.
- MC0011 stale: dead WatchlistAware entry, no TDH/IntentAware coverage, single-segment pattern misses qualified calls.
