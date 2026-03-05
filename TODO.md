# TODO

## Ideas for Further Refinement of TMDB matcher

- **Prefer older `first_air_date` on ties.** When scores are equal, break ties by preferring the show with the earlier premiere date. Libraries are far more likely to contain established shows than brand-new reboots.
- **Season count validation.** If the library already has files spanning 8 seasons, a TMDB result with only 1 season is a poor match regardless of title score. Cross-reference the number of season directories against `number_of_seasons` from the TMDB detail response.
