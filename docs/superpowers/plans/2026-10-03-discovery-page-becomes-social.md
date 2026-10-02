# The Discovery Page Becomes Social — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Everything named for the Discovery *page* is named Social: the route, the LiveView and its helpers, the component family, the stories, the preference, the page behaviour, the CSS, the sidebar entry, the docs. The `MediaCentaur.Discovery` *context* (title intents) is untouched — that is Phase 3.

**Architecture:** A rename with no behaviour change. Three units that each compile on their own: (1) the preference (`show_discovery` → `show_social`, no data migration — the value resets to its default, off); (2) the page and its family (`DiscoveryLive` → `SocialLive`, `Components.Discovery` → `Components.Social`, `storybook/discovery` → `storybook/social`, `discovery_behavior.js` → `social_behavior.js`, `.discovery-*` CSS → `.social-*`, `/discovery` → `/social`); (3) prose, docs, decision record and wiki.

**Tech Stack:** Phoenix LiveView, ExUnit, Phoenix Storybook, bun, the wiki repo.

Campaign: [`campaigns/social-and-watchlist.md`](../../../campaigns/social-and-watchlist.md), Phase 2. Run every `mix` command through `~/scripts/agents/agent-mix`. Use `git mv` for every rename so history follows.

**Names.** The sidebar entry, the page title, the `page_header`, the Settings row label and the preference's user-facing name are all **Social**. Sidebar icon: `hero-users`. The page is "the Social page" in prose; the subsystem (`MediaCentaur.Social`) keeps its name — the same word on the page and its subsystem is one context's two faces (campaign glossary).

**Out of scope.** `MediaCentaur.Discovery`, `Discovery.*`, `discovery:updates`, `Pipeline.Discovery`, `test/support/factory.ex`'s "Discovery (title intents)" section, the data-migration test `rename_show_watchlist_settings_key_test.exs` (history), `CHANGELOG.md` (ship time).

---

## File map

| Was | Becomes |
|---|---|
| `lib/media_centaur/settings/preferences/discovery_visibility.ex` (`Preferences.DiscoveryVisibility`, key `show_discovery`) | `…/social_visibility.ex` (`Preferences.SocialVisibility`, key `show_social`) |
| `lib/media_centaur_web/live/discovery_live.ex` (`MediaCentaurWeb.DiscoveryLive`) | `…/social_live.ex` (`MediaCentaurWeb.SocialLive`) |
| `lib/media_centaur_web/live/discovery_live/{activity_artwork,activity_words,add_friend_block,feed_entries,people}.ex` (`DiscoveryLive.*`) | `…/social_live/…` (`SocialLive.*`) |
| `lib/media_centaur_web/components/discovery/{act,feed_entry,feed_row,hue_swatches,identity_tile,person_card}.ex` (`Components.Discovery.*`) | `…/components/social/…` (`Components.Social.*`) |
| `storybook/discovery/{_discovery.index,feed_row.story,hue_swatches.story,identity_tile.story,person_card.story}.exs` (`Storybook.Discovery.*`) | `storybook/social/{_social.index,…}` (`Storybook.Social.*`) |
| `test/media_centaur_web/live/discovery_live_test.exs`, `test/media_centaur_web/live/discovery_live/*_test.exs`, `test/media_centaur_web/components/discovery/*_test.exs` | `…/social_live_test.exs`, `…/social_live/`, `…/components/social/` |
| `test/support/discovery_rows.ex` (`MediaCentaur.DiscoveryRows`) | `test/support/social_rows.ex` (`MediaCentaur.SocialRows`) |
| `assets/js/input/discovery_behavior.js` (`createDiscoveryBehavior`), `assets/js/input/__tests__/discovery_behavior.test.js` | `social_behavior.js` (`createSocialBehavior`), `social_behavior.test.js` |
| `assets/js/input/page_behavior.js` registry key `discovery`; `config.js` layouts/cursorStartPriority key `discovery` | `social` |
| `assets/css/app.css` `.discovery-page`, `.discovery-columns`, `.discovery-rail`, `.discovery-head`, `.discovery-head-cell`, container name `discovery` | `.social-page`, `.social-columns`, `.social-rail`, `.social-head`, `.social-head-cell`, container `social` |
| Routes `/discovery`, `/discovery/friends` | `/social`, `/social/friends` |
| Assign `show_discovery` (every LiveView, `Layouts.app`, `review?={@show_discovery}`), event `toggle_show_discovery`, on_mount hook `:setting_aware_show_discovery` | `show_social`, `toggle_show_social`, `:setting_aware_show_social` |
| `data-page-behavior="discovery"` | `"social"` |

---

### Task 1: The preference is `show_social`

**Files:**
- Rename: `lib/media_centaur/settings/preferences/discovery_visibility.ex` → `social_visibility.ex`
- Modify: `lib/media_centaur/settings/preferences.ex:13`, `lib/media_centaur_web/router.ex:32-37`, `lib/media_centaur_web/components/layouts.ex:48-52,137`, `lib/media_centaur_web/live/settings_live.ex:940-943` and its three `show_discovery={@show_discovery}` sites, `lib/media_centaur_web/live/settings_live/preferences.ex:20,62-67`, every LiveView passing `show_discovery={@show_discovery}` or `review?={@show_discovery}` (`home_live`, `library_live`, `incoming_live`, `discovery_live`, `apps_live`, `guide_live`, `status_live`, `watch_history_live`, `review_live`, `episode_mapping_live`), `lib/media_centaur_web/components/detail_panel.ex:134`, `lib/media_centaur_web/components/detail/view_controls.ex:55`, `lib/media_centaur_web/live/title_detail_host.ex:47`
- Tests: `test/media_centaur_web/live/settings_live_test.exs:12,214-220`, `home_live_test.exs:29-32`, `library_live_test.exs:22,418,488,510`, `discovery_live_test.exs:25,80,1301,1642-1647`, `incoming_live_test.exs:2533`, `no_db_on_render_test.exs:283,298` (comments)

- [ ] **Step 1: Tests first.** Replace `DiscoveryVisibility` → `SocialVisibility`, `"show_discovery"` → `"show_social"`, `toggle_show_discovery` → `toggle_show_social` across the test files above. Run `~/scripts/agents/agent-mix test test/media_centaur_web/live/settings_live_test.exs` — fails (module undefined).

- [ ] **Step 2: Implement.** `git mv` the preference file; module `MediaCentaur.Settings.Preferences.SocialVisibility`, `key: "show_social", default: false`. Moduledoc:

```elixir
@moduledoc """
Typed accessor for the `show_social` Settings entry.

Gates the sidebar's Social entry and the Review control on the title
detail modal. Default-**off**: the Social page is an early preview, so
it stays out of the sidebar until a person opts in under Settings →
Preferences. The page stays reachable by URL and the watchlist is
unaffected — it lives on Incoming (UIDR-050).

Renamed from `show_discovery` on 2026-10-03 (UIDR-051) without a data
migration: the preference resets to its default. The 2026-09-02 rename
from `show_watchlist` was a data migration
(`RenameShowWatchlistSettingsKey`); that history stands.
"""
```

Then the registry (`preferences.ex`), the router on_mount tuple (`{Preferences.SocialVisibility, :show_social, :setting_aware_show_social}`, comment "its Social entry"), `Layouts.app`'s attr `show_social` and its doc, the sidebar `:if={@show_social}` (label/icon/paths are Task 2), the settings row (`label="Social"`, `description="Show the Social page in the sidebar. Early preview — it may still change shape"`, `checked={@show_social}`, `event="toggle_show_social"`), the handler, every `show_social={@show_social}` / `review?={@show_social}`, the three doc strings. `grep -rn "show_discovery\|DiscoveryVisibility" lib test storybook` must be empty except the data-migration test and `social_visibility.ex`'s history sentence.

- [ ] **Step 3: Green.** `~/scripts/agents/agent-mix compile --warnings-as-errors && ~/scripts/agents/agent-mix test test/media_centaur_web/live/settings_live_test.exs test/media_centaur_web/live/home_live_test.exs test/media_centaur_web/live/library_live_test.exs test/media_centaur_web/live/discovery_live_test.exs test/media_centaur_web/live/incoming_live_test.exs test/media_centaur_web/no_db_on_render_test.exs`.

- [ ] **Step 4: Commit** `refactor(settings): show_discovery is show_social (no migration; the preference resets)`.

---

### Task 2: The page and its family are Social

**Files:** every row of the file map except the preference; plus the aliases in `lib/media_centaur_web/components/detail_panel.ex:96,110`, `lib/media_centaur_web/components/title/social.ex:35`, `lib/media_centaur_web/live/settings_live/social_section.ex:48-49`, `lib/media_centaur_web/live/title_detail_host.ex:109`; `test/media_centaur_web/page_smoke_test.exs` (the `/discovery*` rows → `/social*`); `lib/media_centaur_web/components/layouts.ex:136-148` (the sidebar entry); `lib/media_centaur_web/live/discovery_live.ex` (`page_title "Social"`, `page_header title="Social"`, `data-page-behavior="social"`, class `social-rail` etc., every `~p"/discovery…"`, `current_path/1`, `discovery_path/2` → `social_path/2`, `feed_path/1`).

- [ ] **Step 1: Tests first.** `git mv` the test files and directories; rename modules (`MediaCentaurWeb.SocialLiveTest`, `MediaCentaurWeb.SocialLive.FeedEntriesTest`, `MediaCentaurWeb.Components.Social.FeedRowTest`, …), aliases, every `/discovery` path → `/social`, `data-page-behavior='discovery'` → `'social'`, `"Discovery"` heading assertions → `"Social"`, the sidebar assertion `a.sidebar-link-active[href='/social']`. `git mv test/support/discovery_rows.ex test/support/social_rows.ex`, module `MediaCentaur.SocialRows`, moduledoc "the shape `SocialLive` assigns"; update its users (`grep -rn DiscoveryRows test`). JS: `git mv` the behaviour test, `createSocialBehavior`, `inputConfig.layouts.social`, `cursorStartPriority.social`, `buildNavGraph("social", …)`, describe "social behavior". Run one Elixir test file and `bun test` — both fail (modules/keys undefined).

- [ ] **Step 2: Implement the Elixir side.** `git mv` the LiveView, its directory, the component directory, the storybook directory; rename every module (`MediaCentaurWeb.SocialLive`, `SocialLive.ActivityArtwork|ActivityWords|AddFriendBlock|FeedEntries|People`, `MediaCentaurWeb.Components.Social.Act|FeedEntry|FeedRow|HueSwatches|IdentityTile|PersonCard`, `MediaCentaurWeb.Storybook.Social` + `Storybook.Social.FeedRow|HueSwatches|IdentityTile|PersonCard`); every alias and `defp`/doc reference in the files listed above and inside the renamed files; the router (`live "/social", SocialLive, :feed`; `live "/social/friends", SocialLive, :friends`); the sidebar entry:

```heex
<.link
  :if={@show_social}
  navigate="/social"
  class={sidebar_link_class(@current_path, ["/social", "/social/friends"])}
  data-tip="Social"
  data-nav-item
  data-nav-remember
  tabindex="0"
>
  <.icon name="hero-users" class="size-5 flex-shrink-0" />
  <span class="sidebar-label">Social</span>
</.link>
```

In the LiveView: `assign(:page_title, "Social")`, `<.page_header title="Social" …/>`, `data-page-behavior="social"`, `~p"/social…"` everywhere, `current_path(:friends)` → `"/social/friends"`, the default `"/social"`, `discovery_path/2` → `social_path/2` (and `title_detail_path/2` which calls it), the rail link `~p"/social/friends"`, `push_navigate(… ~p"/social/friends?person=…")`, the flash/empty-state copy if any names the page. The storybook index: `def folder_icon, do: {:fa, "users", :light, "psb:mr-1"}` (keep the four entries). `grep -rn "DiscoveryLive\|Components\.Discovery\|Storybook\.Discovery\|/discovery\|discovery_live\|DiscoveryRows" lib test storybook` must be empty.

- [ ] **Step 3: Implement the JS/CSS side.** `git mv assets/js/input/discovery_behavior.js assets/js/input/social_behavior.js`, `createSocialBehavior`, header comment "Social page behavior"; `page_behavior.js` import and registry key `social`; `config.js`: the `discovery` layout key → `social` (and its comment "Social: the zone-tabs strip above the person cards on Friends…"), `cursorStartPriority.social`, the two comments at ~l.39 and ~l.46 ("The Social page's title detail modal…", "Social's Friends tab…"). `app.css` ~l.3366–3430: the comment "Social's columns (UIDR-046)", every `.discovery-*` class → `.social-*`, `container: social / inline-size`, both `@container social (…)` rules; the LiveView's templates use the new classes. `grep -rn "discovery" assets/js assets/css lib/media_centaur_web` must return only `pipeline`-related or no hits.

- [ ] **Step 4: Green.** `~/scripts/agents/agent-mix compile --warnings-as-errors`; `~/scripts/agents/agent-mix test test/media_centaur_web/live/social_live_test.exs test/media_centaur_web/live/social_live test/media_centaur_web/components/social test/media_centaur_web/components/title test/media_centaur_web/components/detail test/media_centaur_web/live/settings_live_test.exs test/media_centaur_web/live/home_live_test.exs test/media_centaur_web/live/library_live_test.exs test/media_centaur_web/live/incoming_live_test.exs test/media_centaur_web/page_smoke_test.exs test/media_centaur_web/storybook_compile_test.exs test/media_centaur_web/storybook_render_test.exs`; `cd assets && bun test`; `~/scripts/agents/agent-mix boundaries`.

- [ ] **Step 5: Commit** `refactor: the Discovery page is the Social page — /social, SocialLive, Components.Social, the social page behaviour (UIDR-051)`.

- [ ] **Step 6: The context-map test, as its own commit.** `test/context_map/fixture_instances_test.exs:18` names `MediaCentaurWeb.DiscoveryLive.FeedEntries`; it belongs to the `context-map` branch this branch currently sits on. Change it to `MediaCentaurWeb.SocialLive.FeedEntries`, run `~/scripts/agents/agent-mix test test/context_map/fixture_instances_test.exs`, commit separately: `test(context_map): follow the SocialLive rename` — so the owner can drop this one commit if the branch is rebased onto `main` before `context-map` merges.

---

### Task 3: Prose, docs, the decision record, the wiki

**Files:**
- Create: `decisions/user-interface/2026-10-03-051-the-discovery-page-is-the-social-page.md`
- Amend (dated blockquote + `amended: 2026-10-03`): UIDR-010 (`2026-04-27-010-page-redistribution.md:14` lists Discovery in the Watch group), UIDR-038, UIDR-045, UIDR-046 (the page's name throughout), UIDR-043 and UIDR-050 (name the page), UIDR-020:17 and UIDR-033:10 (a word each — amend only if the sentence would mislead; a note in brackets is enough)
- Modify prose: `lib/media_centaur_web/live/social_live.ex` moduledoc ("The Social page — …"), `lib/media_centaur_web/live/social_live/activity_artwork.ex:17`, `lib/media_centaur_web/live/settings_live.ex:123` ("Friends are managed on the Social page."), `lib/media_centaur_web/live/settings_live/social_section.ex:33`, `lib/media_centaur_web/components/tab_strip.ex:4`, `lib/media_centaur_web/components/title/logic.ex:8`, `lib/media_centaur_web/live/title_detail_host.ex:6`, `lib/media_centaur_web/shell_badges.ex:41`, `lib/media_centaur/social/connections.ex:109`, `lib/media_centaur/social/identity.ex:7`, `test/support/tmdb_stubs.ex:183`, `assets/js/input/config.js` comments if any remain
- Docs: `docs/social.md` (every mention of the *page*, `DiscoveryLive`, `Components.Discovery`, `/discovery`, `show_discovery` — leave `MediaCentaur.Discovery` the context alone), `docs/GLOSSARY.md` (row **Discovery** → **Social** (page); **Feed** (tab) "The Social page's tab at `/social`"; **Title detail modal** "on Home, Library, Social and Incoming"; **Social** row gains "and the Social page (Feed, Friends) at `/social`, gated by `show_social`"), `docs/storybook.md:127-129` (`social.*`), `docs/architecture.md:202`, `docs/input-system.md:365`, `.claude/skills/user-interface/SKILL.md` (Page Structure row → **Social** `/social`, `/social/friends`; inventory rows' paths `social/…`; the sub-directory list; the host sentence), `.claude/skills/input-system/SKILL.md:121`, `.claude/skills/automated-testing/SKILL.md:96` (`/social/*`), `.claude/commands/design-audit.md:48`, `README.md:50` ("**Social** — …"), `priv/guide/watchlist-and-tracking.md:19`, `campaigns/social-and-watchlist.md` (Status: Phase 2 done on branch; Next steps 2 marked done; glossary row for Social (page) now true)
- Wiki: `Social.md` (nine mentions: the page is **Social**, routes `/social`, the preference **Social**, "Social → Feed", "Social → Friends"), `Settings-Reference.md:50,101,147` (**Social** (default off) — shows the Social page…), `Watchlist.md:71`, `FAQ.md:73`, `Keyboard-and-Gamepad.md` if it names the page

- [ ] **Step 1: UIDR-051.**

```markdown
---
status: accepted
date: 2026-10-03
---
# The Discovery page is the Social page

Amends UIDR-010 (the Watch group's pages) and the records that name the page: UIDR-038, UIDR-043, UIDR-045, UIDR-046, UIDR-050.

## Context and Problem Statement

The Discovery page held three tabs: Feed, Watchlist, Friends. UIDR-050 moved the watchlist to Incoming. What is left — friends' reviews and listings, and the roster — is the social subsystem's one page, and "Discovery" no longer says what it is. The `show_discovery` preference gated the page and the Review control.

## Decision Outcome

1. **The page is Social**, at `/social` (Feed, the default) and `/social/friends`. Sidebar entry **Social** (`hero-users`), gated by **Social** under Settings → Preferences (`show_social`, default off — the page is still an early preview).
2. **Code and surface agree** (ADR-075 rule 3): `SocialLive`, `Components.Social.*`, the `social` page behaviour and nav layout, the `.social-*` classes.
3. **No data migration.** `show_discovery` is not read any more; the preference resets to off and is switched on again by the person who wants the page.
4. **The subsystem keeps its name.** `MediaCentaur.Social` and the Social page are one context's two faces; the shared word is correct, not a collision.

### Consequences

* Good, because the sidebar names what the page is.
* Bad, because anyone who had turned Discovery on turns Social on once.
```

Then the amendments, one line each, e.g. UIDR-046: "> **Amendment 2026-10-03 (UIDR-051).** The Discovery page named below is the Social page at `/social`; `DiscoveryLive`, `Components.Discovery` and `.discovery-*` are `SocialLive`, `Components.Social` and `.social-*`." Run `scripts/gen-decisions-index`.

- [ ] **Step 2: The prose and docs** as listed. For `docs/social.md`, read the whole file: it mixes the page and the context; change only page sentences. `grep -rn -i "discovery page\|/discovery\|DiscoveryLive\|Components.Discovery\|show_discovery\|Discovery →\|Discovery tab\|Discovery entry\|on Discovery" lib test storybook assets docs .claude priv README.md campaigns ../media-centaur.wiki` must return only Phase-3 context mentions, historical records (amended), `docs/superpowers`, `docs/plans`, the data-migration test and `CHANGELOG.md`.

- [ ] **Step 3: Green and commit.** `~/scripts/agents/agent-mix test test/media_centaur/guide test/media_centaur_web/storybook_compile_test.exs`; `~/scripts/agents/agent-mix format`; commit `docs: UIDR-051 — the Discovery page is the Social page; prose, glossary, skills, guide, wiki`; wiki commit `wiki: the Discovery page is the Social page` (no push).

---

### Task 4: Precommit, a look, the campaign

- [ ] `~/scripts/agents/agent-mix precommit` clean.
- [ ] With the dev server up: `~/scripts/agents/page-shot --url http://127.0.0.1:2160/social --viewport 1920x1080 --wait-ms 4000 -o <scratch>/social.png` — the header reads Social, the sidebar entry (when the preference is on) reads Social with the users icon, the rail renders. `http://127.0.0.1:2160/settings?section=preferences` — the row reads Social.
- [ ] `campaigns/social-and-watchlist.md`: Status "Phases 1–2 done on branch `social-and-watchlist`, awaiting merge; Phase 3 next"; Completion criteria' sidebar line now holds.
