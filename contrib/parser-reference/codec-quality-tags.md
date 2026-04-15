
# Video & Audio Codec Tags and Quality Indicators in Release Filenames

> Source: https://en.wikipedia.org/wiki/Pirated_movie_release_types
> Source: https://trash-guides.info/Radarr/Radarr-collection-of-custom-formats/
> Source: https://trash-guides.info/Sonarr/sonarr-collection-of-custom-formats/
> Source: https://en.wikipedia.org/wiki/Dolby_Digital
> Source: https://en.wikipedia.org/wiki/Dolby_Digital_Plus
> Source: https://en.wikipedia.org/wiki/Dolby_TrueHD
> Source: https://en.wikipedia.org/wiki/High-dynamic-range_television
> Source: https://en.wikipedia.org/wiki/VP9
> Source: https://en.wikipedia.org/wiki/AV1
> Source: https://en.wikipedia.org/wiki/Display_resolution_standards
> Source: https://en.wikipedia.org/wiki/Audio_file_format
> Source: https://www.filebot.net/forums/viewtopic.php?t=6259
> Source: https://www.filebot.net/forums/viewtopic.php?t=12807
> Source: https://scenerules.org/t.html?id=2020_X265.nfo
> Source: https://www.whathifi.com/advice/mp3-aac-wav-flac-all-the-audio-file-formats-explained
> Source: https://handwiki.org/wiki/Engineering:Pirated_movie_release_types


Comprehensive reference for tags found in media release filenames. Tags are grouped by
category. Each entry lists the tag as it appears in filenames, what it means, common
variations, and quality notes.

---

## 1. Video Codecs

### H.264 / AVC

| Tag | Meaning | Variations | Notes |
|-----|---------|------------|-------|
| `x264` | Encoded with the x264 encoder (H.264/AVC) | `X264`, `h264`, `H264`, `h.264`, `H.264`, `AVC` | The most common video codec in releases. Excellent compatibility across all devices. Good quality-to-size ratio. |
| `x265` | Encoded with the x265 encoder (H.265/HEVC) | `X265`, `h265`, `H265`, `h.265`, `H.265`, `HEVC` | ~30-50% better compression than x264 at equivalent quality. Primarily used for 2160p and HDR content. Higher decode requirements. |

### Legacy Codecs

| Tag | Meaning | Variations | Notes |
|-----|---------|------------|-------|
| `XviD` | Encoded with the Xvid encoder (MPEG-4 ASP) | `XVID`, `Xvid` | Legacy codec from the DVD-rip era. Rarely used in modern releases. |
| `DivX` | Encoded with the DivX encoder (MPEG-4 ASP) | `DIVX`, `divx` | Proprietary predecessor/competitor to Xvid. Obsolete for new releases. |
| `MPEG2` | MPEG-2 video codec | `MPEG-2`, `MPG2`, `H.262` | Used in DVDs and broadcast TV. Large file sizes for the quality. Found in raw captures and remuxes. |
| `VC-1` | Microsoft VC-1 codec (evolved from WMV9) | `VC1`, `WMV9` | Used on some early Blu-ray discs. Rarely seen in modern releases. |

### Modern / Next-Gen Codecs

| Tag | Meaning | Variations | Notes |
|-----|---------|------------|-------|
| `AV1` | AOMedia Video 1 | `av1` | Royalty-free, next-gen codec. Superior compression to HEVC. Used by Netflix, YouTube, and streaming services. Growing in releases. |
| `VP9` | Google VP9 codec | `vp9` | Royalty-free codec developed by Google. Used by YouTube and Netflix. Rarely seen in scene releases but appears in WEBRip/WEB-DL from YouTube sources. |
| `VP8` | Google VP8 codec | `vp8` | Predecessor to VP9. Rare in media releases. |

---

## 2. Audio Codecs and Formats

### Dolby Family

| Tag | Meaning | Variations | Notes |
|-----|---------|------------|-------|
| `AC3` | Dolby Digital (AC-3) | `DD`, `Dolby`, `DolbyDigital` | Lossy. Standard Blu-ray/DVD audio. Typically 5.1 channels at 384-640 kbps. The baseline for surround sound. |
| `DD5.1` | Dolby Digital 5.1 channels | `DD.5.1`, `DD51` | Explicit channel count variant of AC3. 5.1 = front L/R/C + surround L/R + LFE subwoofer. |
| `DD+` | Dolby Digital Plus (E-AC-3) | `DDP`, `EAC3`, `E-AC-3`, `E-AC3`, `DDPlus`, `DD+5.1`, `DD+7.1`, `DDP5.1`, `DDP7.1` | Enhanced lossy codec. Higher bitrates and more channels than AC3. Default audio for many streaming services. |
| `DDP5.1` | Dolby Digital Plus 5.1 | `DD+5.1`, `EAC3.5.1` | Explicit channel variant. Common in WEB-DL releases from streaming services. |
| `TrueHD` | Dolby TrueHD | `Dolby.TrueHD`, `TRUEHD` | Lossless. Found on Blu-ray discs. Bit-for-bit identical to studio master. Typical bitrates 1-5 Mbps. Internal codec ID: `MLP FBA`. |
| `TrueHD.Atmos` | Dolby TrueHD with Atmos metadata | `Atmos`, `TrueHD.7.1.Atmos`, `TRUEHD.ATMOS` | Lossless base + Atmos object-based spatial audio. Highest quality Dolby format. Internal codec ID: `MLP FBA 16-ch`. Falls back to 7.1 TrueHD on non-Atmos receivers. |
| `Atmos` | Dolby Atmos (generic tag) | `ATMOS` | May indicate TrueHD Atmos (lossless, Blu-ray) or DD+ Atmos (lossy, streaming). Check source to determine which. |
| `EAC3.Atmos` | Dolby Digital Plus with Atmos | `DDP.Atmos`, `DD+.Atmos`, `DDPAtmos`, `EAC3Atmos` | Lossy Atmos. Common in streaming WEB-DL. Internal codec ID: `E-AC-3 JOC`. |

### DTS Family

| Tag | Meaning | Variations | Notes |
|-----|---------|------------|-------|
| `DTS` | DTS Digital Surround (core) | `DTS5.1` | Lossy. Standard DTS track on DVDs and Blu-rays. Typically 768-1509 kbps at 5.1 channels. |
| `DTS-ES` | DTS Extended Surround | `DTS.ES`, `DTSES` | Adds a center-rear channel (6.1) to DTS. |
| `DTS-HD` | DTS-HD (generic tag) | `DTSHD` | May refer to either DTS-HD HRA or DTS-HD MA. Ambiguous without further context. |
| `DTS-HD.HRA` | DTS-HD High Resolution Audio | `DTS-HD.HR`, `DTS.HRA`, `DTSHRA`, `DTS-HRA` | Lossy but higher bitrate than DTS core. Up to 6 Mbps, up to 7.1 channels. Internal codec ID: `DTS XBR`. |
| `DTS-HD.MA` | DTS-HD Master Audio | `DTS-HD.MA.5.1`, `DTS-HD.MA.7.1`, `DTSMA`, `DTS-MA`, `DTS.MA` | Lossless. Bit-for-bit identical to studio master. Most common lossless format on Blu-ray. Internal codec ID: `DTS XLL`. |
| `DTS-X` | DTS:X (object-based spatial audio) | `DTS.X`, `DTSX` | DTS's answer to Dolby Atmos. Object-based immersive audio. Found on UHD Blu-rays. Falls back to DTS-HD MA on non-DTS:X receivers. |

### AAC Family

| Tag | Meaning | Variations | Notes |
|-----|---------|------------|-------|
| `AAC` | Advanced Audio Coding | `AAC2.0`, `AAC5.1`, `AAC.2.0`, `AAC.5.1` | Lossy. Very common in WEB-DL and WEBRip releases. Efficient codec, good quality at low bitrates. Default for Apple/iTunes content. |
| `AAC-LC` | AAC Low Complexity | `AACLC` | The most common AAC profile. |
| `HE-AAC` | High-Efficiency AAC | `HEAAC`, `HE.AAC`, `AAC-HE` | Version of AAC optimized for low bitrates (streaming). |

### Lossless / Uncompressed

| Tag | Meaning | Variations | Notes |
|-----|---------|------------|-------|
| `FLAC` | Free Lossless Audio Codec | `flac` | Open-source lossless compression. Common in music releases and some MKV remuxes. ~50-70% of uncompressed size. |
| `LPCM` | Linear Pulse-Code Modulation | `PCM`, `WAV` | Uncompressed audio. Found on some Blu-ray discs. Very large. Highest possible quality (raw digital audio). |
| `ALAC` | Apple Lossless Audio Codec | `alac` | Apple's lossless format. Rare in video releases. |

### Other Audio Codecs

| Tag | Meaning | Variations | Notes |
|-----|---------|------------|-------|
| `MP3` | MPEG-1 Audio Layer 3 | `mp3`, `LAME` | Legacy lossy codec. Rarely used in modern video releases. May appear in older DVDRip or XviD releases. |
| `OPUS` | Opus audio codec | `opus` | Modern, royalty-free, lossy codec. Excellent quality at low bitrates. Appears in some WEBRip releases. |
| `OGG` | Ogg Vorbis | `Vorbis`, `ogg` | Open-source lossy codec. Rare in video releases. |
| `WMA` | Windows Media Audio | `wma` | Microsoft's proprietary audio codec. Essentially obsolete in releases. |

---

## 3. Audio Channel Layouts

| Tag | Meaning | Variations | Notes |
|-----|---------|------------|-------|
| `1.0` | Mono | `Mono` | Single audio channel. |
| `2.0` | Stereo | `Stereo`, `2ch`, `2CH` | Left + Right channels. Common for older content and some streaming sources. |
| `2.1` | Stereo + LFE | | Stereo with a subwoofer channel. Uncommon tag. |
| `5.1` | 5.1 Surround | `6ch`, `6CH`, `51` | Front L/C/R + Surround L/R + LFE. The standard surround sound layout. Most common multi-channel config. |
| `6.1` | 6.1 Surround | `7ch` | 5.1 + center surround. Used by DTS-ES. |
| `7.1` | 7.1 Surround | `8ch`, `8CH`, `71` | 5.1 + rear L/R. Standard for UHD Blu-ray and high-end releases. |
| `7.1.2` | 7.1 + 2 height channels | | Atmos bed layout. Rare as explicit tag. |
| `7.1.4` | 7.1 + 4 height channels | | Full Atmos bed layout. Rare as explicit tag. |

---

## 4. HDR and Dynamic Range Tags

### HDR Formats

| Tag | Meaning | Variations | Notes |
|-----|---------|------------|-------|
| `HDR` | High Dynamic Range (generic) | `hdr` | Generic HDR tag. Usually indicates HDR10 but can be ambiguous. Wider color gamut and higher peak brightness than SDR. |
| `HDR10` | HDR10 (static metadata) | `HDR.10`, `hdr10` | Open standard. Static metadata (one brightness/color profile for entire film). 10-bit color, up to 1000 nits peak. Most common HDR format. |
| `HDR10+` | HDR10+ (dynamic metadata) | `HDR10Plus`, `HDR10.Plus`, `hdr10+`, `HDR10P` | Samsung-developed extension of HDR10. Dynamic metadata (scene-by-scene optimization). Open standard, royalty-free. |
| `DoVi` | Dolby Vision | `DV`, `Dolby.Vision`, `DolbyVision`, `DOVI` | Dolby's premium HDR format. 12-bit color, dynamic metadata per frame, up to 10,000 nits theoretical peak. Requires Dolby-licensed hardware for playback. |
| `DV.HDR10` | Dolby Vision with HDR10 fallback | `DoVi.HDR10`, `DV.HDR`, `DVHDR10` | Dual-layer: Dolby Vision for compatible devices, falls back to HDR10 on others. Common in UHD Blu-ray releases. Profile 7 or 8. |
| `DV.HDR10+` | Dolby Vision with HDR10+ fallback | `DoVi.HDR10+` | Rare combination. Both dynamic metadata formats in one file. |
| `HLG` | Hybrid Log-Gamma | `hlg` | BBC/NHK-developed HDR standard for broadcast. No metadata required; backward-compatible with SDR displays. Used primarily in broadcast TV captures. |
| `SDR` | Standard Dynamic Range | `sdr` | Non-HDR content. 8-bit color, standard brightness range. Sometimes explicitly tagged to distinguish from HDR versions. |
| `WCG` | Wide Color Gamut | `wcg` | BT.2020 color space. Often accompanies HDR but technically separate. Rarely used as standalone tag. |
| `10bit` | 10-bit color depth | `10-bit`, `10.bit`, `Hi10`, `Hi10P` | 10-bit color encoding. Smoother gradients, fewer banding artifacts. Required for HDR; optional for SDR (where it improves quality). |

### Dolby Vision Profiles (advanced)

| Tag | Meaning | Notes |
|-----|---------|-------|
| `DV.P5` | Dolby Vision Profile 5 | Single-layer, IPTPQc2. Streaming-only profile. No HDR10 fallback. |
| `DV.P7` | Dolby Vision Profile 7 | Dual-layer, used on UHD Blu-ray. MEL/FEL enhancement layers. |
| `DV.P8` | Dolby Vision Profile 8 | Single-layer, HDR10 base with RPU metadata. Most common in streaming and remux releases. |

---

## 5. Resolution Tags

### Standard Definition

| Tag | Meaning | Variations | Notes |
|-----|---------|------------|-------|
| `480p` | 640x480 or 720x480 progressive | `SD`, `NTSC` | NTSC standard definition. DVD resolution (NTSC regions). |
| `480i` | 720x480 interlaced | | Interlaced NTSC. Raw broadcast/capture. |
| `576p` | 720x576 progressive | `PAL` | PAL standard definition. DVD resolution (PAL regions). |
| `576i` | 720x576 interlaced | | Interlaced PAL. Raw broadcast/capture. |
| `SD` | Standard Definition (generic) | `sd` | Umbrella term for 480p/576p and below. |

### High Definition

| Tag | Meaning | Variations | Notes |
|-----|---------|------------|-------|
| `720p` | 1280x720 progressive | `HD`, `hd` | Entry-level HD. Good balance of quality and file size. Common for HDTV captures. |
| `1080i` | 1920x1080 interlaced | | Interlaced full HD. Common in broadcast HDTV. Two fields per frame. |
| `1080p` | 1920x1080 progressive | `FHD`, `FullHD`, `Full.HD` | Full HD. The most common resolution for Blu-ray and streaming releases. |
| `HD` | High Definition (generic) | `hd` | Umbrella term usually meaning 720p or 1080p. |
| `FHD` | Full High Definition | `FullHD` | Synonym for 1080p. |

### Ultra High Definition

| Tag | Meaning | Variations | Notes |
|-----|---------|------------|-------|
| `2160p` | 3840x2160 progressive | `4K`, `4k`, `UHD`, `Ultra.HD`, `UltraHD` | Ultra HD / 4K. Standard for UHD Blu-ray and premium streaming. Almost always paired with HDR and HEVC/x265. |
| `4K` | 3840x2160 (consumer 4K) | `4k` | Technically consumer "4K" is 3840x2160 (UHD), not true cinema 4K (4096x2160). Used interchangeably with 2160p in releases. |
| `UHD` | Ultra High Definition | `Ultra.HD`, `UltraHD` | Synonym for 2160p/4K in release context. |

### Niche

| Tag | Meaning | Variations | Notes |
|-----|---------|------------|-------|
| `540p` | 960x540 progressive | | Half of 1080p. Rare; sometimes seen in low-bitrate HDTV captures. |
| `360p` | 640x360 progressive | | Very low quality. Rarely tagged explicitly. |
| `1440p` | 2560x1440 progressive | `QHD`, `2K` | Uncommon in video releases. Primarily a monitor/gaming resolution. |
| `4320p` | 7680x4320 progressive | `8K`, `8k` | Extremely rare in releases. Almost no consumer content at this resolution. |

---

## 6. Source Tags

### Disc Sources (highest quality)

| Tag | Meaning | Variations | Notes |
|-----|---------|------------|-------|
| `Remux` | Remuxed from disc | `REMUX`, `BDRemux`, `BluRay.Remux` | Video/audio streams extracted from Blu-ray/UHD Blu-ray without re-encoding. Highest quality possible (identical to disc). Very large files (20-80 GB). |
| `BluRay` | Blu-ray disc source | `Bluray`, `BDRip`, `BRRip`, `BD`, `BDMV` | Encoded from a Blu-ray disc. Quality depends on encoding settings. `BDRip` = encoded directly from disc; `BRRip` = encoded from a pre-existing BDRip (generation loss). |
| `UHD.BluRay` | UHD Blu-ray disc source | `UHDBluRay`, `UHD.BD`, `UHD.Remux` | 4K Blu-ray source. Typically paired with 2160p, HDR, and HEVC. |
| `DVD` | DVD disc source | `DVDRip`, `DVDR`, `DVD-R`, `DVD5`, `DVD9` | Encoded from a retail DVD. `DVD5` = single-layer 4.7 GB; `DVD9` = dual-layer 8.5 GB. Maximum resolution 480p/576p. |

### Streaming / Web Sources

| Tag | Meaning | Variations | Notes |
|-----|---------|------------|-------|
| `WEB-DL` | Web download (lossless capture) | `WEBDL`, `WEB.DL`, `WEB` | Downloaded directly from streaming service (Netflix, Amazon, Disney+, etc.) without re-encoding. High quality; the stream exactly as the service delivered it. |
| `WEBRip` | Web rip (screen capture + re-encode) | `WEBRIP`, `WEB.Rip`, `WEB-Rip` | Captured from streaming via screen recording or HDMI capture, then re-encoded. Slight quality loss vs WEB-DL. Sometimes extracted via HLS/RTMP and remuxed (better quality). |
| `AMZN` | Amazon Prime Video source | `Amazon` | Source service tag. Often paired with WEB-DL or WEBRip. |
| `NF` | Netflix source | `Netflix`, `NFLX` | Source service tag. |
| `DSNP` | Disney+ source | `Disney+`, `DisneyPlus`, `DNSP` | Source service tag. |
| `ATVP` | Apple TV+ source | `AppleTV`, `ATV+` | Source service tag. Known for high bitrate streams. |
| `HMAX` | HBO Max source | `HBOMax`, `HBO` | Source service tag. |
| `HULU` | Hulu source | | Source service tag. |
| `PCOK` | Peacock source | `Peacock` | Source service tag. |
| `PMTP` | Paramount+ source | `ParamountPlus` | Source service tag. |
| `iT` | iTunes source | `iTunes` | Source service tag. Often high quality with surround audio. |
| `CR` | Crunchyroll source | `Crunchyroll` | Anime streaming service. |
| `STAN` | Stan source | | Australian streaming service. |

### TV Broadcast Sources

| Tag | Meaning | Variations | Notes |
|-----|---------|------------|-------|
| `HDTV` | HD television broadcast capture | `HDTVRip` | Captured from over-the-air or cable HD broadcast. Quality varies; may have station logos/watermarks. |
| `PDTV` | Pure Digital TV | `PDTVRip` | Captured from a digital TV broadcast via direct digital transport stream (no analog conversion). SD quality. |
| `DSR` | Digital Satellite Rip | `SATRip`, `DTH` | Captured from digital satellite broadcast. Similar quality to PDTV. |
| `SDTV` | Standard Definition TV | `TVRip` | Generic SD TV capture. Lowest broadcast quality tier. |

### Pre-Release / Low Quality Sources

| Tag | Meaning | Variations | Notes |
|-----|---------|------------|-------|
| `CAM` | Camera recording in theater | `CAMRIP`, `CAM-Rip`, `HDCAM` | Recorded with a camera in a movie theater. Lowest quality: shaky, bad audio from room mic, audience noise, parallax distortion. `HDCAM` uses an HD camera for slightly better video. |
| `TS` | Telesync | `TELESYNC`, `HDTS`, `HD-TS` | Recorded in theater with a professional camera (sometimes from projection booth). Audio often sourced from a direct line-in or assistive listening device. Better than CAM but still poor. `HDTS` = HD telesync. |
| `TC` | Telecine | `TELECINE`, `HDTC`, `HD-TC` | Captured from a film print using a telecine machine (analog reel to digital). Better quality than TS; near-DVD quality. Rare in modern era. |
| `SCR` | Screener | `SCREENER`, `DVDSCR`, `DVDScreener`, `BDSCR` | From a pre-release screener disc sent to critics/awards voters. May have watermarks, "property of" text overlays, or black-and-white sections. Near-DVD/BD quality otherwise. |
| `R5` | Region 5 retail | `R5.LINE`, `R5.AC3` | Early retail DVD release from Region 5 (Russia, etc.) with unfinished mastering. May have separate line audio (from a different source). Quality between Telecine and DVDRip. |
| `PPV` | Pay-Per-View | `PPVRip` | Captured from a pay-per-view broadcast. Quality similar to HDTV. |
| `VODRip` | Video-on-Demand rip | `VOD` | Captured from a VOD service. Quality varies. |
| `WORKPRINT` | Work print | `WP` | An unfinished version of a film. May be missing effects, music, or color grading. Collector interest only. |

---

## 7. Source Quality Hierarchy

From lowest to highest quality (approximate):

1. **CAM** -- camera in theater
2. **TS / TELESYNC** -- better camera, direct audio
3. **TC / TELECINE** -- film print transfer
4. **SCR / SCREENER** -- pre-release disc (may have watermarks)
5. **R5** -- early Region 5 retail
6. **SDTV / PDTV / DSR** -- standard-def broadcast
7. **DVDRip** -- retail DVD encode
8. **HDTV** -- HD broadcast capture
9. **WEBRip** -- captured/re-encoded from streaming
10. **WEB-DL** -- direct (untouched) streaming download
11. **BDRip / BRRip** -- encoded from Blu-ray
12. **Remux** -- untouched streams from disc (highest)

---

## 8. Edition and Release Tags

### Edition Tags

| Tag | Meaning | Variations | Notes |
|-----|---------|------------|-------|
| `Directors.Cut` | Director's cut | `DC`, `Directors`, `DirectorsCut` | Version edited to the director's vision, often with added/changed scenes vs theatrical. |
| `Extended` | Extended edition | `Extended.Cut`, `Extended.Edition`, `EXT` | Longer than theatrical release. Added scenes that were cut for time. |
| `Unrated` | Unrated version | `UNRATED` | Version not submitted to ratings board. Often contains content cut to achieve a lower rating. |
| `Theatrical` | Theatrical release version | `THEATRICAL` | The version shown in cinemas. |
| `Special.Edition` | Special edition | `SE` | May include additional content or remastered video/audio. |
| `Criterion` | Criterion Collection release | `CC` | High-quality restorations from the Criterion Collection. |
| `Remastered` | Remastered version | `REMASTERED` | Video/audio has been reprocessed from original elements. Often improved quality. |
| `Anniversary` | Anniversary edition | `Anniversary.Edition` | Re-release for a film's milestone anniversary. May be remastered. |
| `IMAX` | IMAX version | `IMAX.Edition` | May include expanded aspect ratio sequences shot in IMAX. |
| `Open.Matte` | Open matte version | `OpenMatte` | Full-frame version revealing more vertical image information than the widescreen theatrical crop. |

### Release Quality Tags

| Tag | Meaning | Variations | Notes |
|-----|---------|------------|-------|
| `PROPER` | Corrected release (replaces another group's release) | `proper` | Re-release by a different group fixing issues with the first release (wrong aspect ratio, bad encode, sync issues). |
| `REPACK` | Repacked release (replaces own earlier release) | `repack` | Same group re-releases to fix a flaw in their own earlier release. |
| `RERIP` | Re-ripped release | `rerip` | New rip from the same source to fix issues. |
| `INTERNAL` | Internal/limited release | `iNTERNAL` | Released only within a group or tracker, not intended for wide distribution. Often for niche content or duplicate releases. |
| `REAL` | Verified genuine release | `REAL.PROPER` | Confirms the release is legitimate when a fake/mislabeled release exists. |
| `NUKED` | Release has been invalidated | `NUKE` | Not a filename tag per se, but indicates the release failed quality checks by scene standards. Avoid. |

### Container and Packaging Tags

| Tag | Meaning | Variations | Notes |
|-----|---------|------------|-------|
| `MKV` | Matroska container | `mkv` | Open container format. Supports multiple audio/subtitle tracks. Standard for HD/UHD releases. |
| `MP4` | MPEG-4 Part 14 container | `M4V`, `mp4` | Common container for streaming and portable devices. Less flexible than MKV for multiple tracks. |
| `AVI` | Audio Video Interleave | `avi` | Legacy container from the XviD/DivX era. Limited metadata and codec support. |

### Language and Audio Tags

| Tag | Meaning | Variations | Notes |
|-----|---------|------------|-------|
| `DUAL` | Dual audio tracks | `Dual.Audio`, `DUAL.AUDIO`, `DualAudio` | Two language tracks included (e.g., English + Spanish). |
| `MULTI` | Multiple audio tracks | `Multi.Audio`, `MULTi`, `MULTI.AUDIO` | Three or more language tracks. Common in European releases. |
| `DUBBED` | Audio is dubbed | `DUB` | Original audio replaced with a different language dub. |
| `SUBBED` | Subtitles included | `SUB`, `SUBS` | Hardcoded or soft subtitles in one or more languages. |
| `HC` | Hardcoded subtitles | `HARDCODED`, `HardSub` | Subtitles burned into the video stream (cannot be turned off). Common in screener releases. |

### Miscellaneous Tags

| Tag | Meaning | Variations | Notes |
|-----|---------|------------|-------|
| `HYBRID` | Hybrid source | `Hybrid` | Combines multiple sources (e.g., WEB-DL video + Blu-ray audio). Used when one source has better video and another has better audio. |
| `3D` | Stereoscopic 3D | `3D.HSBS`, `3D.HOU`, `3D.SBS`, `3D.TAB` | 3D video. HSBS = Half Side-by-Side, HOU = Half Over-Under. |
| `HDR.DV` | Contains both HDR10 and Dolby Vision | `DoVi.HDR10` | Dual HDR format for maximum compatibility. |
| `LINE` | Line audio | `LINE.AUDIO` | Audio sourced from a direct audio jack rather than a microphone. Paired with CAM/TS video for better audio quality. |
| `COMPLETE` | Complete series/season | `COMPLETE.SERIES` | All episodes included. |
| `SAMPLE` | Sample file | | Short excerpt, not the full release. Usually 30-90 seconds. |

---

## 9. Common Filename Patterns

Release filenames follow a general structure:

```
Title.Year.Resolution.Source.AudioCodec.VideoCodec-GROUP
Title.Year.Resolution.Source.HDR.AudioCodec.VideoCodec-GROUP
```

Examples:

```
Movie.Name.2024.2160p.UHD.BluRay.Remux.HDR10.DV.DTS-HD.MA.7.1-GROUP
Movie.Name.2024.1080p.BluRay.x264.DTS-GROUP
Movie.Name.2024.1080p.WEB-DL.DD+5.1.H.264-GROUP
Movie.Name.2024.2160p.AMZN.WEB-DL.DDP5.1.Atmos.DV.H.265-GROUP
Show.Name.S03E05.Episode.Title.720p.HDTV.x264-GROUP
Movie.Name.2024.Directors.Cut.1080p.BluRay.x265.DTS-HD.MA.5.1-GROUP
Movie.Name.2024.2160p.WEB-DL.DDP5.1.DV.HDR10.H.265-GROUP
```

---

## 10. Quick Quality Reference

### Video Codec Quality Tiers (for equivalent bitrate)

1. **AV1** -- best compression efficiency
2. **HEVC / x265** -- excellent, standard for 4K
3. **H.264 / x264** -- very good, most compatible
4. **VP9** -- comparable to HEVC
5. **MPEG-4 ASP (XviD/DivX)** -- legacy, poor by modern standards
6. **MPEG-2** -- legacy, large files

### Audio Quality Tiers

1. **LPCM** -- uncompressed (highest, largest)
2. **DTS-HD MA / TrueHD / FLAC** -- lossless (identical to master)
3. **DTS-X / TrueHD Atmos** -- lossless + spatial
4. **DTS-HD HRA** -- high-res lossy
5. **DD+ Atmos / EAC3 Atmos** -- lossy + spatial
6. **DD+ / EAC3** -- enhanced lossy
7. **DTS (core) / AC3** -- standard lossy surround
8. **AAC** -- efficient lossy (good for streaming)
9. **MP3 / OGG / Opus** -- general lossy (compact)
