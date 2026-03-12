---
title: "The SD TV x264 Releasing Standards 2016"
source_url: "https://scenerules.org/html/sdtvx2642k16.html"
date_accessed: "2026-03-12"
category: "scene-standards"
document_id: "sdtvx2642k16"
effective_date: "2016-04-10"
---

# The SD TV x264 Releasing Standards 2016

Mandatory compliance date: 2016-04-10 00:00:00 UTC

---

## SECTION 1: HDTV Sources

**1.1** HDTV defined as "high definition natively recorded transport stream"
**1.2** HDTV sources must not be upscaled
**1.3** Providers downscaling 1080i to 720p (e.g., BellTV) are prohibited

---

## SECTION 2: PDTV & DSR Sources

**2.1** PDTV defined as "576i/576p natively recorded transport stream"
**2.2** DSR defined as "480i/480p natively recorded transport stream"

---

## SECTION 3: AHDTV & APDTV & ADSR Sources

**3.1** These are "captured streams from analog output" of set-top boxes
**3.2** Captures must occur at native broadcast format
**3.2.1** Unable devices must restore to original framerate
**3.2.2** Dupe frames or blended frames constitute technical flaws

---

## SECTION 4: Codec Requirements

**4.1** Video must use "H.264/MPEG-4 AVC encoded with x264 8-bit"
**4.1.1** Custom x264 builds allowed if based on x264 codebase
**4.2** x264 headers must remain intact, unmodified
**4.3** x264 must stay current with 60-day grace period maximum
**4.3.1** Official x264 git repository is sole reference
**4.3.2** Grace period applies at pre time, not encode date
**4.3.3** Grace period applies only to preceding revision, doesn't reset
**4.4** Constant Rate Factor (--crf) must be used
**4.4.1** CRF values restricted to 19-24 range
**4.4.2** Non-standard CRF requires NFO justification
**4.4.2.1** Groups not required to follow others' non-standard values
**4.4.2.2** CRF >1500kb/s bitrate suggests higher CRF values
**4.5** Standard CRF values by content type:
- High compressibility (19-20): Scripted, talk shows, animation, stand-up
- Medium (21-22): Documentary, reality, variety, poker
- Low (23-24): Sports, awards, live events
**4.6** Settings cannot fall below "preset 'slow'" specifications
**4.7** Level must be "3.1"
**4.8** Colour matrix (--colormatrix) must be set
**4.8.1** HDTV/AHDTV sources use "bt709"
**4.8.2** PDTV/APDTV/DSR/ADSR use source specification
**4.8.2.1** Use "undef" if source unspecified
**4.9** Colour space (--output-csp) must be "i420" (4:2:0)
**4.10** Sample aspect ratio (--sar) must be "1:1" (square)
**4.11** Deblocking (--deblock) required; values discretionary
**4.12** Keyframe interval (--keyint): 200-300 range minimum
**4.12.1** Recommendation: 10x framerate guideline
**4.12.2** 50/60 FPS content: 200-600 maximum range
**4.13** Minimum GOP (--minkeyint): 30 or less
**4.13.1** Recommendation: 1x framerate guideline
**4.13.2** 50/60 FPS content: 60 or less maximum
**4.14** Custom matrices prohibited
**4.15** Zones (--zones) prohibited
**4.16** x264 parameters must not vary within release
**4.17** Optional tuning (--tune): "film," "grain," or "animation" only
**4.18** Suggested command: `x264 --crf ## --preset slow --level 3.1 ...`

---

## SECTION 5: Video/Resolution

**5.1** Resolution must be mod 2
**5.2** Upscaling prohibited
**5.3** Adding borders prohibited
**5.4** Multiple video tracks prohibited
**5.5** English titles with unintended foreign overlays require INTERNAL tag
**5.5.1** Exception for opening titles/credits
**5.6** Non-English with hardcoded English requires SUBBED tag
**5.6.1** English with hardcoded subtitles in English scenes requires SUBBED
**5.6.2** English with hardcoded non-English for English scenes prohibited
**5.6.3** Creator-intended hardsubs exempt (aliens, muffled audio, etc.)
**5.7** Resolution-based dupes prohibited
**5.7.1** Exception for different aspect ratios (tag WS/OM, mention in NFO)
**5.7.2** 20+ pixel additions not considered dupes; tag WS/OM
**5.8** Black borders and artifacts must be cropped
**5.8.1** Faded edges retention discretionary, not a flaw
**5.8.2** Varying aspect ratios crop to most common frame size
**5.8.3** Letterboxed with hardcoded subtitles: crop or leave uncropped
**5.8.3.1** Cropping out subtitles allowed only if unnecessary
**5.8.4** Over/under-crop tolerance: 1px per side maximum
**5.9** HDTV/PDTV >720px width must resize to 720px
**5.10** PDTV maximum resolutions:
- **5.10.1** 705-720px width: 720x height
- **5.10.2** <=704px width: 704x528
**5.11** DSR maximum resolutions:
- **5.11.1** >720px width: 720x height
- **5.11.2** 641-720px width: 640x height
- **5.11.3** <=640px width: 640x480
**5.12** Aspect ratio tolerance: 0.5% maximum variance

---

## SECTION 6: Filters

**6.1** IVTC or deinterlacing required as needed
**6.2** Smart deinterlacers only (Yadif, QTGMC)
**6.2.1** FieldDeinterlace prohibited
**6.3** Accurate field matching filters only (TIVTC, Decomb)
**6.3.1** MEncoder, MJPEG, libav, libavcodec, FFmpeg IVTC prohibited
**6.3.2** Deinterlacers not used for IVTC
**6.4** Sharp resizers required (Spline36Resize, BlackmanResize, Lanczos)
**6.4.1** Simple resizers prohibited (Bicubic, PointResize)

---

## SECTION 7: Framerate

**7.1** Constant frame rate (CFR) required
**7.1.1** Variable frame rate (VFR) prohibited
**7.2** True 50/60 FPS released at 50/60; false doubling prohibited
**7.2.1** Failure to bob 25i/30i to 50/60 is technical flaw
**7.2.2** Varying framerates use main feature rate
**7.2.3** Rare: 25/50 FPS restored to 24/30 FPS
**7.2.4** Rare: 30/60 FPS restored to 25 FPS
**7.3** Hybrid sources discretionary; NFO must explain decision
**7.3.1** If majority warrants higher FPS without frame loss, IVTC failure is flaw
**7.4** Native vs. converted framerate definitions
**7.4.1** NTSC native to NTSC
**7.4.2** PAL native to PAL
**7.4.3** NTSC broadcast in PAL is converted
**7.4.4** PAL broadcast in NTSC is converted
**7.5** Converted with significant abnormalities requires CONVERT tag
**7.5.1** Converted without abnormalities don't require tag
**7.6** Framerate-based dupes prohibited; use INTERNAL

---

## SECTION 8: Audio

**8.1** Segmented encoding prohibited
**8.2** VBR AAC LC required
**8.2.1** Apple/QAAC, FDK-AAC, or Nero only
**8.2.1.1** FFmpeg, FAAC, MEncoder prohibited
**8.2.2** Quality-based VBR (not targeted/constrained)
**8.2.2.1** QAAC: "--tvbr 82 --quality 2"
**8.2.2.2** FDK-AAC: "--bitrate-mode 4 --profile 2"
**8.2.2.3** Nero: "-q 0.4"
**8.2.3** AAC normalized to maximum gain; complete 2-pass method required
**8.2.3.1** eac3to: "--normalize"
**8.2.3.2** sox: "--norm"
**8.2.3.3** QAAC: "--normalize"
**8.2.4** Strip existing normalization values (dialnorm)
**8.2.5** >2 channels down-mixed to stereo
**8.2.6** Audio not resampled; keep original format
**8.2.7** 2-channel VBR AAC LC from broadcaster may be retained
**8.2.7.1** AAC LATM/LOAS converted to ADTS without transcoding
**8.2.8** Suggested command line provided
**8.3** Multiple language audio tracks allowed
**8.3.1** Default track must be release language
**8.3.2** ISO 639 language codes required for secondary tracks
**8.4** Non-English titles may include English dub
**8.4.1** English dub allowed as secondary track
**8.4.2** Dub-only releases require DUBBED tag
**8.5** Audio-based dupes prohibited; use INTERNAL

---

## SECTION 9: Glitches/Missing Footage

**9.1** Unavoidable issues from live broadcast remain until proper released
**9.2** Station alerts >=30 seconds cumulative total = technical flaw
**9.3** Frame abnormalities from broken splicing = technical flaw
**9.4** Missing/repeated footage >=2 seconds = technical flaw
**9.4.1** Exception: on-screen text loss = flaw regardless of duration
**9.4.2** Exception: excessive glitches throughout = flaw
**9.5** Audio sync drift >=120ms single point or cumulative = technical flaw
**9.6** Channel glitches in any audio channel = technical flaw
**9.6.1** Glitches include missing/repeated dialogue, bad mix, clicks, gaps

---

## SECTION 10: Editing/Adjustments

**10.1** Minor adjustments allowed (frame duplication/removal for sync)
**10.2** Multi-episode without delineation must not split
**10.3** Previously-on footage optional but recommended
**10.4** Upcoming/teaser footage optional but recommended
**10.5** Credits with unique content must be included
**10.5.1** Plain credits optional; may be removed
**10.5.2** Simulcast without unique credits != proper over primary broadcaster; use EXTENDED
**10.5.3** Different broadcaster with unique content != proper; use EXTENDED
**10.5.3.1** Unique uninterrupted soundtrack only: use INTERNAL, not EXTENDED
**10.6** Bumper segments (5-20 sec preview) optional
**10.6.1** If omitted initially, secondary release with all bumpers tagged UNCUT allowed
**10.6.2** If included, all bumpers must be flawless and complete
**10.6.3** Small segments with show content != bumper segments
**10.7** Unrelated video (commercials, ratings) completely removed
**10.7.1** Content warnings discretionary except when creator-intended
**10.7.2** Integrated sponsorships exempt
**10.7.3** Show transition cards discretionary
**10.7.4** Opening/closing interleaves discretionary unless containing show content
**10.8** Unrelated audio completely removed
**10.8.1** Exception: broadcaster audio splice without sync issues

---

## SECTION 11: Subtitles

**11.1** Subtitles for English titles optional but encouraged
**11.2** English with foreign dialogue requires forced subtitle track
**11.2.1** Forced subtitles must be flagged correctly = flaw if not
**11.2.2** Hardcoded foreign subs in video: separate track not required
**11.2.3** Primarily English broadcaster without hardcodes: forced subs recommended but not required
**11.3** Non-English without hardcodes requires English forced track for "English release" designation
**11.4** Subtitles from original source only
**11.4.1** Fan-made/custom subtitles prohibited
**11.5** Adjustments/edits allowed (timecodes, grammar, spelling)
**11.6** Muxed as text format (SubRip .srt or SubStation Alpha .ssa/.ass)
**11.6.1** Not set as default or forced unless specified
**11.6.2** ISO 639 language codes required
**11.7** External subtitle directories prohibited
**11.8** Subtitle-based dupes prohibited; use INTERNAL

---

## SECTION 12: Container

**12.1** Container must be Matroska (.mkv)
**12.2** File streaming/playback from RAR mandatory
**12.3** Matroska header compression disabled
**12.4** Chapters allowed and recommended for long events
**12.5** No watermarks, intros, outros, or defacement in any track

---

## SECTION 13: Packaging

**13.1** RAR format, maximum 101 volumes (.rar to .r99)
**13.2** RAR3/v2.0 or RAR4/v2.9 only (not RAR5)
**13.3** Permitted RAR sizes:
- **13.3.1** 15,000,000 or 20,000,000 bytes only
- **13.3.2** Positive multiples of 50,000,000 bytes
- **13.3.3** Minimum 10 volumes at 50MB before stepping to larger multiples
**13.4** SFV and NFO required
**13.5** RAR, SFV, sample files: unique lowercase names with group tag
**13.6** Missing RAR(s) or SFV = technical flaw
**13.7** Corrupt RARs = technical flaw
**13.8** RAR compression/recovery records prohibited
**13.9** Encryption/password protection prohibited
**13.10** Single MKV per RAR; no multi-files

---

## SECTION 14: Samples

**14.1** Single 50-70 second sample required
**14.2** Unique filenames in "Sample" directory
**14.3** Cut from final video, not separately encoded
**14.4** Source validity question allows nuke within 24 hours
**14.4.1** Group has 24 hours to provide >=10 second source sample
**14.4.2** Requests may specify timecode verification
**14.4.3** Source samples packed per section 13, tagged SOURCE.SAMPLE

---

## SECTION 15: Tagging

**15.1** Allowed tags: ALTERNATIVE.CUT, CONVERT, COLORIZED, DC, DIRFIX, DUBBED, EXTENDED, FINAL, INTERNAL, NFOFIX, OAR, OM, PPV, PROPER, REAL, REMASTERED, READNFO, REPACK, RERIP, SAMPLEFIX, SOURCE.SAMPLE, SUBBED, UNCENSORED, UNRATED, UNCUT, WEST.FEED, WS
**15.1.1** WEST.FEED = exclusive west coast airing
**15.2** Tag variations prohibited (READ.NFO, RNFO disallowed)
**15.3** READNFO used sparingly
**15.3.1** READNFO not stacked with PROPER, REPACK, RERIP
**15.4** Tags used once; order discretionary
**15.4.1** Exception: REAL stacked to differentiate
**15.5** Tags grouped, period-delimited, follow directory format

---

## SECTION 16: Directory Naming

**16.1** Allowed characters: A-Z, a-z, 0-9, . _ -
**16.2** Single punctuation only; no consecutive punctuation
**16.3** No typos/spelling mistakes
**16.4** Mandatory directory format templates:
- **16.4.1** `Single.Episode.Special.YYYY.<TAGS>.[LANGUAGE].<FORMAT>-GROUP`
- **16.4.2** `Weekly.TV.Show.SXXEXX[Episode.Part].[Episode.Title].<TAGS>.[LANGUAGE].<FORMAT>.x264-GROUP`
- **16.4.3** `Weekly.TV.Show.Special.SXXE00.Special.Title.<TAGS>.[LANGUAGE].<FORMAT>-GROUP`
- **16.4.4** `Multiple.Episode.TV.Show.SXXEXX-EXX[Episode.Part].[Episode.Title].<TAGS>.[LANGUAGE].<FORMAT>.x264-GROUP`
- **16.4.5** `Miniseries.Show.Name.Part.X.[Episode.Title].<TAGS>.[LANGUAGE].<FORMAT>.x264-GROUP`
- **16.4.6** `Daily.TV.Show.YYYY.MM.DD.[Guest.Name].<TAGS>.[LANGUAGE].<FORMAT>.x264-GROUP`
- **16.4.7** `Daily.Sport.League.YYYY.MM.DD.Event.<TAGS>.[LANGUAGE].<FORMAT>.x264-GROUP`
- **16.4.8** `Monthly.Competition.YYYY.MM.Event.<TAGS>.[LANGUAGE].<FORMAT>.x264-GROUP`
- **16.4.9** `Yearly.Competition.YYYY.Event.<TAGS>.[LANGUAGE].<FORMAT>.x264-GROUP`
- **16.4.10** `Sports.Match.YYYY[-YY].Round.XX.Event.[Team.vs.Team].<TAGS>.[LANGUAGE].<FORMAT>.x264-GROUP`
- **16.4.11** `Sport.Tournament.YYYY.Event.[Team/Person.vs.Team/Person].<TAGS>.[LANGUAGE].<FORMAT>.x264-GROUP`
- **16.4.12** `Country.YYYY.Event.<BROADCASTER>.FEED.<TAGS>.[LANGUAGE].<FORMAT>.x264-GROUP`

**16.5** Format field values: AHDTV, HDTV, APDTV, PDTV, ADSR, DSR
**16.5.1-16.5.9** Same naming rules as 720p TV (see HD TV document)

**16.6** No source/ripping/encoding method indication
**16.7** Single-episode titles include production year
**16.8** Channel names prohibited
**16.9-16.14** Same naming disambiguation rules as 720p TV

---

## SECTION 17: Fixes

**17.1** Allowed fixes: DIRFIX, NFOFIX, SAMPLEFIX only
**17.2** All fixes require NFO stating which release fixed
**17.3** Proper not allowed for fixable errors

---

## SECTION 18: Dupes

**18.1** Same-second releases within +/-1 second variance not dupes
**18.2** AHDTV dupes HDTV
**18.3** HDTV doesn't dupe AHDTV
**18.4** PDTV/APDTV dupe HDTV/AHDTV
**18.5** PDTV doesn't dupe APDTV
**18.6** DSR/ADSR dupe HDTV/AHDTV/PDTV/APDTV
**18.7** DSR doesn't dupe ADSR
**18.8** AHDTV/HDTV/PDTV/APDTV/DSR/ADSR dupe Retail equivalent
**18.9** Hardcoded subtitled (SUBBED) dupes muxed subtitles
**18.10** Muxed subtitles don't dupe hardcoded
**18.11** Native video doesn't dupe converted
**18.12** Converted dupes native
**18.13** Version tags don't dupe counterparts except censored->uncensored and FS->WS
**18.14** Identical footage, different narrator (same language) dupes; use INTERNAL
**18.15** Alternate commentary/coverage from different broadcasters don't dupe

---

## SECTION 19: Propers/Rerips/Repacks

**19.1** Detailed NFO reasons required
**19.2** Propers only for technical flaws
**19.2.1** Optional content flaws use INTERNAL
**19.2.2** Time-compressed sources: no proper for IVTC issues
**19.2.3** Minor IVTC flaws not technically flawed
**19.3** Qualitative propers prohibited; use INTERNAL

---

## SECTION 20: Internals

**20.1** Internals allowed for any reason
**20.2** Severe technical flaws mentioned in NFO
**20.3** Internals nuked only for unmentioned flaws
**20.4** DIRFIX.INTERNAL to avoid nuke prohibited

---

## SECTION 21: Ruleset Specifics

**21.1** This ruleset = ONLY official standard; supersedes previous
**21.1.1** Former rulesets/codecs nuked as defunct
**21.1.2** Naming standards apply once current season ends
**21.2** Foreign language releases replace "English" with tagged language
**21.2.1** Compact tags allowed (PLDUB, SWESUB, SUBFRENCH, NLSUBBED)
**21.2.2** Foreign-tagged releases dupe only same foreign-tagged releases
**21.3** Keyword definitions: Must=mandatory, Should=suggestion, Can/may=optional

---

## SIGNATORIES

**Signed (54 Groups):**
aAF, ALTEREGO, AMB3R, AMBIT, AVS, AZR, BAJSKORV, BARGE, BATV, C4TV, CBFM, CCCAM, CREED, CROOKS, D0NK, DEADPOOL, DKiDS, DOCERE, EMX, FiHTV, FQM, FRiES, FRiSPARK, HYBRiS, iDiB, iFH, KILLERS, KYR, LOL, MiNDTHEGAP, MORiTZ, NORiTE, PANZeR, ProPLTV, QCF, RCDiVX, REGRET, RiVER, SH0W, SKANK, SKGTV, SORNY, SQUEAK, SRiZ, TASTETV, TLA, TVBYEN, TViLLAGE, TvNORGE, UAV, WaLMaRT, WNN, YesTV, ZOMBiE

**Refused to Sign (3 Groups):**
BRISK, BWB, FLEET

---

## REVISION HISTORY

- 2012-02-22: Initial standards with CRF encoding
- 2012-04-01: Enhanced rule coverage, additional signatories
- 2016-04-04: Complete rewrite, switched to number-based rules, MP4 removed for Matroska, stricter AAC encoding
