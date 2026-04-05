# Consolidate off-scale micro-typography into a single utility

**Source:** design-audit 2026-04-06, DS14
**Severity:** Minor (18 instances)
**Scope:** `assets/css/app.css`, `lib/media_centaur_web/live/review_live.ex`, `lib/media_centaur_web/components/upcoming_cards.ex`

## Context

Tailwind's standard scale starts at `text-xs` (12px). Review and Upcoming both want tiny uppercase labels for section headers and S/E episode prefixes, and each site has invented a slightly different off-scale size:

- `text-[0.5625rem]` (9px) — `review_live.ex:384,396`
- `text-[0.625rem]` (10px) — `review_live.ex:538,556`
- `text-[0.6875rem]` (11px) — `review_live.ex:458`
- `text-[10px]` — `review_live.ex:783`, `upcoming_cards.ex:257`
- `text-[9px]` — `upcoming_cards.ex:393,398,590`
- `text-[11px]` — `upcoming_cards.ex:386,586`
- `text-[0.7em]` — `upcoming_cards.ex:435,436,476,477,502,503`

Paired `tracking-[0.05em]` / `tracking-[0.06em]` at `review_live.ex:384,396,556`.

Eighteen ad-hoc sizes that do the same visual job — micro uppercase labels.

## What to do

1. Pick a canonical micro size. 10px (0.625rem) is the median and is already the most common. Use that.
2. Add a `text-micro` utility in `assets/css/app.css` (somewhere near the theme-independent utility block, around line 123):
   ```css
   .text-micro {
     font-size: 0.625rem;
     font-weight: 600;
     text-transform: uppercase;
     letter-spacing: 0.05em;
   }
   ```
3. Replace every `text-[0.5625rem|0.625rem|0.6875rem|10px|11px|9px] font-semibold uppercase tracking-[...]` cluster in review_live.ex and upcoming_cards.ex with `text-micro` (keep opacity/color classes like `text-base-content/40` — `text-micro` only sets size/weight/case/tracking).
4. The `text-[0.7em]` S/E prefixes inside episode code spans are a different case — they're sizing relative to the parent line, not a standalone label. Leave them alone OR move them to a separate `text-micro-inline` utility. Don't force them into `text-micro`.
5. `grep -rn "text-\[" lib/media_centaur_web/` should return nothing (or only the deliberately-kept inline `0.7em` cases).

## Acceptance criteria

- One utility, not eighteen arbitrary sizes.
- Visual result unchanged in Review and Upcoming (screenshot-diff if you want to be sure, otherwise read the rendered page).
- `mix precommit` clean.
