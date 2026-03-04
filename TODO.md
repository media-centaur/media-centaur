# TODO

## MPV Plugins & Scripts

Future enhancements to the MPV playback experience. These are all MPV-side (Lua scripts or C plugins in `~/.config/mpv/scripts/`) and require no backend code changes — our IPC observers pick up any state changes they cause.

- [ ] **OLED screensaver** — [mpv-oled-screensaver](https://github.com/Akemi/mpv-oled-screensaver). Fades to black after 15s when paused in fullscreen. Prevents OLED burn-in.
- [ ] **Chapter skip** — [chapterskip](https://github.com/po5/chapterskip) or [SmartSkip](https://github.com/Eisa01/mpv-scripts/#smartskip). Auto-skip intros/outros/credits by chapter name. Useful for TV series binging. Requires chapters in media files (MKV chapter metadata).
- [ ] **Refresh rate matching** — [mpv-kscreen-doctor](https://gitlab.com/smaniottonicola/mpv-kscreen-doctor) or similar Wayland-compatible solution. Auto-match display refresh rate to video framerate (24Hz for 24fps film). Eliminates judder.
- [ ] **MPRIS** — [mpv-mpris](https://github.com/hoyon/mpv-mpris). Standard Linux media key support (play/pause/next/prev). MPV state changes from MPRIS flow through our existing IPC property observers, so watch progress tracking remains intact.

Configurations
- [ ] Don't visualize cache

## TMDB Confidence Scorer: Same-Title Disambiguation

**Problem:** When two shows share an identical title (e.g., "Sample Show One" 2001 vs "Sample Show One" 2026 reboot), both receive a confidence score of 1.0. `Enum.max_by` silently picks whichever TMDB returns first in its search results. There is no tiebreaker logic.

**Real-world impact:** The entire Sample Show One library (8 seasons, 161 files) was ingested against the wrong TMDB ID — the 2026 reboot (ID 295778) instead of the classic 2001 show (ID 4556).

**Current mitigation:** When multiple TMDB results tie at the best confidence score, the Search stage now forces `:needs_review` instead of auto-approving. All tied candidates are included in `payload.candidates` for the review UI.

### Ideas for Further Refinement

- **Prefer older `first_air_date` on ties.** When scores are equal, break ties by preferring the show with the earlier premiere date. Libraries are far more likely to contain established shows than brand-new reboots.
- **Season count validation.** If the library already has files spanning 8 seasons, a TMDB result with only 1 season is a poor match regardless of title score. Cross-reference the number of season directories against `number_of_seasons` from the TMDB detail response.
