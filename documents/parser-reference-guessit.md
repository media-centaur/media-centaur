---
title: "Parser Reference: guessit"
sources:
  - https://github.com/guessit-io/guessit
  - https://github.com/guessit-io/guessit/blob/develop/guessit/config/options.json
  - https://github.com/guessit-io/guessit/tree/develop/guessit/rules/properties
  - https://github.com/guessit-io/guessit/blob/develop/guessit/test/movies.yml
  - https://github.com/guessit-io/guessit/blob/develop/guessit/test/episodes.yml
date_accessed: 2026-03-12
category: parser-reference
---

# guessit - Video Filename Parser (Python)

The most comprehensive open-source video filename parser. Uses the Rebulk pattern
matching library with patterns defined in `config/options.json` and rule logic in
`rules/properties/*.py`.

## Video Codecs

| Pattern | Maps To |
|---------|---------|
| `x264`, `h264`, `h-264`, `x-264`, `[hx]-?264` | H.264 |
| `(MPEG-?4)?AVC(?:HD)?` | H.264 |
| `x265`, `h265`, `h-265`, `x-265`, `[hx]-?265` | H.265 |
| `HEVC` | H.265 |
| `hevc10` (combined) | H.265 + 10-bit |
| `[hx]-?263` | H.263 |
| `[hx]-?262`, `Mpe?g-?2` | MPEG-2 |
| `XviD` | Xvid |
| `DVDivX`, `DivX` | DivX |
| `VC-?1` | VC-1 |
| `VP7` | VP7 |
| `VP8`, `VP80` | VP8 |
| `VP9` | VP9 |
| `Rv\d{2}` | RealVideo |

### Color Depth

- 8-bit, 10-bit, 12-bit (patterns: `8bit`, `10bit`, `12bit`, `10-bit`, etc.)

### Video Profiles

- BP (Baseline), MP (Main), HP (High), etc.

## Audio Codecs

| Pattern | Maps To |
|---------|---------|
| `MP3`, `LAME`, `LAME\d+-?\d+` | MP3 |
| `MP2` | MP2 |
| `Dolby`, `DD`, `AC-?3` | Dolby Digital |
| `DDP`, `DD\+`, `E-?AC-?3` | Dolby Digital Plus |
| `True-?HD` | Dolby TrueHD |
| `Atmos`, `Dolby-?Atmos` | Dolby Atmos |
| `AAC` | AAC |
| `FLAC` | FLAC |
| `DTS` | DTS |
| `DTS-?HD` | DTS-HD |
| `DTS:X`, `DTS-X`, `DTSX` | DTS:X |
| `Opus` | Opus |
| `Vorbis` | Vorbis |
| `PCM` | PCM |
| `LPCM` | LPCM |

### Audio Profiles

| Profile | Context | Patterns |
|---------|---------|----------|
| Master Audio | DTS-HD | `MA` |
| High Resolution Audio | DTS-HD | `HR`, `HRA` |
| Extended Surround | DTS | `ES` |
| High Efficiency | AAC | `HE` |
| Low Complexity | AAC | `LC` |
| High Quality | Dolby Digital | `HQ` |
| EX | Dolby Digital | `EX` |

### Audio Channels

- `1.0`, `2.0`, `5.1`, `7.1` (regex-matched with context)

## Screen Size / Resolution

| Pattern | Maps To |
|---------|---------|
| `4k` | 2160p |
| `\d{3,4}p` (e.g. `720p`, `1080p`) | progressive scan |
| `\d{3,4}i` (e.g. `1080i`) | interlaced scan |
| `\d{3,4}-?[x*]-?\d{3,4}` (e.g. `1920x1080`) | explicit WxH |
| Frame rates: `\d+-?(?:p\|fps)` (e.g. `24fps`, `60p`) | frame rate |

## Sources / Origins

| Pattern | Maps To |
|---------|---------|
| `VHS` | VHS |
| `CAM` | Camera |
| `HD-?CAM` | HD Camera |
| `TELESYNC`, `TS` | Telesync |
| `HD-?TELESYNC`, `HD-?TS` | HD Telesync |
| `WORKPRINT`, `WP` | Workprint |
| `TELECINE`, `TC` | Telecine |
| `HD-?TELECINE`, `HD-?TC` | HD Telecine |
| `PPV` | Pay-per-view |
| `SD-?TV` | TV |
| `DVB`, `PD-?TV` | Digital TV |
| `DVD`, `VIDEO-?TS`, `DVD-R`, `DVD-9`, `DVD-5` | DVD |
| `DM` | Digital Master |
| `HD-?TV` | HDTV |
| `VOD` | Video on Demand |
| `WEB`, `WEB-DL`, `WEB-UHD`, `DL-WEB`, `DL-Mux` | Web |
| `WEB-Cap` | Web |
| `HD-?DVD` | HD-DVD |
| `Blu-?ray`, `BD`, `BD[59]`, `BD25`, `BD50` | Blu-ray |
| `Ultra-?Blu-?ray` | Ultra HD Blu-ray |
| `AHDTV` | Analog HDTV |
| `UHD-?TV` | Ultra HDTV |
| `DSR`, `DTH` | Satellite |

Rip suffixes: any source + `-?Rip` (e.g. `DVDRip`, `BDRip`, `HDTVRip`, `WEBRip`)

## Editions

| Pattern | Maps To |
|---------|---------|
| `collector`, `collector's-edition` | Collector |
| `special-edition`, `se` | Special |
| `ddc` | Director's Definitive Cut |
| `CC`, `Criterion`, `criterion-edition` | Criterion |
| `deluxe`, `deluxe-edition` | Deluxe |
| `limited-edition` | Limited |
| `theatrical`, `theatrical-cut` | Theatrical |
| `DC`, `director's-cut` | Director's Cut |
| `extended-cut`, `extended-version` | Extended |
| Alternative Cut | Alternative Cut |
| `Remastered`, `4K Remastered` | Remastered |
| `Restored`, `4K Restored` | Restored |
| `Uncensored` | Uncensored |
| `Uncut` | Uncut |
| `Unrated` | Unrated |
| `IMAX` | IMAX |
| `Fan` | Fan |
| `Ultimate` | Ultimate |
| `Ultimate Collector` | Ultimate Collector |
| `Ultimate Fan` | Ultimate Fan |

## Other Tags

| Pattern | Maps To |
|---------|---------|
| `Audio-?Fix`, `Audio-?Fixed` | Audio Fixed |
| `Sync-?Fix`, `Sync-?Fixed` | Sync Fixed |
| `Dual`, `Dual-?Audio` | Dual Audio |
| `ws`, `wide-?screen` | Widescreen |
| `Re-?Enc(?:oded)?` | Reencoded |
| `Proper`, `Real` | Proper |
| `Fix`, `Fixed`, `Dirfix`, `Nfofix`, `Prooffix` | Fix |
| `Fansub` | Fan Subtitled |
| `Fastsub` | Fast Subtitled |
| `R5` | Region 5 |
| `RC` | Region C |
| `Pre-?Air` | Preair |
| `Screener`, `Scr(?:eener)?` | Screener |
| `Remux` | Remux |
| `Hybrid` | Hybrid |
| `PAL` | PAL |
| `SECAM` | SECAM |
| `NTSC` | NTSC |
| `XXX` | XXX |
| `2in1` | 2in1 |
| `3D` | 3D |
| `HQ` | High Quality |
| `HR` | High Resolution |
| `LD` | Line Dubbed |
| `MD` | Mic Dubbed |
| `mHD`, `HDLight` | Micro HD |
| `LDTV` | Low Definition |
| `HFR` | High Frame Rate |
| `VFR` | Variable Frame Rate |
| `HD` | HD |
| `FHD`, `Full-?HD` | Full HD |
| `UHD`, `Ultra-?(?:HD)?` | Ultra HD |
| `Upscaled?` | Upscaled |
| `Complet`, `Complete` | Complete |
| `Classic` | Classic |
| `Bonus` | Bonus |
| `Trailer` | Trailer |
| `Retail` | Retail |
| `Colorized` | Colorized |
| `Internal` | Internal |
| `LiNE` | Line Audio |
| `Read-?NFO` | Read NFO |
| `CONVERT` | Converted |
| `DOCU`, `DOKU` | Documentary |
| `OM`, `Open-?Matte` | Open Matte |
| `STV` | Straight to Video |
| `OAR` | Original Aspect Ratio |
| `VO`, `OV` | Original Video |
| `Ova`, `Oav` | Original Animated Video |
| `Ona` | Original Net Animation |
| `Oad` | Original Animation DVD |
| `Mux` | Mux |
| `HC`, `vost` | Hardcoded Subtitles |
| `SDR` | Standard Dynamic Range |
| `HDR(?:10)?` | HDR10 |
| `Dolby-?Vision`, `DV` | Dolby Vision |
| `BT-?2020` | BT.2020 |
| `Sample` | Sample |
| `Extras`, `Digital-?Extras?` | Extras |
| `Proof` | Proof |
| `Obfuscated`, `Scrambled` | Obfuscated |
| `xpost`, `postbot`, `asrequested` | Repost |

## Container Formats

### Video
3g2, 3gp, 3gp2, asf, avi, divx, flv, iso, m4v, mk2, mk3d, mka, mkv, mov, mp4,
mp4a, mpeg, mpg, ogg, ogm, ogv, qt, ra, ram, rm, ts, m2ts, vob, wav, webm, wma, wmv

### Subtitles
srt, idx, sub, ssa, ass

### Info
nfo

### Other
torrent, nzb

## Streaming Services (150+)

| Service | Detection Patterns |
|---------|-------------------|
| 9Now | `9NOW` |
| A&E | `AE`, `A&E` |
| ABC | `AMBC` |
| ABC Australia | `AUBC` |
| Al Jazeera English | `AJAZ` |
| AMC | `AMC` |
| Amazon Prime | `AMZN`, `AMZN-CBR`, `Amazon`, `Amazon-?Prime` |
| Adult Swim | `AS`, `Adult-?Swim` |
| America's Test Kitchen | `ATK` |
| Animal Planet | `ANPL` |
| AnimeLab | `ANLB` |
| AOL | `AOL` |
| AppleTV | `ATVP`, `ATV+`, `APTV` |
| ARD | `ARD` |
| BBC iPlayer | `iP`, `BBC-?iPlayer` |
| Binge | `BNGE` |
| Blackpills | `BKPL` |
| BluTV | `BLU` |
| Boomerang | `BOOM` |
| BravoTV | `BRAV` |
| Canal+ | `CNLP` |
| Cartoon Network | `CN` |
| CBC | `CBC` |
| CBS | `CBS` |
| CNBC | `CNBC` |
| Comedy Central | `CC`, `Comedy-?Central` |
| Channel 4 | `ALL4`, `4OD` |
| CHRGD | `CHGD` |
| Cinemax | `CMAX` |
| Country Music Television | `CMT` |
| Comedians in Cars Getting Coffee | `CCGC` |
| Crave | `CRAV` |
| Crunchyroll | `CR`, `Crunchy-?Roll` |
| Crackle | `CRKL` |
| CSpan | `CSPN` |
| CTV | `CTV` |
| CuriosityStream | `CUR` |
| CWSeed | `CWS` |
| Daisuki | `DSKI` |
| DC Universe | `DCU` |
| Deadhouse Films | `DHF` |
| DramaFever | `DF`, `DramaFever` |
| Digiturk Diledigin Yerde | `DDY` |
| Discovery | `DISC`, `Discovery` |
| Discovery Plus | `DSCP` |
| Disney | `DSNY`, `Disney` |
| Disney+ | `DSNP` |
| DIY Network | `DIY` |
| Doc Club | `DOCC` |
| DPlay | `DPLY` |
| E! | `ETV` |
| ePix | `EPIX` |
| El Trece | `ETTV` |
| ESPN | `ESPN` |
| Esquire | `ESQ` |
| Facebook Watch | `FBWatch` |
| Family | `FAM` |
| Family Jr | `FJR` |
| Fandor | `FANDOR` |
| Food Network | `FOOD` |
| Fox | `FOX` |
| Fox Premium | `FOXP` |
| Foxtel | `FXTL` |
| Freeform | `FREE` |
| FYI Network | `FYI` |
| GagaOOLala | `Gaga` |
| Global | `GLBL` |
| GloboSat Play | `GLOB` |
| Hallmark | `HLMK` |
| HBO Go | `HBO`, `HBO-?Go` |
| HBO Max | `HMAX` |
| HGTV | `HGTV` |
| History | `HIST`, `History` |
| Hulu | `HULU` |
| Investigation Discovery | `ID` |
| IFC | `IFC` |
| hoichoi | `HoiChoi` |
| iflix | `IFX` |
| iQIYI | `iQIYI` |
| iTunes | `iTunes`, `iT` (case-sensitive) |
| ITV | `ITV` |
| Knowledge Network | `KNOW` |
| Lifetime | `LIFE` |
| Motor Trend OnDemand | `MTOD` |
| MBC | `MBC`, `MBCVOD` |
| MSNBC | `MNBC` |
| MTV | `MTV` |
| MUBI | `MUBI` |
| National Audiovisual Institute | `INA` |
| National Film Board | `NFB` |
| National Geographic | `NATG`, `National-?Geographic` |
| NBA TV | `NBA`, `NBA-?TV` |
| NBC | `NBC` |
| Netflix | `NF`, `Netflix` |
| NFL | `NFL` |
| NFL Now | `NFLN` |
| NHL GameCenter | `GC` |
| Nickelodeon | `NICK`, `Nickelodeon`, `NICKAPP` |
| Norsk Rikskringkasting | `NRK` |
| OnDemandKorea | `ODK`, `OnDemandKorea` |
| Opto | `OPTO` |
| Oprah Winfrey Network | `OWN` |
| Paramount+ | `PMTP`, `PMNP`, `PMT+`, `Paramount+`, `ParamountPlus` |
| PBS | `PBS` |
| PBS Kids | `PBSK` |
| Peacock | `PCOK`, `Peacock` |
| Playstation Network | `PSN` |
| Pluzz | `PLUZ` |
| PokerGO | `POGO` |
| Rakuten TV | `RKTN` |
| The Roku Channel | `ROKU` |
| RTE One | `RTE` |
| RUUTU | `RUUTU` |
| SBS | `SBS` |
| Science Channel | `SCI` |
| SeeSo | `SESO`, `SeeSo` |
| Shomi | `SHMI` |
| Showtime | `SHO` |
| Sony | `SONY` |
| Spike | `SPIK` |
| Spike TV | `SPKE`, `Spike-?TV` |
| Sportsnet | `SNET` |
| Sprout | `SPRT` |
| Stan | `STAN` |
| Starz | `STZ` |
| Sveriges Television | `SVT` |
| SwearNet | `SWER` |
| Syfy | `SYFY` |
| TBS | `TBS` |
| TFou | `TFOU` |
| The CW | `CW`, `The-?CW` |
| TLC | `TLC` |
| TubiTV | `TUBI` |
| TV3 Ireland | `TV3` |
| TV4 Sweden | `TV4` |
| TVING | `TVING` |
| TV Land | `TVL`, `TV-?Land` |
| TVNZ | `TVNZ` |
| UFC | `UFC` |
| UFC Fight Pass | `FP` |
| UKTV | `UKTV` |
| Univision | `UNIV` |
| USA Network | `USAN` |
| Velocity | `VLCT` |
| VH1 | `VH1` |
| Viceland | `VICE` |
| Viki | `VIKI` |
| Vimeo | `VMEO` |
| VRV | `VRV` |
| W Network | `WNET` |
| WatchMe | `WME` |
| WWE Network | `WWEN` |
| Xbox Video | `XBOX` |
| Yahoo | `YHOO` |
| YouTube Red | `RED` |
| ZDF | `ZDF` |

## Real-World Test Cases (Movies)

Selected examples from guessit's test suite showing expected parse results:

```
Fear.and.Loathing.in.Las.Vegas.720p.HDDVD.DTS.x264-ESiR.mkv
  -> title: "Fear and Loathing in Las Vegas", resolution: 720p, source: HD-DVD, audio: DTS, codec: H.264

Dark.City.(1998).DC.BDRip.720p.DTS.X264-CHD.mkv
  -> title: "Dark City", year: 1998, resolution: 720p, source: Blu-ray, audio: DTS, codec: H.264

Borat.(2006).R5.PROPER.REPACK.DVDRip.XviD-PUKKA.avi
  -> title: "Borat", year: 2006, source: DVD, codec: Xvid, other: [Region 5, Proper]

Battle.Royale.(2000).(Special.Edition).CD1of2.DVDRiP.XviD-[ZeaL].avi
  -> title: "Battle Royale", year: 2000, edition: Special, cd: 1/2, source: DVD, codec: Xvid

Sample.Movie.(1982).(Director's.Cut).CD1.DVDRip.XviD.AC3-WAF.avi
  -> title: "Sample Movie", year: 1982, edition: Director's Cut, source: DVD, codec: Xvid

2001.A.Space.Odyssey.1968.HDDVD.1080p.DTS.x264.mkv
  -> title: "2001 A Space Odyssey", year: 1968, source: HD-DVD, resolution: 1080p

2012.2009.720p.BluRay.x264.DTS WiKi.mkv
  -> title: "2012", year: 2009, resolution: 720p, source: Blu-ray (title starts with number)

Pacific.Rim.3D.2013.COMPLETE.BLURAY-PCH.avi
  -> title: "Pacific Rim", year: 2013, other: [3D, Complete], source: Blu-ray
```

## Real-World Test Cases (TV Episodes)

```
Californication.2x05.Vaginatown.HDTV.XviD-0TV.avi
  -> title: "Californication", season: 2, episode: 5, source: HDTV, codec: Xvid

The.Big.Bang.Theory.S01E01.mkv
  -> title: "The Big Bang Theory", season: 1, episode: 1

new.girl.117.hdtv-lol.mp4
  -> title: "new girl", season: 1, episode: 17, source: HDTV

Doctor Who (2005) - S06E01 - The Impossible
  -> title: "Doctor Who", year: 2005, season: 6, episode: 1

Kaamelott - 5x44x45x46x47x48x49x50.avi
  -> title: "Kaamelott", season: 5, episodes: 44-50

The Sopranos - [05x07] - In Camelot.mp4
  -> title: "The Sopranos", season: 5, episode: 7

Duckman - 101 (01) - 20021107 - I, Duckman.avi
  -> title: "Duckman", season: 1, episode: 1 (3-digit compact: 101 = S01E01)

South.Park.4x07.Cherokee.Hair.Tampons.DVDRip
  -> title: "South Park", season: 4, episode: 7, source: DVD
```

## Season/Episode Pattern Formats

guessit recognizes these episode numbering conventions:
- `S01E05` (standard)
- `1x05` (compact)
- `S01E05E06` or `S01E05-E06` (multi-episode)
- `101` or `1x01` (3-digit compact)
- `S01` alone (season pack)
- `E05` alone (episode only)
- `5x44x45x46x47x48x49x50` (multi-episode with x separator)
- `[05x07]` (bracketed)
- `S01Extras` (extras/bonus)
