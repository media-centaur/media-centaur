---
title: "SD x264 Releasing Standards v1.1 (Movies)"
source_url: "https://scenerules.org/html/2013_SDX264v1.1.html"
date_accessed: "2026-03-12"
category: "scene-standards"
document_id: "2013_SDX264v1.1"
effective_date: "2013-11-01"
---

# SD x264 Releasing Standards v1.1

Effective date: 2013-11-01 00:00 UTC (1383264000 unixtime). Compliance mandatory from this date forward. This ruleset transitions SD releases from XviD to x264 codec standards.

---

## SECTION 1: VIDEO

**1.1** Non-English overlays in English-language films prohibited in main footage; permitted only in iNTERNAL releases. Credits and foreign text overlays must be removed or tagged appropriately.

**1.2** Watermarks, intros, outros, and defacement banned throughout entire file including credits.

**1.3** Video splitting into multiple files not allowed.

**1.4** Two-disc movies must encode as single file if credits distributed across discs.

**1.5** Credits encoding restrictions: must match main footage settings except interlaced credits may be de-interlaced solo (not entire video).

**1.6** Studio worksheets and test screens must be removed.

---

## SECTION 2: ASPECT RATIO / RESOLUTION

### 2.1 - General

**2.1.1** Black borders require complete cropping to widest frame on variable-AR sources.

**2.1.2** Height and width must be mod2.

**2.1.3** Over/under-cropping exceeding 1px constitutes technical flaw; recommend removing excess pixel.

**2.1.4** Video AR within 0.5% of original source required.

**2.1.5** AR based on actual source, not IMDB or packaging information.

**2.1.6** Incorrect source AR requires comparison screenshots and source sample justification.

**2.1.7** ITU-R Standard (anamorphic WS 1.82, FS 1.36) prohibited.

**2.1.8** Only sharp resizers permitted: Lanczos/Lanczos4, Spline36, Blackman. Simple resizers (bicubic, simple) banned.

### 2.2 - BluRay

**2.2.1** BluRay width must be 720 pixels.

**2.2.2** Apply source AR while resizing height to mod2.

### 2.3 - DVD

**2.3.1** 720px horizontal sources cropped per AR requirements; height resized to mod2. Exception: 4:3 NTSC letterboxed content crops by height, resizes by width.

**2.3.2** Width maximized post-crop, except 4:3 NTSC sources capped at 640px width.

**2.3.3** Upscaling prohibited.

---

## SECTION 3: FRAMERATE / FILTERS

**3.1** IVTC or deinterlacing applied when required.

**3.2** Only smart deinterlacers permitted (Yadif); FieldDeinterlace banned.

**3.3** Framerate must match original source as closely as possible.

**3.4** PAL movies may require IVTC regardless of source format.

**3.5** Hybrid sources left to ripper discretion with mandatory explanation and source proof; problematic sources require restoration or INTERNAL tag with NFO notation.

**3.5.1** Native source releases following restoration releases tagged NATIVE; original not nuked.

**3.6** Variable Frame Rate (VFR) techniques prohibited.

---

## SECTION 4: CONTAINER

**4.1** Container must be MKV using MKVMerge (custom tools permitted if output compatible).

**4.2** File streaming and RAR playback mandatory.

**4.3** MKV headers remain intact, unmodified, uncompressed.

---

## SECTION 5: CODEC

**5.1** H.264 with 8-bit depth via x264.

**5.2** x264 version within 50 revisions of latest at pre-time.

### 5.3 - CRF Requirements

**5.3.1** CRF range: 19-26 only; below 19 or above 26 never permitted.

**5.3.2** CRF 19 for 2007+ sources except sports. Exceptions: CRF 21 if avg bitrate >2000kbps; CRF 22-23 if CRF 21 yields >1500kbps; CRF 23-24 if CRF 21 yields >2000kbps.

**5.3.3** CRF 19-21 for 2006 and older sources except sports. Similar bitrate exceptions apply.

**5.3.4** CRF 23-26 for sporting events (ripper discretion).

**5.3.5** TV season/volume sets use consistent CRF across episodes; max 25% episodes may vary.

**5.3.6** Bonus complete episodes match season CRF; extras (deleted scenes, bloopers) at ripper discretion.

**5.4** No source-type dupes (DVD/BD); use INTERNAL tag.

**5.5** Settings must meet or exceed `--preset slow` specifications.

**5.6** Sample Aspect Ratio (--sar) must be 1:1 (square).

**5.7** Keyframe interval (--keyint): 200-300 inclusive; recommended 10x framerate.

**5.8** Min-keyint (--min-keyint): 20-30 inclusive; recommended 1x framerate.

**5.9** Colormatrix matches source spec; BD defaults to bt709; DVD defaults to 'undef'.

**5.10** Zones (--zones) forbidden.

**5.11** --output-csp kept at default.

**5.12** --level 3.1 mandatory.

**5.13** Custom matrices prohibited.

### 5.14 - Optional Psychovisual Settings

**5.14.1** --tune parameters: film, grain, animation only.

**5.14.2** --deblock: -2:-2 for film (recommended), 2:1 for animation (recommended).

**5.14.3** --aq-strength: 0.6-0.9 recommended; default 1.0.

**5.14.4** --psy-rd: 0.8-1.2 for film, 0.4-0.7 for animation; trellis kept at 0.0.

### 5.15 - Suggested Command Lines

**5.15.1** BluRay: `x264 --level 3.1 --crf xx --preset slow --colormatrix bt709 -o output.mkv input.avs`

**5.15.2** DVD: `x264 --level 3.1 --crf xx --preset slow -o output.mkv input.avs`

---

## SECTION 6: AUDIO

**6.1** VBR AAC LC only; INTERNAL AC3 releases permitted.

**6.2** Nero and Apple encoders recommended; FFmpeg and FAAC banned.

**6.3** Average bitrate: 96-160kbps stereo, 60-100kbps mono.

**6.4** Must match source: STEREO for stereo, MONO for mono (identical channels = mono). Dual mono forbidden except remastered audio on originally mono titles.

**6.5** Multichannel audio downmixed to stereo except INTERNAL releases.

**6.6** Original source frequency preserved (48kHz remains 48kHz, 44.1kHz remains 44.1kHz).

**6.7** AAC audio normalized.

**6.8** Dual-language tracks permitted for non-English material only.

**6.9** English dubbed without original audio tagged DUBBED.

**6.10** Dubbed releases only if no secondary dubbed track exists in competing release.

---

## SECTION 7: SUBTITLES

**7.1** Vobsub and accurately OCR'd SRT only.

**7.2** Required for non-English films and films with non-English dialogue.

**7.2.1** SRT: mux into MKV, enable by default.

**7.2.2** Vobsub: forced-only stream mandatory if foreign parts embedded/flagged only.

**7.3** SRT muxing into MKV recommended; separate packing allowed otherwise.

**7.4** Vobsubs NOT muxed into MKV.

**7.5** Subtitle filenames match video filename; DVD forced subs tagged `*.forced`.

**7.6** BD Vobsubs resized to 720x480 or 720x576 via BDSup2Sub.

**7.7** External subtitles packed as `<video-name>.subs.rar` in 'Subs' directory.

**7.8** Single subtitle set only.

**7.9** Hardcoded subs permitted only if source-present.

**7.10** English subs synced with video.

**7.11** Foreign releases lack English subs tagged with spoken language; English-subbed releases NOT tagged with language.

**7.12** Retail subtitles only; fan/custom subs use INTERNAL.

**7.13** Multi-language subtitles trigger INTERNAL.

**7.14** SUBBED tag mandatory on hardsubbed fully non-English films.

---

## SECTION 8: PACKAGING

**8.1** RAR format, max 99 volumes; allowed sizes: 15MB or 50MB.

**8.2** Unique filenames (all files including subs RAR).

**8.3** No compression or recovery records.

**8.4** SFV required for main RARs and subtitle RARs separately.

**8.5** NFO mandatory.

**8.6** Recommended NFO info: group name, title, release date, CRF value, IMDB/Amazon/TVRage link, RAR count or total video size.

---

## SECTION 9: SAMPLES

**9.1** 50-70 second sample required per release.

**9.2** Unique filename in separate 'Sample' directory.

**9.3** Cut from video, NOT separately encoded.

**9.4** Source samples required for questionable rips.

---

## SECTION 10: PROPERS / REPACKS / RERIPS

**10.1** Propers permitted only for technical flaws (bad IVTC, interlacing, wrong CRF).

**10.2** Propers include NFO detailing flaw reason.

**10.3** Non-globally nuked releases include original release sample/screenshots demonstrating flaw in Proof directory.

**10.4** Qualitative propers banned; use INTERNAL for ripper-discretion decisions.

**10.5** Hardcoded subs followed by non-hardsubbed allowed; original NOT nuked.

**10.6** Propering working-fix releases prohibited.

**10.7** XviD proper requires XviD ruleset violation at XviD pre-time.

**10.8** Repacks and rerips include detailed reason in NFO.

---

## SECTION 11: SPECIAL MOVIE EDITIONS

**11.1** Allowed tags: DC, EXTENDED, UNCUT, REMASTERED, UNRATED, THEATRICAL, CHRONO, SE (or other).

**11.2** Same runtime as previous versions = dupe.

**11.3** Shorter cut after longer version (e.g., THEATRICAL) allowed; tagged in dirname.

**11.4** Remastered releases permitted post-original; tagged REMASTERED.

**11.5** Extras in special editions non-dupes unless separately released.

**11.6** Homemade sources prohibited.

**11.7** PAL-NTSC length differences from fps, not extra footage.

---

## SECTION 12: WS vs. FS

**12.1** WS/FS tags only if different-AR rip exists.

**12.2** WS after FS (vice versa) requires proof of additional picture area.

**12.3** Wider WS showing more original source valid, tagged WS not PROPER.

**12.4** Letterboxed DVDs not FS despite 4:3 flagging.

---

## SECTION 13: DIRECTORY AND FILE NAMING

**13.1** Mandatory format:
- Movie: `Movie.Name.YEAR.<PROPER/READ.NFO/REPACK>.<BDRip/DVDRip>.x264-GROUP`
- TV: `TV.Show.SxxExx.<PROPER/READ.NFO/REPACK>.<BDRip/DVDRip>.x264-GROUP`

**13.2** All movies must include production year.

**13.3** TV shows matching previous show names require country tag (US, UK) or production year tag.

**13.4** DVDRip for DVD, BDRip for BD.

**13.5** No ripping method, release date, genre, audio, or other metadata in dirname (use NFO).

**13.6** Distribution tags (FESTIVAL, STV, LIMITED, TV for TV movies) allowed.

**13.7** READ.NFO tag allowed, not abused.

**13.8** Permitted tags: WS/FS, PROPER, REPACK, RERIP, REAL, RETAIL, EXTENDED, REMASTERED, RATED, UNRATED, CHRONO, THEATRICAL, DC, SE, UNCUT, INTERNAL, DUBBED, SUBBED, FINAL, COLORIZED.

**13.8.1** RERIP for ripping issues, REPACK for packing issues.

**13.8.2** RERIP/REPACK uses different filenames from previous release.

**13.9** Acceptable characters: A-Z, a-z, 0-9, period, hyphen only (NO spaces, double dots/slashes).

---

## SECTION 14: PROOF

**14.1** All retail releases require physical disc photograph with group tag in JPEG.

**14.2** Proof images in separate 'Proof' directory.

**14.3** Cover scans and m2ts/vob samples optional but insufficient as proof.

**14.4** Missing proof = nuke; can be propered. Proofixes after 4 hours rejected.

**14.5** TV series proof options: a) all discs in first episode, b) per episode, c) per disc, d) all discs every episode.

**14.6** EXIF metadata removed from images.

---

## SECTION 15: SOURCE RELATED NOTES

**15.1** Re-encoding transcoded sources prohibited.

**15.2** Non-studio audio tagged (e.g., LINE audio).

**15.3** Studio audio releases don't dupe non-studio.

**15.4** CAM, TS, TC, Workprint, SCREENER, Laserdisc tagged in dirname; not retail.

**15.5** Screeners clearly marked in NFO.

**15.6** SD WEBRips from iTunes-style sources follow ruleset without re-encoding; HD downloads re-encoded.

**15.6.1** Capped WEBRips follow TV rules.

**15.6.2** Proof: screenshot of download in progress.

**15.6.3** BDRip/DVDRip predate WEBRip.

---

## SECTION 16: INTERNALS

**16.1** INTERNALS follow all rules; exempt from CRF and conditions explicitly noted.

**16.2** INTERNALS NOT exempt from proof rules.

**16.3** Experimental codecs/containers permitted but INTERNAL.

**16.4** Dirfixing to INTERNAL to avoid nuke remains nuked.

---

## SIGNATORIES

Document signed by 100+ scene groups including 0x539, aAF, AEN, AFFECTION, ALLiANCE, AMIABLE, and others.

## CHANGELOG

Rev 1.1 - Resizing examples corrected.
