
# High Definition x264 and Ultra High Definition x265 Standards

> Source: https://scenerules.org/t.html?id=2020_X265.nfo


Revision 5.0 - 2020-04-15
Compliance mandatory as of 2020-05-11 00:00:00 UTC.

---

## SECTION 1: RETAIL SOURCES

**1.1** Retail sources = studio-distributed content via legitimate retail discs

**1.1.1** Allowed formats: Blu-ray, Ultra HD Blu-ray, HD DVD

**1.1.2-1.1.4** Tagging requirements:
- Blu-ray -> `BluRay` tag
- Ultra HD Blu-ray -> `UHD.BluRay` tag
- HD DVD -> `HDDVD` tag

**1.1.5** Music discs tagged as `MBluRay` or `UHD.MBluRay`
- Must comply with directory format 18.4.7
- Exempt from rules 8.14, 10.2, 18.5.7
- Only musical performances/events (not documentaries with live footage)

**1.1.5.3** `PURE` tag: audio releases only, source resolution only
- Example: 1080p source cannot release as 720p

---

## SECTION 2: NON-RETAIL SOURCES

**2.1** Non-retail = content not distributed via retail (cam, bootleg, workprint, screener)

**2.2** Visual/audible watermarks must be mentioned in NFO

**2.3** Non-retail exempt from:
- Rule 15 (proof not required)
- Rule 3.7 (non-critical footage removal permitted)
- Rule 12.5 (watermark concealment allowed)

**2.4** Non-retail elements require appropriate tag (e.g., `LINE`)

---

## SECTION 3: VIDEO

**3.1** No transcoding of transcoded/lossy material

**3.2** Single video track only

**3.3** Technical flaws prohibited:
- Sync issues, interlacing, lack IVTC, bad aspect ratio, invalid resolution, unrelated footage, warnings, glitches not in source, under/over-crop

**3.4** No dupes based on source type or disc format

**3.5** 3D sources: left/right-eye cannot be used for 2D release
- Exceptions: exclusive 3D releases with no 2D planned; or when 4.7.1 applies

**3.6** Single features: no multi-file splits
- **3.6.1** Credits spanning multiple discs = single release
- **3.6.2** Multiple episodes in single file with clear delineation = split into individual releases

**3.7** Non-feature footage (credits, intros, text) must not be removed/encoded separately
- **3.7.1** Interlaced non-feature in progressive feature: may leave interlaced OR deinterlace only that footage

**3.8** Unrelated footage must be removed (warnings, worksheets, test screens, piracy notices)

**3.9** English features: no foreign overlays for relevant on-screen information
- **3.9.1** Relevant = location titles, hardcoded subtitles, introduction text, plot-essential info
- **3.9.2** Non-relevant = opening credits, title, closing credits
- **3.9.3** English subtitles for relevant info = must include as forced track (10.2)

**3.10** Multiple retail video sources allowed, must not encode separately. Note all sources in NFO.

---

## SECTION 4: RESOLUTION & ASPECT RATIO

**4.1** 720p = max 1280x720
- **4.1.1** AR >= 1.78:1 -> width = 1280px (e.g., 2.40:1 -> 1280x534)
- **4.1.2** AR <= 1.78:1 -> height = 720px (e.g., 1.33:1 -> 960x720)

**4.2** 1080p = max 1920x1080

**4.3** 2160p = max 3840x2160

**4.4** Resolution must be mod2 (divisible by 2)

**4.5** No upscaling allowed
- **4.5.1** 1080p from 1080p/2160p from 2160p = crop only, no resize
- **4.5.2** Cropping allowed vertically/horizontally = resolution may fall below max (e.g., 1916x1072 acceptable for 1080p)
- **4.5.3** Source below 1080p/2160p minimum -> resize down to 720p/1080p + include source sample

**4.6** 3D only at 1080p or 2160p

**4.7** No dupes based on resolution
- **4.7.1** AR difference >=5% = NOT a dupe; tag as `WS`, `FS`, or `OM` (not `PROPER`); original not nuked
- **4.7.1.1** AR calculation provided

**4.8** Crop all black borders and non-feature content
- **4.8.1** Includes black/colored borders, duplicate/dirty lines/pixels
- **4.8.2** Faded edges: optional to retain (group discretion); retention != technical flaw
- **4.8.3** Varying AR throughout feature -> crop to widest frame (disregard studio logos/credits)
- **4.8.4** Varying crop between sources != technical flaw; cannot proper

**4.9** Over/under-crop max 1 pixel per side; >1 pixel = technical flaw

**4.10** Resolution within 0.2% of original aspect ratio
- **4.10.1** Calculate original AR from source after cropping only
- **4.10.2** Bad mastering AR -> source sample + comparison screenshot required

**4.11-4.15** Aspect ratio formulas:
- SAR = (PixelHeight / PixelWidth) / (DARHeight / DARWidth)
- DAR = (PixelWidth x DARWidth) / (PixelHeight x DARHeight)
- Display resolution: DisplayWidth = PixelWidth x (SARWidth / SARHeight)
- AR error: AR Error % = [(Original AR - Release AR) / Original AR] x 100
- Target resolution for mod2: TargetHeight = TargetWidth / [(SourceWidth - CropLR) / (SourceHeight - CropTB)]

---

## SECTION 5: FILTERS

**5.1** Apply IVTC, de-interlacing, or decimation as required

**5.2** Smart deinterlacers: QTGMC (preset slow+) or Nnedi3 only

**5.3** Field matching: TIVTC or Decomb only

**5.4** Sharp resizers: Spline36Resize, Spline64Resize, or BlackmanResize only

**5.5** Frame-accurate input plugins only (DGIndex, DGDecNV, LSMASHSource); no DirectShowSource

**5.6** No destructive/effects filters (RemoveGrain, GrainFactory3, MedianBlur, FineSharp)

**5.7** Optional recommended methods:
- **5.7.1** Overlay technique for non-mod2 opposing sides
- **5.7.2** SelectRangeEvery() for CRF testing
- **5.7.3** Selective debanding with f3kdb (high caution required)

---

## SECTION 6: FRAMERATE

**6.1** Constant frame rate (CFR) required; VFR not allowed

**6.2** No dupes based on framerate; use `INTERNAL` tag

**6.3** Constant dupe sequences must be decimated

**6.4** Hybrid sources (varying fps): IVTC discretionary; NFO must explain decision
- **6.4.1** If IVTC/decimation doesn't lose unique frames = not applying = technical flaw

**6.5** Native vs. converted framerates:
- **6.5.1** NTSC content = native NTSC
- **6.5.2** PAL content = native PAL
- **6.5.3** NTSC mastered in PAL = converted
- **6.5.4** PAL mastered in NTSC = converted

**6.6** Converted video must restore to original framerate
- **6.6.1** Includes ghosted, blended, duplicate frames
- **6.6.2** Speed-up/slow-down NTSC<->PAL != converted video
- **6.6.3** Successful restoration without artifacts -> no `CONVERT` tag
- **6.6.4** Cannot restore or causes artifacts -> use `CONVERT` tag

**6.7** True 50/59.940 fps released at 50/59.940 fps; true 25/29.970 fps at 50/59.940 = technical flaw
- **6.7.1** Mixed 25/29.970 and true 50/59.940 -> use main feature fps
- **6.7.2** Rare: 25/50 fps -> restore to 23.976 or 29.97 fps
- **6.7.3** Rare: 29.97/59.940 fps -> restore to 25 fps

---

## SECTION 7: VIDEO CODEC

**7.1** Encoding requirements by resolution/HDR:
- **7.1.1** x265 10-bit H.265/HEVC for: 720p/1080p HDR, 2160p SDR/HDR
- **7.1.2** x264 8-bit H.264/AVC for: 720p/1080p SDR
- **7.1.3** Custom builds (tMod, kMod) allowed; must be based on current codebase

**7.2** x264/x265 headers remain intact; no modification/removal

**7.3** Encoder version: max 60-day grace period before mandatory update
- **7.3.1** x264 reference: https://code.videolan.org/videolan/x264/tree/stable
- **7.3.2** x265 reference: https://bitbucket.org/multicoreware/x265/wiki/Home
- **7.3.3** Grace period applies at pre-time, not encode date
- **7.3.4** Grace applies only to immediately preceding revision; doesn't reset for older revisions

**7.4** No segmented encoding

**7.5** Constant Rate Factor (--crf) required
- **7.5.1** Decimal values allowed
- **7.5.2** Recommended starting CRF: 16 or 14 (highly compressible) for 2160p; 17 for 720p/1080p

**7.6** Increment CRF by 1 or 0.1 while encoded bitrate exceeds X% of source bitrate:
- **7.6.1** 30% for 720p
- **7.6.2** 60% for 1080p
- **7.6.3** 70% for 2160p

**7.7** 2-pass accepted for all resolutions, extreme cases only (not primary replacement)
- **7.7.1** NFO must provide detailed evidence of visual/bitrate/file-size advantage; specific scene timestamps + proof samples required
- **7.7.2** CRF >24 = consider 2-pass
- **7.7.3** 2-pass must follow 7.6 percentages

**7.8** Exceeding 7.6 percentages allowed with detailed NFO justification

**7.9** Unreasonably high CRF or low 2-pass bitrates without justification = technical flaw

**7.10** Encoded video bitrate <= source video bitrate
- **7.10.1** Video bitrate only (not muxed total)
- **7.10.2** CRF calculation algorithm provided for excessive bitrate cases

**7.11** Settings >= x264 preset "slower" or x265 preset "slow"

**7.12** Level requirements:
- **7.12.1** 720p = 4.1
- **7.12.2** 1080p = 4.1; 1080p >30fps = 4.2
- **7.12.3** 2160p = 5.1; 2160p >30fps = 5.2

**7.13** No custom matrices

**7.14** Zones (--zones) sparse use only; NFO must justify each with proof samples

**7.15** No GPU acceleration (--opencl, NVENC)

**7.16** Optional tuning: 'film', 'grain', or 'animation' only

**7.17** Recommended tuning settings per source:
- **7.17.1** Complex video -> --preset veryslow encouraged
- **7.17.2** --aq-mode 3 --aq-strength: 0.5-0.7 grainy; 0.6-0.9 digital; 0.9-1.1 animation
- **7.17.3** --psy-rd: 0.8-1.2 films; 0.5-0.8 animation
- **7.17.4** --deblock: -3:-3 films; 1:1 animation

**7.18** Sample Aspect Ratio (--sar) = '1:1' (square)

**7.19** Deblocking (--no-deblock) not allowed

**7.20** Framerate passed to encoder; keyframe interval (--keyint) and min GOP (--min-keyint) auto-set; no manual changes

**7.21** Color space = 4:2:0

**7.22** Color matrix (--colormatrix) optional = 'bt709' for SDR; not required

**7.23** x265 specifics:
- **7.23.1** Range, color primaries, transfer, color matrix, chroma location = match source or omit if undefined
- **7.23.2** Ultra-HD Bluray support (--uhd-bd) not allowed
- **7.23.3** High tier, repeat headers, AUD, HRD = enabled
- **7.23.4** HDR encodes:
  - **7.23.4.1** --hdr10 and --hdr10-opt enabled
  - **7.23.4.2** Master Display and Max CL = match source or omit if undefined; extract from concatenated source

**7.24** No tone-mapping (HDR<->SDR, DV<->SDR, HDR10Plus<->SDR); use `INTERNAL` tag

**7.25** HDR/DV/HDR10Plus source resolution only (exceptions: 4.5.3)

**7.26** Suggested command lines:
- **7.26.1** x264: --preset slower --level ## --crf ##
  - **7.26.1.1** Optional: --no-mbtree --no-fast-pskip --no-dct-decimate
- **7.26.2** x265: --high-tier --repeat-headers --aud --hrd --preset slow --level-idc ## --crf ## --range ## --colorprim ## --transfer ## --colormatrix ## --chromaloc ##
  - **7.26.2.1** HDR append: --hdr10 --hdr10-opt --master-display ## --max-cll ##
  - **7.26.2.2** Optional: --no-cutree --no-open-gop --no-sao --pmode --aq-mode 4

---

## SECTION 8: AUDIO

**8.1** Lossless tracks: DTS:X, TrueHD Atmos, DTS-HD MA, TrueHD, LPCM

**8.2** Lossy tracks: DTS-HD HR, E-AC3, DTS-ES, DTS, AC3

**8.3** Audio track requirements:

**8.3.1** 1080p/2160p:
- **8.3.1.1** Highest quality lossless (preference order: 8.1)
- **8.3.1.2** If no lossless: highest quality lossy (preference order: 8.2)

**8.3.2** 720p:
- **8.3.2.1** AC3 or E-AC3 extracted core from lossless/lossy
- **8.3.2.2** Lossless priority; don't extract core from lossy if lossless exists
- **8.3.2.3** Extracted core <640 Kbps -> transcode new track to E-AC3/AC3 from source
- **8.3.2.4** Lossy track (non-AC3/E-AC3) -> transcode from source
- **8.3.2.5** Lossy AC3/E-AC3 only -> mux as-is

**8.3.3** All resolutions: FLAC for mono/stereo lossless + multi-channel LPCM (see 9.7)

**8.4** Sync must not drift during entire release

**8.5** Glitching/unrelated audio in any channel = technical flaw
- **8.5.1** Includes audible glitch, missing audio, pops, clicks, unintended gaps, missing dialogue, muted/muffled

**8.6** English release: single English dialogue track only
- **8.6.1** Exception: remastered/restored source (both tracks allowed; group discretion on primary)

**8.7** Non-English release: optional secondary dialogue track
- **8.7.1** Original audio + forced English subtitles required (10.2)
- **8.7.2** Secondary = different dialects/varieties of original OR English dub
- **8.7.3** Rare: third track possible (another dialect + English dub)

**8.8** Non-English dubbed-only releases -> tag `DUBBED`

**8.9** Commentary audio allowed (see 9.8)

**8.10** Single highest-quality audio track per format per resolution
- **8.10.1** Exception: embedded cores in lossless (broken out by muxers)

**8.11** Additional special audio allowed (isolated scores, original mixes, different narrators)

**8.12** Supplementary audio tracks: descriptive title field

**8.13** ISO 639 language code (MKVToolnix-supported)
- **8.13.1** Unsupported language -> use 'und'

**8.14** No dupes based on multiple audio tracks, format, narrators, or remastered audio; use `INTERNAL`

**8.15** Multiple retail audio sources allowed; note all sources in NFO

---

## SECTION 9: AUDIO CODEC

**9.1** No segmented encoding

**9.2** No transcoding required: keep original format (includes cores); mux as-is

**9.3** No resampling; preserve original format

**9.4** No gain/normalization; keep source levels

**9.5** Channels unchanged; keep same count/layout
- **9.5.1** Exception: commentary (9.8.2)
- **9.5.2** Exception: AC3 transcode (9.6.2)

**9.6** AC3 or E-AC3 when transcoding lossless/lossy
- **9.6.1** >=640 Kbps from higher bitrate source only; allowed methods:
  - Dolby Media Encoder
  - eac3to: -640
  - FFmpeg: -b:a 640k
- **9.6.2** Positional metadata (DTS:X, TrueHD Atmos) and channels >5.1 (7.1) = group discretion retention

**9.7** FLAC for mono/stereo lossless + multi-channel LPCM
- **9.7.1** Best compression: level 8
- **9.7.2** No replay-gain

**9.8** VBR AAC LC for commentary audio
- **9.8.1** Apple/QAAC, FDK-AAC, or Nero
- **9.8.2** >2 channels -> downmix to stereo
- **9.8.3** Quality-based VBR; no targeted/constrained VBR:
  - QAAC: --tvbr 82 --quality 2
  - FDK-AAC: --bitrate-mode 4 --profile 2
  - Nero: -q 0.4

---

## SECTION 10: SUBTITLES

**10.1** All PGS (.sup) from source must be included as-is
- **10.1.1** Forced subtitles for excluded dubbed tracks = group discretion

**10.2** Foreign dialogue/overlays -> separate SubRip (.srt) forced English track (forced + default)
- **10.2.1** Exception: hardcoded source subtitles for non-English dialogue
- **10.2.2** Exception: excessive positional subtitles (anime) -> PGS forced + default instead

**10.3** Forced SubRip free of technical flaws
- **10.3.1** Carefully OCR'd
- **10.3.2** Minor grammar/punctuation != flaw; correction recommended

**10.4** Subtitles from licensed web/HDTV or alternative retail disc allowed
- **10.4.1** Note source + specific tracks in NFO
- **10.4.2** Fan-made/custom != allowed

**10.5** Hardcoded source subtitles allowed (except non-English in English features)
- **10.5.1** Hardcoded throughout feature -> tag `SUBBED`
- **10.5.2** Subtitles in letterboxed matte only -> crop + OCR to SubRip
- **10.5.3** Subtitles overlay active video + matte -> crop to widest frame, apply equally

**10.6** Subtitles not subject to propers/nukes for technical flaws

**10.7** No dupes based on subtitles; use `INTERNAL`

---

## SECTION 11: SUBTITLE FORMAT

**11.1** Allowed: PGS (.sup) and SubRip (.srt)
- **11.1.1** PGS compression: zlib only
- **11.1.2** PGS no resize
- **11.1.3** SubRip: UTF-8 encoding
- **11.1.4** SubRip not in 3D releases

**11.2** Subtitle settings:
- **11.2.1** ISO 639 language code; unsupported = 'und'
- **11.2.2** Not default/forced unless specified (section 10)
- **11.2.3** Correct sync offset at muxing

**11.3** Descriptive title field recommended

**11.4** 3D releases: 3D subtitles only

**11.5** No burning subtitles to video

**11.6** No external 'Subs' directories

---

## SECTION 12: CONTAINER

**12.1** Container = Matroska (.mkv); MKVToolnix recommended
- **12.1.1** Custom muxing tools allowed if Matroska-compliant

**12.2** File streaming/playback from RAR = mandatory

**12.3** Matroska header compression = disabled

**12.4** Chapters mandatory when present on source
- **12.4.1** Names optional; auto-generated = English

**12.5** No watermarks, intros, outros, defacement

---

## SECTION 13: PACKAGING

**13.1** RAR, max 101 volumes (.rar to .r99)

**13.2** RAR3/v2.0 or RAR4/v2.9 only; RAR5 not allowed

**13.3** Archive sizes: positive integer multiples of 50,000,000 bytes
- **13.3.1** Min 10 volumes before next multiple

**13.4** Single SFV for primary archives

**13.5** Unique lowercase filenames with group tag

**13.6** Missing RAR(s)/SFV = technical flaw

**13.7** Corrupt RAR(s) = technical flaw

**13.8** No RAR compression/recovery records

**13.9** No encryption/password protection

**13.10** Single .mkv per archive set (exception: extras releases)

---

## SECTION 14: NFO

**14.1** Single NFO required; must include:
- **14.1.1** Movies: iMDB link
- **14.1.2** Series: TVmaze/TheTVDB link
- **14.1.3** Source video bitrate

**14.2** Optional (recommended): release name/group, date, runtime, resolution, AR, framerate, audio format, file size, archive info, subtitles list, CRF value

---

## SECTION 15: PROOF

**15.1** Proof required for every release
- **15.1.1** High-quality photograph of printed disc side (group name visible)
- **15.1.2** >=640x480px; disc details clear/legible
- **15.1.3** Minor redaction allowed
- **15.1.4** Photo of actual disc used
- **15.1.5** Cover scans/m2ts samples != required proof

**15.2** Separate 'Proof' directory (JPEG/PNG, unarchived)

**15.3** Multiple sources: proof for all

**15.4** Strip all EXIF data

**15.5** Missing proof = technical flaw; can proper
- **15.5.1** Proof fixes <= 24 hours after original pre
- **15.5.2** Fixes after proper or >24 hours = rejected

---

## SECTION 16: SAMPLES / SOURCE SAMPLES

**16.1** 50-70 second sample per release (separate 'Sample' dir, cut from final video, not from opening/closing)

**16.2** Source samples when validity questioned (48h window, 30s-5m, packed with SOURCE.SAMPLE tag)

---

## SECTION 17: TAGGING

**17.1** Source tags allowed:
`BLURAY, CAM, D-THEATER, DCP, HDDVD, MBLURAY, MUSE-LD, SCREENER, TELECINE, TELESYNC, UHD.BLURAY, UHD.MBLURAY, WORKPRINT`

**17.2** Additional tags allowed:
`ALTERNATIVE.CUT, BW, CHRONO, COLORIZED, CONVERT, DC, DIRFIX, DUBBED, DV, EXTENDED, EXTRAS, FS, HDR, HDR10Plus, INTERNAL, LINE, NFOFIX, OAR, OM, PROOFFIX, PROPER, PURE, RATED, READNFO, REAL, REMASTERED, REPACK, RERIP, RESTORED, SAMPLEFIX, SDR, SOURCE.SAMPLE, SUBBED, THEATRICAL, UNCENSORED, UNCUT, UNRATED, WS`

- **17.2.1** <VERSION/CUT TITLE> allowed when tag doesn't fit
- **17.2.2** Remastered/restored: 3+ comparison screenshots + source link

**17.3** Tag variations disallowed (READ.NFO != READNFO)

**17.4** `READNFO` used sparingly; not with PROPER/REPACK/RERIP

**17.5** Tags grouped, period-delimited

**17.6** Tags used once; order discretionary
- **17.6.1** Exception: `REAL` stacked

**17.7** `HDR` tag for SDR->HDR (or vice versa); not for original format releases

---

## SECTION 18: DIRECTORY FORMAT

**18.1** Acceptable characters: A-Z, a-z, 0-9, . _ -

**18.2** Single punctuation only; no consecutive

**18.3** No typos/spelling mistakes

**18.4** Directory format rules:

**18.4.1** Feature:
`Feature.Title.<YEAR>.<TAGS>.[LANGUAGE].<RESOLUTION>.<FORMAT>.<x264|x265>-GROUP`

**18.4.2** Weekly TV:
`Weekly.TV.Show.[COUNTRY_CODE].[YEAR].SXXEXX[Episode.Part].[Episode.Title].<TAGS>.[LANGUAGE].<RESOLUTION>.<FORMAT>.<x264|x265>-GROUP`

**18.4.3** Special:
`Weekly.TV.Show.Special.SXXE00.Special.Title.<TAGS>.[LANGUAGE].<RESOLUTION>.<FORMAT>.<x264|x265>-GROUP`

**18.4.4** Multi-Episode:
`Multiple.Episode.TV.Show.SXXEXX-EXX[Episode.Part].[Episode.Title].<TAGS>.[LANGUAGE].<RESOLUTION>.<FORMAT>.<x264|x265>-GROUP`

**18.4.5** Crossover:
`Cross.Over.TV.Show.One.SXXEXX[Episode.Part].[Episode.Title]_Show.Two.SXXEXX[Episode.Part].[Episode.Title].<TAGS>.[LANGUAGE].<RESOLUTION>.<FORMAT>.<x264|x265>-GROUP`

**18.4.6** Miniseries:
`Miniseries.Show.PartX.[Episode.Title].<TAGS>.[LANGUAGE].<RESOLUTION>.<FORMAT>.<x264|x265>-GROUP`

**18.4.7** Music:
`Musical.Performance.or.Event.<PERFORMANCE_YEAR>.<TAGS>.<RESOLUTION>.<FORMAT>.<x264|x265>-GROUP`

**18.4.8** Audio:
`Artist.Name.Recording.Name.<RECORDING_YEAR>.<TAGS>.<RESOLUTION>.PURE.<FORMAT>.<x264|x265>-GROUP`

**18.5** Named arguments <> = mandatory; [] = optional
- **18.5.1** Mini-series parts: >=1 digit (Part.1, Part.10)
- **18.5.2** Episode/season: >=2 digits (S01E99, S01E100, S101E01)
- **18.5.3** Episode part: alphanumeric (S02E01A/B)
- **18.5.4** No season for non-seasonal series (One.Piece.E01)
- **18.5.5** Episode title: optional
- **18.5.6** Tags: section 17 only
- **18.5.7** Language: mandatory non-English; English = no tag
  - **18.5.7.1** Full language name (FRENCH, RUSSIAN, GERMAN); no codes
- **18.5.8** Format: source type (BluRay, TELECINE, HDDVD)

**18.6** No ripping/encoding methods in dirname; use NFO

**18.7** Non-series: include production year

**18.8** Same-title, different countries: ISO 3166-1 alpha-2 code
- **18.8.1** UK shows: use "UK", not "GB"
- **18.8.2** Only successors, not originals

**18.9** Same title, same country, different start years: year of first season
- **18.9.1** Not required for earlier broadcast

**18.10** Same title, same country, different years: ISO code + year

**18.11** Hyphenated/punctuated names: follow title sequence/credits
- **18.11.1** No title card -> see 18.13.1
- **18.11.2** No seasonal titles
- **18.11.3** Non-standard chars -> period (M.A.S.H)

**18.12** Nomenclature consistent across show lifetime
- **18.12.1** Follow first release format
- **18.12.2** Extended content: primary name + EXTENDED tag
- **18.12.3** Cannot change format after second release
- **18.12.4** Official name change allowed; document in NFO
- **18.12.5** Seasonal name changes ignored
- **18.12.6** Deviations need NFO evidence

**18.13** User services (TVmaze, TheTVDB) = guide only
- **18.13.1** Priority: official website -> broadcaster -> network guide
- **18.13.2** Inconsistent sources -> use established numbering

---

## SECTION 19: FIXES

**19.1** Allowed fixes: DIRFIX, NFOFIX, PROOFFIX, SAMPLEFIX

**19.2** Other fixes disallowed (RARFIX, SFVFIX, SUBFIX)

**19.3** All fixes require NFO

**19.4** No proper for fixable issues (except proof; see 15.5.1)

**19.5** Season-wide DIRFIX allowed

---

## SECTION 20: DUPES

**20.1** All HD formats equal quality; dupe each other
- **20.1.1** Exception: different version/framing tags

**20.2** Native fps != dupe converted fps

**20.3** Converted fps dupes native fps

**20.4** Retail != dupe non-retail

**20.5** Non-retail dupes retail

**20.6** Muxed subtitles != dupe hardcoded

**20.7** Hardcoded (SUBBED) dupes muxed

**20.8** HDR after SDR (or vice versa) != dupe

**20.9** Non-foreign English != dupe foreign-tagged

---

## SECTION 21: PROPERS / REPACKS / RE-RIPS

**21.1** Detailed NFO reasons required
- **21.1.1** Clear timestamps and specifics
- **21.1.2** Non-global nuke: sample demonstrating flaw required

**21.2** Propers: technical flaws only; no qualitative propers (use INTERNAL)

**21.3** Audio/visual glitches: proper allowed
- **21.3.1** Mastering glitches: no nuke until valid replacement

**21.4** Ripping/encoding issues: use RERIP

**21.5** Packing/muxing issues: use REPACK

---

## SECTION 22: INTERNALS

**22.1** Internal releases follow all rules except encoding specifics and experimental codecs

**22.2** NFO must mention exemptions; can nuke if not mentioned

**22.3** DIRFIX.INTERNAL disallowed

---

## SECTION 23: RULESET SPECIFICS

**23.1** This ruleset = ONLY official for HD/UHD retail; supersedes all previous
- **23.1.1** Former rulesets/codecs: nuke defunct
- **23.1.2** Naming standards: take effect when current season ends
- **23.1.3** Not retroactive

**23.2** Keyword definitions:
- Must = explicit, compulsory
- Should = suggestion
- Can/may = optional
- e.g. = common examples (not exhaustive)
- i.e. = only examples (exhaustive)

---

## SECTION 24: NOTES

**24.1** CRF = primary method; 2-pass for rare extreme cases only

**24.2** Dolby Vision (DV) + HDR10Plus = out of scope; INTERNAL tag only
- **24.2.1** DV encodes: --dolby-vision-profile + --dolby-vision-rpu match source
  - DV enhancement layer on HDR/HDR10Plus encode allowed
  - MP4 allowed for DV (Matroska lacks DV support)
- **24.2.2** HDR10Plus: --dhdr10-info metadata match source; --dhdr10-opt enabled
- **24.2.3** Metadata from concatenated source
- **24.2.4** DV/HDR10Plus exempt from cropping rules; uncropped only
- **24.2.5** Future provisions for when widespread support + 3mo passed

**24.3** Remuxes: subject to rules 12-24 until dedicated ruleset
- **24.3.1** Include all subtitle + audio tracks
- **24.3.2** Mux as-is; no modification
- **24.3.4** Remux tagging: H265 (not X265), H264 (not X264)

---

## SIGNATORIES

**Signed (85 Groups):**
aAF, AMIABLE, ANiHLS, ARCHiViST, BALKAN, BARGAiN, BATV, BEDLAM, BiPOLAR, BLOW, BRMP, CADAVER, CAPRiCORN, Chakra, CiNEFiLE, CONDITION, Counterfeit, CREEPSHOW, DAA, DEATH, DEFLATE, DEPTH, DEV0, DoNE, EiDER, ELBOWDOWN, EMERALD, Felony, FLAME, FUTURiSTiC, GeTiT, GHOULS, GiMCHi, GreenBlade, GxP, HAiDEAF, HAiKU, HDEX, HFPA, IAMABLE, IcHoR, iNGOT, JRP, KYR, LATENCY, LiBRARiANS, LiQUiD, LOUNGE, MBLURAYFANS, MUSiCBD4U, NODLABS, OUIJA, PAST, PHASE, PRESENT, PSYCHD, PURELiQUiD, REACTOR, RedBlade, REGRET, Replica, REWARD, SADPANDA, SAPHiRE, SCOTLUHD, SECTOR7, SH0W, SHORTBREHD, SiNNERS, SNOW, SPECTACLE, SPOOKS, TAXES, TOPAZ, TREBLE, TURBO, URANiME, USURY, ViRGO, W4F, WEST, WhiteRhino, WUTANG, YELLOWBiRD, YOL0W

**Refused (8 Groups):**
AAA, AAAUHD, DODELIJK, GUACAMOLE, KWANGMYONG, MAYHEM, TURMOiL, WATCHABLE

---

## REVISION HISTORY

- 2007-04-28: High.Def.x264.movie.standards.rls.1
- 2007-07-05: Revision 2
- 2008-10-13: Revision 3.0
- 2008-12-20: Revision 3.1
- 2009-01-27: Revision 3.1 Addendum 1
- 2011-01-29: Revision 4.0
- 2020-04-15: Revision 5.0 (total rewrite; CRF primary; UHD/x265 supported)
