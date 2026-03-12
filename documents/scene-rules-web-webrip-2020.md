---
title: "WEB and WEBRip SD/HD x264 UHD x265 Releasing Standards v2.0"
source_url: "https://scenerules.org/t.html?id=2020_WDX_unformatted.nfo"
date_accessed: "2026-03-12"
category: "scene-standards"
document_id: "2020_WDX"
effective_date: "2020-05-20"
---

# THE.2020.WEB.AND.WEBRIP.SD.HD.X264.UHD.X265.RULESET.v2.0-WDX

High Definition x264/H264 and Ultra High Definition x265/H265 WEB and WEBRip Standards
Version 2.0 - 2020-05-13
Compliance optional until 2020-05-20 00:00:00 UTC; mandatory thereafter.

---

## SECTION 1: Untouched WEB.H264 / WEB.H265

**1.1** - Untouched releases = losslessly downloaded content (official or backdoor)
- **1.1.1** - Video must use H.264/MPEG-4 AVC or H.265/HEVC codec (exception in 1.5.1)

**1.2** - Source video and audio streams must remain unchanged

**1.3** - Tagging requirements: WEB.H264 or WEB.H265 based on header presence
- **1.3.1** - HEVC/H265 allowed only when source lacks H264 stream

**1.4** - Transcoding allowed only if files fail standards (last resort)
- **1.4.1** - Must follow transcoding standards (Section 3)
- **1.4.2** - Transcode from highest resolution/bitrate offered
- **1.4.2.1** - 720p/1080p and 1080p/2160p streams considered equal value (except DRM protection variances)
- **1.4.3** - Transcoding permitted for technical flaws (e.g., duplicate frame removal)
- **1.4.4** - Transcoding allowed when target resolution unavailable from lossless sources
- **1.4.5** - No transcoding to WEBRip if untouched file meets standards
- **1.4.5.1** - Video transcoding doesn't require audio transcoding; vice versa
- **1.4.5.1.1** - Exception: SD audio = untouched (rule 2.2) or transcoded from highest quality (rule 5.6.2)

**1.5** - Non-AVC/HEVC codecs must be transcoded (Section 3)
- **1.5.1** - Exception: VP9/AV1 allowed only when source lacks H264/H265
- **1.5.1.1** - Untouched rules apply to VP9/AV1
- **1.5.1.2** - No transcoding from VP9/AV1 except for technical flaw correction

**1.6** - SD definition: minimum 720 pixels horizontal (or <=720p specs per rule 8.2)
- **1.6.1** - Transcoding allowed when all sources below minimum (rule 1.4.4)
- **1.6.2** - Single-source files below minimum allowed with NFO explanation

**1.7** - Exceeding resolution specs allowed only for valid circumstance
- **1.7.1** - NFO must explain resolution overage

**1.8** - Must use highest available bitrate for resolution

**1.9** - Black borders not technical flaws; crop-only transcoding prohibited
- **1.9.1** - Container-level cropping forbidden
- **1.9.2** - Cropping applied when fixing other technical flaws

**1.10** - VFR allowed only if present in source
- **1.10.1** - CFR preferred when remuxing without playback issues
- **1.10.1.1** - Use MKVToolnix with '--fix-bitstream-timing-information'

**1.11** - Trimming unrelated footage via lossless keyframe intervals (MKVToolnix recommended)
- **1.11.1** - Single GOP transcoding allowed if lossless removal impossible (VideoRedo recommended)

**1.12** - Incorrect PAR/SAR must be fixed at container level using correct DAR (MKVToolnix)

**1.13** - Non-square SAR not technically flawed
- **1.13.1** - Square SAR sources preferred over non-square SAR equivalents
- **1.13.2** - Source upgrade from non-square to square SAR = technical flaw for initial release

---

## SECTION 2: Untouched Audio

**2.1** - Must use original audio track from source

**2.2** - SD releases maximum 2.0 channels
- **2.2.1** - Exception: only available track >2.0 channels (NFO explanation required)
- **2.2.2** - Prefer 2.0 when both 2.0 and 5.1 available
- **2.2.3** - Identical multi-codec audio = group discretion (smaller file recommended)

**2.3** - HD releases use highest available audio format/quality
- **2.3.1** - Quality hierarchy: positional metadata > channel count > codec > bitrate
  - Example: "576 Kbps 5.1 E-AC3 w/ Atmos > 640 Kbps 5.1 AC3 > 2.0 E-AC3"
- **2.3.2** - Use highest audio format from all resolutions if lesser format offered for larger resolutions
- **2.3.3** - Minor adjustments permitted if highest format causes technical flaws

---

## SECTION 3: Transcoded WEBRip.x264 / WEBRip.x265

**3.1** - Transcoded = captured or encoded to lesser quality (lossy)

**3.2** - Tag as WEBRip.x264/x265

**3.3** - Capture from highest resolution/bitrate
- **3.3.1** - No quality degradation throughout capture; bitrate drops = technical flaw
- **3.3.2** - Capture audio in highest format offered (channel count + bitrate)

**3.4** - Capture at native broadcast framerate
- **3.4.1** - Restore native format if device output limited
- **3.4.2** - Failed restoration to native framerate = technical flaw

**3.5** - Capture at native colour space (YUV/RGB); manual corrections toward source equivalence

**3.6** - Capture software/hardware introducing >2 pixels cropping per side = technical flaw

**3.7** - Final resolution maintains source aspect ratio (post-crop), mod2 compliance
- **3.7.1** - Crop all black borders to widest frame
- **3.7.2** - Match calculated source aspect ratio (rule 8.12)

**3.8** - NFO must state transcoding reason when from untouched source (rules 1.4.4, 1.4.5)
- **3.8.1** - Include flaw description when fixing technical issue (rule 1.4.3)

---

## SECTION 4: Transcoded Video Codec

**4.1** - Video encoding requirements:
- **4.1.1** - H.265/HEVC x265 10-bit: SD/720p/1080p HDR + 2160p SDR/HDR
- **4.1.2** - H.264/AVC x264 8-bit: SD/720p/1080p SDR
- **4.1.3** - Custom builds allowed (tMod, kMod) based on current codebase

**4.2** - x264/x265 headers intact; no modification/removal

**4.3** - Keep x264/x265 current (60-day grace period max)
- **4.3.1** - Official x264 git (stable branch) = reference
- **4.3.2** - Official x265 git = reference; 3rd-party builds acceptable until official support
- **4.3.3** - 60-day grace at pre-time, not encode date
- **4.3.4** - Grace applies only to preceding revision; doesn't reset prior grace periods

**4.4** - Segmented encoding forbidden

**4.5** - CRF (Constant Rate Factor) mandatory
- **4.5.1** - Decimal values allowed
- **4.5.2** - Starting values recommended: 16/14 (2160p), 17 (720p/1080p), 19 (SD)

**4.6** - Bitrate threshold adjustment: increment CRF by 1/0.1 when encoded bitrate exceeds percentage of source
- **4.6.1** - 2160p targets: 20% (SD source), 40% (720p), 60% (1080p), 98% (2160p)
- **4.6.2** - 1080p targets: 40% (SD), 70% (720p), 98% (1080p)
- **4.6.3** - 720p targets: 60% (SD), 98% (720p)
- **4.6.4** - SD targets: 98% (SD)
- **4.6.5** - HEVC->AVC transcoding: add 40% source bitrate to account for HEVC efficiency

**4.7** - 2-pass acceptable in extreme cases (not primary CRF replacement)
- **4.7.1** - NFO must show detailed visual/bitrate improvement evidence vs. CRF
- **4.7.2** - CRF exceeding 24 indicates 2-pass consideration
- **4.7.3** - 2-pass must follow rule 4.6 percentages (target maximum, work down)

**4.8** - Exceeding rule 4.6 percentages allowed with detailed NFO justification

**4.9** - Unreasonably high CRF/low bitrate without justification = technical flaw

**4.10** - Encoded bitrate cannot exceed source bitrate
- **4.10.1** - Video bitrate only (not overall muxed bitrate)
- **4.10.1.1** - Determine source bitrate via network traffic observation or manifest examination
- **4.10.2** - CRF calculation algorithm provided for bitrate excess correction

**4.11** - Settings cannot drop below x264 'slower'/x265 'slow' preset specifications

**4.12** - Level requirements:
- **4.12.1** - SD: '3.1'
- **4.12.2** - 720p: '4.1'
- **4.12.3** - 1080p: '4.1' (or '4.2' if >30fps)
- **4.12.4** - 2160p: '5.1' (or '5.2' if >30fps)

**4.13** - Custom matrices forbidden

**4.14** - Zones permitted sparingly; NFO requires detailed evidence per zone

**4.15** - GPU/acceleration offloading forbidden (no --opencl, nvenc)

**4.16** - Tuning allowed: 'film', 'grain', or 'animation'

**4.17** - Recommended tuning settings per source type:
- **4.17.1** - Complex video: --preset veryslow encouraged
- **4.17.2** - --aq-mode 3 --aq-strength: 0.5-0.7 (grainy), 0.6-0.9 (digital), 0.9-1.1 (animation)
- **4.17.3** - --psy-rd: 0.8-1.2 (film), 0.5-0.8 (animation)
- **4.17.4** - --deblock: -3:-3 (film), 1:1 (animation)

**4.18** - SAR must be '1:1' (square)

**4.19** - Deblocking cannot be disabled (--no-deblock forbidden)

**4.20** - Frame rate passed to encoder; keyframe interval/min-GOP auto-set; changes forbidden

**4.21** - Colour space: 4:2:0

**4.22** - Colour matrix optional for HD SDR (--colormatrix bt709); mandatory for SD SDR
- **4.22.1.1** - SD from HD source: use 'bt709'
- **4.22.1.2** - SD from SD source: use source specification
- **4.22.1.3** - SD unspecified: use 'undef'

**4.23** - x265-specific settings:
- **4.23.1** - Range, colorprim, transfer, colormatrix, chromaloc = match source (or omit if undefined)
- **4.23.2** - --uhd-bd forbidden
- **4.23.3** - --high-tier, --repeat-headers, --aud, --hrd mandatory
- **4.23.4** - HDR encoding:
  - **4.23.4.1** - --hdr10 and --hdr10-opt mandatory
  - **4.23.4.2** - --master-display and --max-cll match source (or omit if undefined)
  - **4.23.4.2.1** - Values from whole concatenated source

**4.24** - Tone-mapping forbidden (HDR->SDR, DV->SDR, HDR10Plus->SDR)

**4.25** - Suggested command lines:
- **4.25.1** - x264: "--preset slower --level ## --crf ##"
  - **4.25.1.1** - Optional: "--no-mbtree --no-fast-pskip --no-dct-decimate"
- **4.25.2** - x265: "--high-tier --repeat-headers --aud --hrd --preset slow --level-idc ## --crf ## --range ## --colorprim ## --transfer ## --colormatrix ## --chromaloc ##"
  - **4.25.2.1** - HDR append: "--hdr10 --hdr10-opt --master-display ## --max-cll ##"
  - **4.25.2.2** - Optional: "--no-cutree --no-open-gop --no-sao --pmode --aq-mode 4"

---

## SECTION 5: Transcoded Audio

**5.1** - Segmented encoding forbidden

**5.2** - Audio not resampled; original source format maintained
- **5.2.1** - Exception: resampling for codec limitations (e.g., TrueHD 192kHz->AC3 48kHz)

**5.3** - Gain levels not adjusted; source levels maintained

**5.4** - Channels not altered/removed; source channel count/layout maintained

**5.5** - Lossy track types: DTS-HD HR, E-AC3, DTS-ES, DTS, AC3, AAC, MP2

**5.6** - Audio track encoding:
- **5.6.1** - 720p and above:
  - **5.6.1.1** - Existing lossy formats not transcoded; kept original
  - **5.6.1.2** - No lossy OR fixing technical flaws: use AC3/E-AC3
  - **5.6.1.3** - AC3/E-AC3 target 640 Kbps (no upscaling):
    - **5.6.1.3.1** - Dolby Media Encoder
    - **5.6.1.3.2** - eac3to: -640
    - **5.6.1.3.3** - FFmpeg: -b:a 640k
  - **5.6.1.4** - Transcoding: retain positional metadata/channels >5.1 at group discretion

- **5.6.2** - SD/commentary: VBR AAC LC
  - **5.6.2.1** - Apple/QAAC, FDK-AAC, or Nero
  - **5.6.2.2** - >2 channels downmix to stereo:
    - **5.6.2.2.1** - eac3to: -downStereo
    - **5.6.2.2.2** - FFmpeg: -ac 2
  - **5.6.2.3** - Quality-based VBR (not targeted/constrained):
    - **5.6.2.3.1** - QAAC: "--tvbr 82 --quality 2"
    - **5.6.2.3.2** - FDK-AAC: "--bitrate-mode 4 --profile 2"
    - **5.6.2.3.3** - Nero: "-q 0.4"

- **5.6.3** - FLAC: lossless mono/stereo + multi-channel LPCM (all HD retail)
  - **5.6.3.1** - Best compression: --compression-level-8
  - **5.6.3.2** - No replay-gain (--replay-gain forbidden)

---

## SECTION 6: Transcoded Filters

**6.1** - IVTC, deinterlacing, decimation applied as required

**6.2** - Allowed smart deinterlacers: QTGMC (slow+) or Nnedi3

**6.3** - Allowed field matching filters: TIVTC or Decomb

**6.4** - Allowed resizers: Spline36Resize, Spline64Resize, BlackmanResize

**6.5** - Frame-accurate input plugins: DGIndex, DGDecNV, LSMASHSource (frame-inaccurate forbidden)

**6.6** - Destructive/effects filters forbidden (RemoveGrain, GrainFactory3, MedianBlur, FineSharp)

**6.7** - Optional recommended filtering:
- **6.7.1** - Odd-crop avoidance via 1-pixel shift (Overlay method)
- **6.7.2** - SelectRangeEvery() for CRF testing
- **6.7.3** - Selective f3kdb debanding (caution; high detail attention)

---

## SECTION 7: Common Video

**7.1** - Single video track only

**7.2** - HDR/DV/HDR10Plus at highest resolution only (exception: rule 8.6.3)

**7.3** - Must be free of technical flaws
- **7.3.1** - Includes: sync issues, interlacing, lack of IVTC, bad AR, invalid resolution, unrelated footage, warnings, glitches, under/over-crop, DRM

**7.4** - Source-based dupes forbidden; use INTERNAL

**7.5** - Single features not split across multiple files
- **7.5.1** - Opening/closing credits spanning files = single release
- **7.5.2** - Multiple episodes in single file with clear delineation = split releases per episode

**7.6** - Non-feature footage (credits, previously on, intertitles) not removed/separately encoded
- **7.6.1** - Progressive feature with interlaced non-feature = deinterlace only that footage

**7.7** - Unrelated footage must be removed
- **7.7.1** - Includes: commercials, warnings, worksheets, test screens, piracy warnings

**7.8** - English features: no foreign overlays for relevant on-screen information
- **7.8.1** - Relevant: location titles, hardcoded subtitles, introduction text, plot-essential info
- **7.8.2** - Non-relevant: opening credits, movie title, closing credits
- **7.8.3** - English subtitles instead of overlays = forced track (rule 11.2); cannot omit

**7.9** - Multiple web sources allowed (single encode); note sources in NFO

---

## SECTION 8: Common Resolution / Aspect Ratio

**8.1** - SD: maximum 720 pixels horizontal display

**8.2** - 720p: maximum display 1280x720
- **8.2.1** - AR >=1.78:1 = 1280 pixels horizontal (e.g., 2.40:1 -> 1280x534)
- **8.2.2** - AR <=1.78:1 = 720 pixels vertical (e.g., 1.33:1 -> 960x720)

**8.3** - 1080p: maximum display 1920x1080

**8.4** - 2160p: maximum display 3840x2160

**8.5** - Resolution must be mod2

**8.6** - Upscaling forbidden
- **8.6.1** - 1080p from 1080p/2160p from 2160p = crop only; no resize
- **8.6.2** - Vertical/horizontal cropping allows under-max resolutions (e.g., 1916x1072 at 1080p acceptable)
- **8.6.3** - Source lacking minimum specs: resize down; include source sample

**8.7** - Resolution-based dupes forbidden; use INTERNAL
- **8.7.1** - AR difference >=5% = not dupe (tag WS/FS/OM, not PROPER)
- **8.7.1.1** - AR difference calculation: |(OldAR - NewAR) / [(OldAR + NewAR) / 2]| x 100

**8.8** - Crop black borders/non-feature content
- **8.8.1** - Includes: black/colored borders, duplicate/dirty lines
- **8.8.2** - Faded edges discretionary (not technical flaw if included)
- **8.8.2.1** - Faded edges = similar-appearance line parallel to frame
- **8.8.2.2** - Faded edges part of frame; 1px faded != 1px black for proper determination
- **8.8.3** - Varying AR = crop to widest frame (exclude studio logos/credits)
- **8.8.4** - Variable cropping between sources = not technical flaw; no proper

**8.9** - Over/under-crop maximum +/-1 pixel per side (>1px = technical flaw)
- **8.9.1** - Under-crop = non-feature frame portions

**8.10** - Resolution within 0.2% original aspect ratio
- **8.10.1** - AR calculated post-crop
- **8.10.2** - Bad mastering AR: include source sample + comparison screenshot

**8.11** - SAR formula: SAR = (PixelHeight / PixelWidth) / (DARHeight / DARWidth)

**8.12** - DAR formula: DAR = (PixelWidth x DARWidth) / (PixelHeight x DARHeight)

**8.13** - Display resolution: DisplayWidth = PixelWidth x (SARWidth / SARHeight)

**8.14** - AR error: AR Error % = [(Original AR - Release AR) / Original AR] x 100

**8.15** - Target resolution (resize for mod2/AR): TargetHeight = TargetWidth / [(SourceWidth - CropLR) / (SourceHeight - CropTB)]
- **8.15.1** - Mod2 confirmation via ceiling/floor of TargetHeight; select value closest to zero AR error

---

## SECTION 9: Common Framerate

**9.1** - CFR mandatory
- **9.1.1** - VFR forbidden

**9.2** - FPS-based dupes forbidden; use INTERNAL

**9.3** - Constant dupe sequence = decimate (e.g., 1080p24 with 1-in-6 dupes -> 20fps)

**9.4** - Hybrid sources (varying FPS): IVTC application at group discretion; NFO explanation required
- **9.4.1** - Proven no unique-frame loss with IVTC/decimation = technical flaw if not applied

**9.5** - Native vs. converted frame rates (production standard):
- **9.5.1** - NTSC-produced = native NTSC
- **9.5.2** - PAL-produced = native PAL
- **9.5.3** - NTSC produced, PAL mastered = converted
- **9.5.4** - PAL produced, NTSC mastered = converted

**9.6** - Converted video must restore to original framerate
- **9.6.1** - Includes: ghosted, blended, duplicate frames
- **9.6.2** - Does NOT include NTSC<->PAL speed-up/slow-down
  - **9.6.2.1** - Correct via video mux (--default-duration) + audio speed adjustment (eac3to -slowdown/-keepDialnorm)
  - **9.6.2.2** - Audio transcoding respects Section 5
  - **9.6.2.3** - WEB tag retained for speed/slow correction
  - **9.6.2.4** - 24fps = valid (no correction if only speed-issue)
- **9.6.3** - Successful native restoration without artifacts = no CONVERT tag
- **9.6.4** - Failed restoration/artifacts = CONVERT tag required

**9.7** - True 50/59.940fps at 50/59.940fps (true 25/29.970 @ 50/59.940 = technical flaw)
- **9.7.1** - Varying 25/29.970 + true 50/59.940 = use main feature framerate
- **9.7.2** - Rare: 25/50fps -> 23.976/29.97fps restoration
- **9.7.3** - Rare: 29.97/59.940fps -> 25fps restoration

---

## SECTION 10: Common Audio

**10.1** - Sync must not drift during entire release

**10.2** - Glitching/unrelated audio = technical flaw
- **10.2.1** - Glitching = audible glitch, missing audio, pops/clicks, gaps, missing dialogue, mute/muffle

**10.3** - English release: single English dialogue track
- **10.3.1** - Exception: remastered/restored source (both original + remastered allowed; group chooses primary)

**10.4** - Non-English release: optional secondary dialogue track
- **10.4.1** - Original + forced English subtitles (rule 11.2)
- **10.4.2** - Secondary = different dialect/language variety OR English dub
- **10.4.3** - Rare: third dubbed track (another dialect/variety) + English dub

**10.5** - Non-English dubbed-only releases: tag DUBBED

**10.6** - Commentary audio allowed

**10.7** - Single audio track per language at highest quality level per resolution (no lossless + lossy pairs)
- **10.7.1** - Exception: embedded cores in lossless tracks (muxer-separated as additional)

**10.8** - Special audio tracks allowed (isolated scores, original mixes, narrators)

**10.9** - Supplementary audio: descriptive title field (original, remastered, commentary with director)

**10.10** - ISO 639 language code (MKVToolnix-supported)
- **10.10.1** - Unsupported language: use 'und'

**10.11** - Audio-based dupes (tracks, format, narrators, remastered) forbidden; use INTERNAL

**10.12** - Retail audio acceptable in place of source extraction; note sources in NFO
- **10.12.1** - Lossless types: DTS:X, TrueHD Atmos, DTS-HD MA, TrueHD
- **10.12.2** - >720p: highest quality retail lossless (rule 10.12.1 preference order)
- **10.12.3** - 720p: extract AC3/E-AC3 >=640Kbps OR transcode from best retail
- **10.12.4** - SD/commentary: transcode from best retail (rule 5.6.2)

---

## SECTION 11: Common Subtitles

**11.1** - All source subtitles converted to SubRip; include in release
- **11.1.1** - Forced subtitles for excluded dubs optional
- **11.1.2** - Exception to SubRip: rule 11.2.2 applies; use PGS/ASS
- **11.1.3** - Capturing non-forced optional (strongly recommended extraction)

**11.2** - Foreign dialogue/overlays: separate SubRip forced English track (forced + default)
- **11.2.1** - Exception: hardcoded source subtitles for non-English dialogue
- **11.2.2** - Exception: excessive positional subtitles (anime) = PGS/ASS (forced + default)

**11.3** - Forced SubRip technical flaw-free
- **11.3.1** - Careful OCR required
- **11.3.2** - Minor grammar/punctuation tolerated (correction recommended)

**11.4** - Subtitles from officially licensed HDTV/retail allowed
- **11.4.1** - Other-source subtitles noted in NFO (source + tracks)
- **11.4.2** - Fan-made/custom forbidden
- **11.4.2.1** - Exception: stripped SDH subtitles (group-made from valid SDH)

**11.5** - Hardcoded source subtitles allowed (except non-English hardcoded in English features)
- **11.5.1** - Full-feature hardcoded = tag SUBBED
- **11.5.2** - Letterbox-only subtitles = crop + OCR to SubRip
- **11.5.3** - Letterbox + active video overlay = crop to widest frame, apply equally
- **11.5.4** - Rules 11.5.2/11.5.3 do NOT apply to WEB releases

**11.6** - Subtitles not subject to propers/nukes for technical flaws

**11.7** - Subtitle-based dupes forbidden; use INTERNAL

---

## SECTION 12: Common Subtitle Format

**12.1** - Allowed: PGS (.sup), SubStation Alpha (.ass), SubRip (.srt)
- **12.1.1** - PGS compression: zlib only
- **12.1.2** - PGS not resized; mux as-is
- **12.1.3** - UTF-8 for ASS/SRT
- **12.1.4** - ASS conversion: clean, no unnecessary modifications (Subtitle Edit recommended)
- **12.1.5** - Embedded closed captions (CEA-708): retain
- **12.1.5.1** - Retention when transcoding optional (strongly recommended)
- **12.1.5.2** - Extraction to SubRip/ASS optional (strongly recommended)

**12.2** - Subtitle requirements:
- **12.2.1** - ISO 639 language code (MKVToolnix-supported)
  - **12.2.1.1** - Unsupported: use 'und'
- **12.2.2** - Not default/forced (unless rule 11 specifies)
- **12.2.3** - Correct sync offset during mux
- **12.2.4** - Correct conversion; groups not responsible for pre-existing flaws in non-forced tracks

**12.3** - Descriptive title field strongly recommended (Director's Commentary, English [Forced], English [SDH])

**12.4** - Burning subtitles to video forbidden

**12.5** - External 'Subs' directory subtitles forbidden

---

## SECTION 13: Common Container

**13.1** - Container: Matroska (.mkv); MKVToolnix recommended
- **13.1.1** - Custom tools allowed (must adhere to specs; identical compatibility)

**13.2** - RAR file streaming/playback support mandatory

**13.3** - Matroska header compression disabled

**13.4** - Chapters allowed/strongly recommended
- **13.4.1** - Chapter names optional; if present = English

**13.5** - No watermarks, intros, outros, defacement in any track

---

## SECTION 14: Common Packaging

**14.1** - RAR format; maximum 101 volumes
- **14.1.1** - Old-style extensions (.rar to .r99)
- **14.1.2** - First volume: .rar extension

**14.2** - RAR3/v2.0 OR RAR4/v2.9 (NOT RAR5/v5.0)
- **14.2.1** - Custom tools must adhere to spec; identical compatibility

**14.3** - Archive sizes:
- **14.3.1** - SD: 15,000,000 or 20,000,000 bytes (no multiples)
- **14.3.2** - All resolutions: positive integer multiples of 50,000,000 bytes
- **14.3.3** - Minimum 10 volumes before upgrading multiple size

**14.4** - Single SFV for primary archives (entire set)

**14.5** - NFO/RAR/SFV/Proof/Sample: unique lowercase filenames with group tag
- **14.5.1** - Group tag unique per group (abbreviated variation allowed)

**14.6** - Missing RAR(s)/SFV on all sites = technical flaw

**14.7** - Corrupt RAR(s) upon extraction = technical flaw

**14.8** - RAR compression/recovery records forbidden

**14.9** - Encryption/password protection forbidden

**14.10** - Archive contains single .mkv only (no extras)
- **14.10.1** - Exception: extras releases (multiple .mkv allowed; unique, descriptive names)
  - **14.10.1.1** - All extras of tagged resolution included
  - **14.10.1.2** - External 'Extras' directories forbidden

---

## SECTION 15: Common Proof

**15.1** - Proof required for releases with retail elements (subtitles, audio)
- **15.1.1** - Photograph of disc printed side; group name visible
- **15.1.2** - Minimum 640x480px; disc details clear/legible
- **15.1.3** - Minor sensitive info may be redacted
- **15.1.4** - Photo of actual disc used for final encode
- **15.1.5** - Cover scans/m2ts samples optional (don't count as proof)

**15.2** - Proof in separate 'Proof' directory
- **15.2.1** - JPEG/PNG format; not archived

**15.3** - Multiple retail sources: proof for all sources

**15.4** - All EXIF data stripped (especially geolocation)
- **15.4.1** - EXIF-lacking proof attention forbidden (no nuke, proper, NFO mention)

**15.5** - Missing required proof = technical flaw; proper-able
- **15.5.1** - Proof fix within 24 hours of original pre
- **15.5.2** - Fixes after proper/24hr = rejected

---

## SECTION 16: Common Samples / Source Samples

**16.1** - 50-70 second sample per release:
- **16.1.1** - Separate 'Sample' directory
- **16.1.2** - Cut from final video (not separately encoded); not archived
- **16.1.3** - No opening/closing (cut >=2m in or middle if possible)

**16.2** - Source samples required if source validity questioned
- **16.2.1** - Unique filename in 'Proof' directory
- **16.2.2** - Source validity nuke (within 24hr) must specify suspicion/reason
- **16.2.3** - Specific timecode may be requested for verification
- **16.2.4** - 48-hour window for 30-second to 5-minute source sample pre (main feature, exclude opening/ending credits if no timestamp specified)
- **16.2.5** - Packed per Section 14; SOURCE.SAMPLE tag
- **16.2.6** - Failed proof provision = release remains nuked (technical flaw)

---

## SECTION 17: Common NFO

**17.1** - Single NFO file mandatory:
- **17.1.1** - Transcoded: source video stream bitrate (retrieved via MediaInfo --parsespeed=1, ffprobe, etc.)

**17.2** - Optional/recommended information:
- **17.2.1** - Release name/group
- **17.2.2** - Release date
- **17.2.3** - Runtime
- **17.2.4** - Resolution/AR
- **17.2.5** - Framerate
- **17.2.6** - Audio format
- **17.2.7** - File size
- **17.2.8** - Archive information
- **17.2.9** - Included subtitles list
- **17.2.10** - CRF value

---

## SECTION 18: Common Tagging

**18.1** - Source tags allowed: WEB, WEBRIP

**18.2** - Additional tags allowed: ALTERNATIVE.CUT, BW, CHRONO, COLORIZED, CONVERT, DC, DIRFIX, DUBBED, DV, EXTENDED, EXTRAS, FS, HDR, HDR10Plus, HR, INTERNAL, LINE, NFOFIX, OAR, OM, PROOFFIX, PROPER, PURE, RATED, READNFO, REAL, REMASTERED, REPACK, RERIP, RESTORED, SAMPLEFIX, SOURCE.SAMPLE, SUBBED, THEATRICAL, UNCENSORED, UNCUT, UNRATED, WS
- **18.2.1** - <VERSION/CUT TITLE> if tag doesn't fit (e.g., Deadpool.2.The.Super.Duper.Cut)
- **18.2.2** - REMASTERED/RESTORED proof: 3+ comparison screenshots (Proof dir) OR link to comparison site (caps-a-holic.com) OR refer to prior release
- **18.2.3** - HR only when rule 21.5.3 applies

**18.3** - Tag variations forbidden (READ.NFO/RNFO != READNFO)

**18.4** - READNFO used sparingly
- **18.4.1** - Not combined with PROPER, REPACK, RERIP

**18.5** - Tags grouped, period-delimited, follow rule 19.4

**18.6** - Tags used once; order discretionary
- **18.6.1** - Exception: REAL stacking to differentiate multiple invalid releases (e.g., REAL.REAL.PROPER)

**18.7** - All HDR content tagged as such

---

## SECTION 19: Common Directory Nomenclature

**19.1** - Acceptable characters: A-Z, a-z, 0-9, . _ -

**19.2** - Single punctuation only (no consecutive: Show----Name forbidden)

**19.3** - No typos/spelling mistakes

**19.4** - Release directory formats:

- **19.4.1 - Feature**:
  `Feature.Title.<YEAR>.<TAGS>.[LANGUAGE].<RESOLUTION>.<FORMAT>-GROUP`

- **19.4.2 - Weekly TV**:
  `Weekly.TV.Show.[COUNTRY_CODE].[YEAR].SXXEXX[Episode.Part].[Episode.Title].<TAGS>.[LANGUAGE].<RESOLUTION>.<FORMAT>-GROUP`

- **19.4.3 - Weekly Special**:
  `Weekly.TV.Show.Special.SXXE00.Special.Title.<TAGS>.[LANGUAGE].<RESOLUTION>.<FORMAT>-GROUP`

- **19.4.4 - Multiple Episode**:
  `Multiple.Episode.TV.Show.SXXEXX-EXX[Episode.Part].[Episode.Title].<TAGS>.[LANGUAGE].<RESOLUTION>.<FORMAT>-GROUP`

- **19.4.5 - Cross-Over**:
  `Cross.Over.TV.Show.One.SXXEXX[Episode.Part].[Episode.Title]_Show.Two.SXXEXX[Episode.Part].[Episode.Title].<TAGS>.[LANGUAGE].<RESOLUTION>.<FORMAT>-GROUP`

- **19.4.6 - Miniseries**:
  `Miniseries.Show.PartX.[Episode.Title].<TAGS>.[LANGUAGE].<RESOLUTION>.<FORMAT>-GROUP`

**19.5** - Named arguments <> mandatory; optional [] discretionary:
- **19.5.1** - Mini-series parts >=1 integer (extendable past 9)
- **19.5.2** - Season/episode >=2 integers (extendable past 99)
- **19.5.3** - Episode parts alphanumeric (A-Z, a-z, 0-9)
- **19.5.4** - Season omitted if series non-seasonal (One.Piece.E01)
- **19.5.5** - Episode title optional
- **19.5.6** - Tags = rule 18 permitted tags
- **19.5.7** - Non-English releases: full language name (FRENCH, RUSSIAN, GERMAN; no codes)
  - **19.5.7.1** - English releases: no language tag
- **19.5.8** - Format: WEBRip.x264/x265 OR WEB.H264/H265

**19.6** - No ripping/encoding method indication (use NFO for technical details)

**19.7** - Non-series (films, documentaries): production year included

**19.8** - Identical titles (different countries): ISO 3166-1 alpha-2 country code
- **19.8.1** - Exception: UK (not GB)
- **19.8.2** - Doesn't apply to original show (only successors)

**19.9** - Identical titles (same country, different years): first season year included (original excluded)

**19.10** - Identical titles (same country, different years): country code + year

**19.11** - Hyphenated/punctuated titles: follow title sequence/credits format (acceptable char list only)
