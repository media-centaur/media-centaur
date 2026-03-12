---
title: "The 720p TV x264 Releasing Standards 2016"
source_url: "https://scenerules.org/html/tvx2642k16.html"
date_accessed: "2026-03-12"
category: "scene-standards"
document_id: "tvx2642k16"
effective_date: "2016-04-10"
---

# The 720p TV x264 Releasing Standards 2016

Mandatory compliance date: 2016-04-10 00:00:00 UTC

---

## SECTION 1: HDTV SOURCES

**1.1** HDTV defined as high definition natively recorded transport stream
**1.2** HDTV sources must not be upscaled
**1.3** Providers downscaling 1080i to 720p (e.g., BellTV) not allowed

---

## SECTION 2: AHDTV SOURCES

**2.1** Analogue HDTV: high definition captured from analog output of set-top box
**2.2** Captures at native broadcast format required
**2.2.1** Devices unable to output native format must restore to original framerate
**2.2.2** Single dupe frames or blended/ghost frames considered technical flaw

---

## SECTION 3: HR.PDTV SOURCES

**3.1** High-Resolution PDTV: non-HD content upscaled and broadcasted on HD channel
**3.1.1** Windowboxed content lacks sufficient resolution; not allowed
**3.2** Crop and resize to maximum resolution:
- **3.2.1** 960x720 for aspect ratios < 1.78:1
- **3.2.2** 960x540 for aspect ratios >= 1.78:1

---

## SECTION 4: CODEC

**4.1** Video must be H.264/MPEG-4 AVC encoded with x264 8-bit
**4.1.1** Custom x264 builds (x264-tMod, x264-kMod) allowed if based on x264 codebase
**4.2** x264 headers must remain intact, unmodified
**4.3** x264 must be current with 60-day grace period maximum
**4.3.1** Official x264 git repository is sole reference
**4.3.2** Grace period applies at pre time, not encoded date
**4.3.3** Grace period non-cumulative; applies only to preceding revision
**4.4** Constant Rate Factor (CRF) must be used
**4.4.1** CRF values: minimum 18, maximum 23
**4.4.2** Justification required in NFO for non-standard CRF
**4.4.2.1** Groups not required to follow other groups' non-standard CRF
**4.4.2.2** Bitrate exceeding 5000kb/s suggests higher CRF value
**4.5** Standard CRF values by compressibility:
- High (18-19): Scripted, Talk Shows, Animation, Stand-Up
- Medium (20-21): Documentary, Reality, Variety, Poker
- Low (22-23): Sports, Awards, Live Events

**4.6** Settings cannot drop below preset 'slow'
**4.7** Level must be '4.1'
**4.8** Colour matrix optionally 'bt709'
**4.9** Colour space must be 'i420' (4:2:0)
**4.10** Sample aspect ratio must be '1:1' (square)
**4.11** Deblocking required; values at group discretion
**4.12** Keyframe interval: minimum 200, maximum 300
**4.12.1** Recommended: 10x framerate (Film=240, PAL=250, NTSC=300)
**4.12.2** 50/60 FPS content: maximum keyframe 200-600
**4.13** Minimum GOP length: 30 or less
**4.13.1** Recommended: 1x framerate (Film=24, PAL=25, NTSC=30)
**4.13.2** 50/60 FPS content: 60 or less for minimum GOP
**4.14** Custom matrices not allowed
**4.15** Zones not allowed
**4.16** x264 parameters must not vary within release
**4.17** Optional tuning: 'film', 'grain', or 'animation'
**4.18** Suggested command: `x264 --crf ## --preset slow --level 4.1 --output out.mkv in.avs`

---

## SECTION 5: VIDEO / RESOLUTION

**5.1** Resolution must be mod 2
**5.2** Upscaling not allowed
**5.3** Adding borders not allowed
**5.4** Multiple video tracks not allowed
**5.5** English titles with foreign overlays (locations, on-screen text) not allowed; use INTERNAL
**5.5.1** Exception: opening titles/credits exempt
**5.6** Non-English titles with hardcoded English subtitles tagged SUBBED
**5.6.1** English titles with hardcoded English subtitles for English scenes tagged SUBBED
**5.6.2** English titles with hardcoded non-English subtitles not allowed; use INTERNAL
**5.6.3** Creator-added hardcoded subtitles exempt (alien hardsubs, drunk talk, muffled mic)
**5.7** Resolution-based dupes not allowed
**5.7.1** Exception: different aspect ratio releases use WS/OM tags, not PROPER
**5.7.2** >=20 pixels additional on any side not considered dupe; tag WS/OM, not PROPER
**5.8** Black borders and artifacts (coloured borders, duplicate lines, dirty pixels, tickers) must be cropped
**5.8.1** Faded edge retention/removal at group discretion; not a flaw
**5.8.1.1** Faded edges: pixel line similar to parallel frame pixels
**5.8.2** Varying aspect ratios: crop to most common frame size
**5.8.3** Letterboxed sources with hardcoded subtitles in borders: discretionary crop
**5.8.3.1** Cropping subtitles allowed only if unnecessary; partial removal is flaw
**5.8.4** Over/under cropping: maximum 1px per side (>1px = technical flaw)
**5.9** 720p = maximum 1280x720 display resolution
**5.9.1** 720i/720p sources: crop as needed, no resize
**5.9.2** 1080i/1080p sources: crop and resize to 1280 width and/or 720 height
**5.10** Resized video within 0.5% of original aspect ratio; includes mathematical formulas for calculation

---

## SECTION 6: FILTERS

**6.1** IVTC or deinterlacing applied as required
**6.2** Smart deinterlacers only: Yadif, QTGMC
**6.2.1** FieldDeinterlace prohibited
**6.3** Accurate field matching for IVTC: TIVTC, Decomb
**6.3.1** MEncoder, MJPEG tools, libav, libavcodec, FFmpeg IVTC prohibited
**6.3.2** Deinterlacers not used as IVTC method
**6.4** Sharp resizers only: Spline36Resize, BlackmanResize, LanczosResize/Lanczos4Resize
**6.4.1** Simple resizers (Bicubic, PointResize, Simple) prohibited

---

## SECTION 7: FRAMERATE

**7.1** Constant frame rate (CFR) required
**7.1.1** Variable frame rate (VFR) prohibited
**7.2** True 50/60 FPS released at 50/60 FPS; true 25/30 FPS at 50/60 FPS prohibited
**7.2.1** Deinterlacing with bobbing (QTGMC, Yadif mode=1) required for double-framerating 25i/30i
**7.2.2** Varying framerates: use main feature framerate (studio for talk shows, game coverage for sports)
**7.2.3** Rare: 25/50 FPS restored to 24/30 FPS
**7.2.4** Rare: 30/60 FPS restored to 25 FPS
**7.3** Hybrid sources with varying FPS: group discretion, reason required in NFO
**7.3.1** Majority with 30,000/1,001 FPS assumed higher framerate warranted; IVTC/decimation without frame loss is flaw
**7.4** Native/converted framerates definitions:
- **7.4.1** NTSC produced = NTSC native
- **7.4.2** PAL produced = PAL native
- **7.4.3** NTSC produced, PAL broadcast = converted
- **7.4.4** PAL produced, NTSC broadcast = converted
**7.5** Converted video with significant abnormalities tagged CONVERT
**7.5.1** Converted without abnormalities needs no tag, not nuked for conversion
**7.6** Framerate-based dupes not allowed; use INTERNAL

---

## SECTION 8: AUDIO

**8.1** Audio in original format
**8.1.1** Audio transcoding prohibited
**8.1.2** AAC LATM/LOAS (Freeview) converted to AAC ADTS without transcoding
**8.2** Multiple language audio tracks allowed
**8.2.1** Default track must be release language
**8.2.2** ISO 639 language codes required; 'und' for unsupported languages
**8.3** Non-English original language titles:
- **8.3.1** English dubbed as secondary track allowed
- **8.3.2** Dubbed-only releases tagged DUBBED
**8.4** Audio track/format-based dupes not allowed; use INTERNAL

---

## SECTION 9: GLITCHES / MISSING FOOTAGE

**9.1** Unavoidable audio/video issues (live broadcast, mastering) not nuked until valid proper/repack/rerip without flaw released
**9.2** Scrolling/alert messages (weather, amber alerts) >=30 seconds cumulative = technical flaw
**9.3** Video frame abnormalities (snipes, banner ads not fading) from broken splicing = technical flaw
**9.4** Missing/repeated footage without dialogue loss: >=2 seconds = technical flaw
**9.4.1** Exception: on-screen text loss = technical flaw regardless of length
**9.4.2** Exception: minor flaws throughout majority = excessive = technical flaw
**9.5** Audio drift >=120ms at single point or total >=120ms = technical flaw
**9.6** Glitches in any audio channel = technical flaw
**9.6.1** Glitches: missing/repeated dialogue, unintelligible dialogue, bad channel mix, gaps, clicks/pops/muted/echoing/muffled

---

## SECTION 10: EDITING / ADJUSTMENTS

**10.1** Minor adjustments (duplicating/removing frames, channel count) for playback/sync allowed
**10.2** Multi-episode without clear delineation not split
**10.3** Previously-on footage optional but recommended
**10.4** Upcoming/teaser/next episode footage optional but recommended
**10.5** Credits included if containing unique content (bloopers, outtakes, dialogue, unique uninterrupted soundtrack, in memory message)
**10.5.1** End credits optional if no unique content; removal at group discretion
**10.5.2** Simulcast without unique credits cannot PROPER primary broadcast with unique credits; use EXTENDED
**10.5.3** Different broadcaster/re-broadcast with unique content: first release not PROPER'd; use EXTENDED
**10.5.3.1** Unique uninterrupted soundtrack only: use INTERNAL, not EXTENDED
**10.5.3.2** Including omitted unique credits recommended but not required
**10.6** Bumper segments (5-20 seconds) optional at group discretion
**10.6.1** Omitted bumpers in first release: secondary with bumpers tagged UNCUT
**10.6.2** When bumpers included:
- **10.6.2.1** All bumper segments must be flaw-free
- **10.6.2.2** All bumpers included; missing any = technical flaw
**10.6.3** Small show content segments (not preview/backstage) not counted as bumpers
**10.7** Unrelated video (commercials, rating cards, warnings) completely removed regardless of duration
**10.7.1** Content warnings retained/removed at discretion, except when creator-intended (must retain)
**10.7.1.1** Scripted/animation: creator-unintended warnings always removed
**10.7.1.2** Non-scripted/animation: after opening, warnings preceding segments removed
**10.7.2** Integrated sponsorship ads exempt
**10.7.3** Show transition cards: discretionary
**10.7.4** Opening/closing interleaves (HBO, "presents", production credits, "original series") discretionary except when containing show content
**10.8** Unrelated audio (alerts, commercials) completely removed regardless of duration
**10.8.1** Exception: broadcaster splice of unrelated audio to segment start without sync issues allowed

---

## SECTION 11: SUBTITLES

**11.1** English titles without foreign dialogue: subtitles optional but encouraged
**11.2** English titles with foreign dialogue require forced subtitle track
**11.2.1** Foreign dialogue subtitles set as forced; failure = technical flaw
**11.2.2** Hardcoded subtitles in source: separate forced track not required
**11.2.3** Primary English broadcaster (FOX, BBC) without hardcoded foreign dialogue subtitles: forced subtitles optional but recommended
**11.3** Non-English titles without hardcoded subtitles require English forced track for English release status
**11.4** Subtitles extracted from original source
**11.4.1** Fan-made/custom subtitles prohibited
**11.5** Adjustments permitted: timecode adjustment, grammar/spelling/punctuation fixes
**11.6** Subtitles muxed as text format: SubRip (.srt) or SubStation Alpha (.ssa/.ass)
**11.6.1** Subtitles not set default or forced unless otherwise specified
**11.6.2** ISO 639 language codes required; 'und' for unsupported
**11.7** External subtitles in 'Subs' directories prohibited
**11.8** Subtitle-based dupes not allowed; use INTERNAL

---

## SECTION 12: CONTAINER

**12.1** Container: Matroska (.mkv); MKVToolnix recommended
**12.1.1** Custom muxing tools allowed if output adheres to Matroska specs with identical demuxer compatibility
**12.2** File streaming/playback from RAR mandatory
**12.3** Matroska header compression prohibited
**12.4** Chapters allowed and recommended for long events
**12.5** Watermarks, intros, outros, defacement prohibited in any track

---

## SECTION 13: PACKAGING

**13.1** RAR packaging, maximum 101 volumes (.rar to .r99)
**13.2** RAR3/RARv2.0 or RAR4/v2.9 required; RAR5/RARv5.0 prohibited
**13.3** Permitted RAR sizes:
- **13.3.1** Positive integer multiples of 50,000,000 bytes
- **13.3.2** Minimum 10 volumes before next multiple
**13.4** SFV and NFO present
**13.5** RAR, SFV, Sample files: unique, lowercase filenames with group tag
**13.6** Missing RAR(s) or SFV on all sites = technical flaw
**13.7** Corrupt RAR(s) on extraction = technical flaw
**13.8** RAR compression and recovery records prohibited
**13.9** Encryption/password protection prohibited
**13.10** Single MKV per RAR; no multiple MKVs or other files

---

## SECTION 14: SAMPLES / SOURCE SAMPLES

**14.1** Single 50-70 second sample required
**14.2** Unique filenames in 'Sample' directory
**14.3** Samples cut from final video, not separately encoded
**14.4** Source validity questioned: release nuked within 24 hours requesting source sample with suspicion/reason stated
**14.4.1** Group has 24 hours from nuke to pre >=10 second source sample
**14.4.2** Requests may specify timecode for verification
**14.4.3** Source samples packed per section 13 with SOURCE.SAMPLE tag
**14.4.4** Insufficient proof or failure to provide: release remains nuked, can be PROPER'd
**14.4.5** Questionable source issues recommended to include unique named source sample(s) in 'Sample' directory

---

## SECTION 15: TAGGING

**15.1** Allowed tags: ALTERNATIVE.CUT, CONVERT, COLORIZED, DC, DIRFIX, DUBBED, EXTENDED, FINAL, INTERNAL, NFOFIX, OAR, OM, PPV, PROPER, REAL, REMASTERED, READNFO, REPACK, RERIP, SAMPLEFIX, SOURCE.SAMPLE, SUBBED, UNCENSORED, UNRATED, UNCUT, WEST.FEED, WS
**15.1.1** WEST.FEED: exclusive west coast airing version
**15.1.1.1** Tag WEST.FEED for exclusive west coast airing even if east feed unreleased
**15.2** Tag variations prohibited (e.g., READ.NFO, RNFO prohibited; must use READNFO)
**15.3** READNFO used sparingly at group discretion
**15.3.1** READNFO not combined with PROPER, REPACK, RERIP (tag redundant)
**15.4** Tags used once; order discretionary
**15.4.1** Exception: REAL tag stacked to differentiate multiple invalid releases
**15.5** Tags grouped, period-delimited, following directory format rule 16.4

---

## SECTION 16: DIRECTORY NAMING

**16.1** Acceptable characters: A-Z, a-z, 0-9, period, underscore, hyphen
**16.2** Single punctuation only; consecutive punctuation prohibited
**16.3** No typos/spelling mistakes
**16.4** Mandatory directory formats:
- **16.4.1** `Single.Episode.Special.YYYY.<TAGS>.[LANGUAGE].720p.<FORMAT>-GROUP`
- **16.4.2** `Weekly.TV.Show.SXXEXX[Episode.Part].[Episode.Title].<TAGS>.[LANGUAGE].720p.<FORMAT>.x264-GROUP`
- **16.4.3** `Weekly.TV.Show.Special.SXXE00.Special.Title.<TAGS>.[LANGUAGE].720p.<FORMAT>-GROUP`
- **16.4.4** `Multiple.Episode.TV.Show.SXXEXX-EXX[Episode.Part].[Episode.Title].<TAGS>.[LANGUAGE].720p.<FORMAT>.x264-GROUP`
- **16.4.5** `Miniseries.Show.Name.Part.X.[Episode.Title].<TAGS>.[LANGUAGE].720p.<FORMAT>.x264-GROUP`
- **16.4.6** `Daily.TV.Show.YYYY.MM.DD.[Guest.Name].<TAGS>.[LANGUAGE].720p.<FORMAT>.x264-GROUP`
- **16.4.7** `Daily.Sport.League.YYYY.MM.DD.Event.<TAGS>.[LANGUAGE].720p.<FORMAT>.x264-GROUP`
- **16.4.8** `Monthly.Competition.YYYY.MM.Event.<TAGS>.[LANGUAGE].720p.<FORMAT>.x264-GROUP`
- **16.4.9** `Yearly.Competition.YYYY.Event.<TAGS>.[LANGUAGE].720p.<FORMAT>.x264-GROUP`
- **16.4.10** `Sports.Match.YYYY[-YY].Event.Round.XX.[Team.vs.Team].<TAGS>.[LANGUAGE].720p.<FORMAT>.x264-GROUP`
- **16.4.11** `Sport.Tournament.YYYY.Event.[Team/Person.vs.Team/Person].<TAGS>.[LANGUAGE].720p.<FORMAT>.x264-GROUP`
- **16.4.12** `Country.YYYY.Event.<BROADCASTER>.FEED.<TAGS>.[LANGUAGE].720p.<FORMAT>.x264-GROUP`

**16.5** <> arguments mandatory; [] optional
**16.5.1** Mini-series parts: >=1 integer wide (Part.1, Part.10)
**16.5.2** Episode/seasonal: >=2 integers wide (S01E99, S01E100, S101E01)
**16.5.3** Episode parts: alphanumeric A-Z, a-z, 0-9 (S02E01A/B)
**16.5.4** Season omitted if no seasons and not mini-series (One.Piece.E01)
**16.5.5** Episode title/guest names optional
**16.5.6** Guest names in appearance order
**16.5.7** Non-English releases include language tag; English releases exclude
**16.5.7.1** Language tags: full name (FRENCH, RUSSIAN); abbreviations prohibited unless established (EE, SI, PL)
**16.5.8** Tags: permitted tags per section 15
**16.5.9** Format: video source (AHDTV, HDTV, HR.PDTV)
**16.5.9.1** 720p tag omitted when format is HR.PDTV
**16.6** No source/ripping/encoding method indication; use NFO for technical details
**16.7** Single-episode titles include production year
**16.8** Channel name inclusion prohibited
**16.9** Different show titles across countries include ISO 3166-1 alpha 2 country code
**16.9.1** UK shows use UK, not GB
**16.9.2** Rule applies to successor shows, not originals
**16.10** Same title, same country, different years: first season year in directory (not required for first broadcast)
**16.11** Same title, same country, different years: country code + first season year
**16.12** Hyphenated/punctuated show names follow title sequence/credits format (limited to acceptable characters)
**16.12.1** No title card: see rule 16.14.1
**16.12.2** Season-specific titles not used
**16.12.3** Ellipsis acronyms converted to periods (M.A.S.H from M*A*S*H)
**16.13** Nomenclature/numbering consistent across show lifetime
**16.13.1** Acronyms/secondary titles follow first release format consistently
**16.13.2** Shows with extended content variants use EXTENDED tag, not modified names
**16.13.3** Format cannot change after second release/episode
**16.13.4** Exception: official broadcaster/studio name change; change documented in first NFO with references
**16.13.5** Official name changes exclude seasonal renaming
**16.13.6** Deviations require evidence in NFO
**16.14** TVRage, TVMaze, TheTVDB not primary references; used as general guide
**16.14.1** Primary source order:
- 16.14.1.1 Official show website
- 16.14.1.2 Original broadcaster order/format
- 16.14.1.3 Network guide
**16.14.2** Inconsistent/missing official sources: use previously established numbering

---

## SECTION 17: FIXES

**17.1** Allowed fixes: DIRFIX, NFOFIX, SAMPLEFIX; other fixes prohibited
**17.2** All fixes require NFO stating which release fixed
**17.3** PROPER not released for errors fixable via above methods
**17.4** Multiple same-season releases needing DIRFIX: single DIRFIX per season allowed/recommended

---

## SECTION 18: DUPES

**18.1** Same-second releases: maximum +/-1 second variance not considered dupes
**18.1.1** Timestamps: whole integers, round half towards zero
**18.1.2** Earliest timestamp used for dupe consideration
**18.1.3** Technical flaw: same-second non-flawed release becomes final
**18.2** AHDTV dupes HDTV
**18.3** HDTV does not dupe AHDTV
**18.4** HR.PDTV dupes HDTV and AHDTV
**18.5** AHDTV/HDTV/HR.PDTV dupe equivalent Retail release
**18.5.1** Exception: aspect ratio exceeding Retail
**18.5.2** Exception: different version tags
**18.6** Hardcoded subtitled releases (SUBBED) dupe muxed-subtitle releases
**18.7** Muxed-subtitle releases do not dupe hardcoded releases
**18.8** Native video streams do not dupe converted streams
**18.9** Converted video streams dupe native streams
**18.10** Version variants do not dupe counterparts, except censored-after-uncensored and FS-after-WS
**18.11** Identical footage with different narrators in same language dupe each other; use INTERNAL
**18.12** Different broadcasters with alternate commentary/coverage do not dupe for worldwide special events

---

## SECTION 19: PROPERS / RERIPS / REPACKS

**19.1** Detailed reasons in NFO for all repacks, rerips, propers
**19.1.1** PROPER reasons: clear statement with timestamps/specifics; sample demonstrating flaw encouraged but not mandatory
**19.2** PROPER permitted only for technical flaw in original
**19.2.1** Optional content flaws: INTERNAL, not PROPER
**19.2.2** Time-compressed sources with blended/missing frames: cannot PROPER for bad IVTC
**19.2.3** Minor IVTC flaws from source compression, glitches, logos, ratings bugs, snipes, banner ads: not technically flawed
**19.2.3.1** Exception: excessive frame abnormalities throughout majority = technical flaw
**19.3** Qualitative PROPER not allowed; use INTERNAL

---

## SECTION 20: INTERNALS

**20.1** INTERNAL releases allowed for any reason
**20.2** Severe technical flaws mentioned in NFO
**20.3** INTERNAL releases nuked only for unmentioned technical flaws
**20.4** DIRFIX.INTERNAL to avoid nuke prohibited

---

## SECTION 21: RULESET SPECIFICS

**21.1** This ruleset is ONLY official for TV-X264, superseding all prior revisions/rulesets/precedents
**21.1.1** Former rulesets/codecs nuked "defunct.ruleset" or "defunct.codec"
**21.1.2** Naming standards take effect when current running season ends
**21.2** Foreign language tags replace 'English' with tagged language in sections 5, 8, 11
**21.2.1** Foreign tags represent release language
**21.2.1.1** Established compact tags allowed (PLDUB, SWESUB, SUBFRENCH, NLSUBBED)
**21.2.1.2** DUBBED tag omitted/included at group discretion
**21.2.1.3** Soft-subbed: primary audio must be tagged language
**21.2.1.4** Hard-subbed with non-tagged primary audio dupes SUBPACK
**21.2.2** Foreign language tags dupe only same foreign language tags
**21.3** Keyword definitions:
- Must: explicit, compulsory rule
- Should: suggestion, non-compulsory
- Can/may: optional, non-compulsory
- e.g.: common examples (not exhaustive)

---

## SIGNATORIES

**Signed (72 Groups):**
aAF, ALTEREGO, ALTiTV, AMB3R, AMBIT, ANGELiC, ASCENDANCE, AVS, AZR, BAJSKORV, BARGE, BATV, C4TV, CBFM, CCCAM, COMPETiTiON, COMPULSiON, CREED, CROOKS, CURIOSITY, D0NK, DEADPOOL, DHD, DiFFERENT, DIMENSION, DKiDS, DOCERE, EDUCATE, EMX, EXECUTION, FiHTV, FoV, FRiES, FRiSPARK, FUtV, HYBRiS, iDiB, iFH, iNGOT, KAFFEREP, KILLERS, KNiFESHARP, KYR, MiNDTHEGAP, MORiTZ, NORiTE, NSN, ORENJI, PANZeR, PRiNCE, ProPLTV, QCF, RCDiVX, RDVAS, REGRET, RiVER, SH0W, SKANK, SKGTV, SORNY, SQUEAK, SRiZ, TASTETV, TLA, TVBYEN, TViLLAGE, TvNORGE, UAV, WaLMaRT, WNN, YesTV, ZOMBiE

**Refused to Sign (3 Groups):**
BRISK, BWB, FLEET

---

## REVISION HISTORY

- 2007-05-08: First TV-X264 standards, 2-pass encoding
- 2008-04-17: Major rewrite, sizing/HR.PDTV
- 2011-06-15: CRF-based encoding replaces 2-pass
- 2011-08-07: Standard CRF values, expanded rules
- 2016-04-04: Total rewrite, number-based rule marking, all issues/loopholes addressed

## DEDICATION

Dedicated to Spatula (RIP 2010-11-22), maker of the first scene TV-X264 release: "The.Unit.S01E04.HD720p.x264-MiRAGETV"
