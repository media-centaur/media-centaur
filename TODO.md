# TODO

## TMDB Confidence Scorer: Same-Title Disambiguation

**Problem:** When two shows share an identical title (e.g., "Sample Show One" 2001 vs "Sample Show One" 2026 reboot), both receive a confidence score of 1.0. `Enum.max_by` silently picks whichever TMDB returns first in its search results. There is no tiebreaker logic.

**Real-world impact:** The entire Sample Show One library (8 seasons, 161 files) was ingested against the wrong TMDB ID — the 2026 reboot (ID 295778) instead of the classic 2001 show (ID 4556).

**Current mitigation:** When multiple TMDB results tie at the best confidence score, the Search stage now forces `:needs_review` instead of auto-approving. All tied candidates are included in `payload.candidates` for the review UI.

### Ideas for Further Refinement

- **Prefer older `first_air_date` on ties.** When scores are equal, break ties by preferring the show with the earlier premiere date. Libraries are far more likely to contain established shows than brand-new reboots.
- **Season count validation.** If the library already has files spanning 8 seasons, a TMDB result with only 1 season is a poor match regardless of title score. Cross-reference the number of season directories against `number_of_seasons` from the TMDB detail response.
