---
title: Streaming Service Tags in Video Release Filenames
category: tag-reference
date_accessed: 2026-03-12
sources:
  - name: TRaSH Guides - Sonarr Custom Formats Collection
    url: https://trash-guides.info/Sonarr/sonarr-collection-of-custom-formats/
  - name: TRaSH Guides - Radarr Custom Formats Collection
    url: https://trash-guides.info/Radarr/Radarr-collection-of-custom-formats/
  - name: TRaSH Guides GitHub - Sonarr Custom Formats
    url: https://github.com/TRaSH-Guides/Guides/blob/master/docs/Sonarr/sonarr-collection-of-custom-formats.md
  - name: TRaSH Guides GitHub - Radarr Custom Formats
    url: https://github.com/TRaSH-Guides/Guides/blob/master/docs/Radarr/Radarr-collection-of-custom-formats.md
  - name: Streaming Service Abbreviation (pandamoon21 gist)
    url: https://gist.github.com/pandamoon21/6fd124010f2e5e270b5089f77bc47355
  - name: Video Torrent Acronyms (rubenhortas gist)
    url: https://gist.github.com/rubenhortas/d7006be931a3b17f7163cb37e027cedf
  - name: Wikipedia - Pirated Movie Release Types
    url: https://en.wikipedia.org/wiki/Pirated_movie_release_types
---

# Streaming Service Tags in Video Release Filenames

This document catalogs the abbreviated service tags embedded in WEB-DL and WEBRip
release filenames. These tags identify which streaming platform a video was sourced from.

**Filename placement:** The service tag appears before the source type tag, e.g.:

    Movie.Title.2024.DSNP.WEB-DL.1080p.DDP5.1.H.264-GROUP
    Show.Name.S01E01.AMZN.WEB-DL.2160p.DV.HDR.DDP5.1.H.265-GROUP

## Major Global Services

| Tag    | Service Name         | Notes |
|--------|----------------------|-------|
| AMZN   | Amazon Prime Video   | Most common Amazon tag |
| AMZ    | Amazon Prime Video   | Alternate tag, less common |
| ATVP   | Apple TV+            | Premium originals |
| ATV    | Apple TV             | Non-originals / purchases (not Apple TV+) |
| APTV   | Apple TV+            | Rare alternate for ATVP |
| DSNP   | Disney+              | Standard tag |
| DNSP   | Disney+              | Alternate/typo variant |
| DISNEY | Disney+              | Rare long-form tag |
| HMAX   | HBO Max              | Deprecated: service rebranded to Max (2023) |
| MAX    | Max                  | Current tag after HBO Max rebrand |
| HBO    | HBO / HBO Go         | Legacy HBO streaming content |
| HBOM   | HBO Max              | Alternate HBO Max tag |
| NF     | Netflix              | Most common Netflix tag |
| NFLX   | Netflix              | Alternate tag |
| PMTP   | Paramount+           | Standard Paramount+ tag |
| PMNP   | Paramount+           | Alternate tag |
| PMNT   | Paramount Network    | Linear network, not the streaming service |
| PARA   | Paramount            | Generic Paramount tag |
| PCOK   | Peacock              | NBC's Peacock service |
| PCKL   | Peacock              | Rare alternate |
| HULU   | Hulu                 | |
| iT     | iTunes               | Apple's download/rental store |
| ROKU   | The Roku Channel     | |
| BCORE  | Bravia Core          | Sony's high-bitrate streaming; premium quality |
| MA     | Movies Anywhere      | Higher quality source material |
| CRiT   | Criterion Channel    | Curated classic/art-house films; high quality |
| CRIT   | Criterion Channel    | Alternate capitalization |
| PLAY   | Google Play          | |
| MUBI   | MUBI                 | Art-house / curated cinema |
| OViD   | OViD                 | Independent/documentary streaming |
| Qibi   | Quibi                | Defunct (2020); short-form mobile streaming |
| RED    | YouTube Premium      | Originally "YouTube Red" |
| TUBI   | Tubi                 | Free ad-supported |
| PLTO   | Pluto TV             | Free ad-supported |

## US Cable / Broadcast Network Services

| Tag    | Service Name         | Notes |
|--------|----------------------|-------|
| AMBC   | ABC (US)             | |
| AMC    | AMC / AMC+           | |
| ANPL   | Animal Planet        | |
| AE     | A&E                  | |
| AS     | Adult Swim           | |
| ATK    | America's Test Kitchen | |
| BET    | BET+                 | |
| BOOM   | Boomerang            | |
| BRAV   | BravoTV              | |
| CBS    | CBS / Paramount+     | Legacy CBS tag |
| CC     | Comedy Central       | |
| CMAX   | Cinemax              | |
| CMDY   | Comedy Central       | Rare alternate |
| CMT    | CMT                  | |
| CN     | Cartoon Network      | |
| CNBC   | CNBC                 | |
| COOK   | Cooking Channel      | |
| CW     | The CW               | |
| CWS    | CW Seed              | |
| DCU    | DC Universe          | Now largely merged into Max |
| DHF    | DHF                  | |
| DISC   | Discovery Channel    | |
| DSCP   | Discovery+           | Discovery's streaming platform |
| DIY    | DIY Network          | |
| DOCC   | Documentary Channel  | |
| DPLY   | Dplay                | |
| EPIX   | Epix / MGM+          | Rebranded to MGM+ (2023) |
| ESPN   | ESPN / ESPN+         | |
| ESQ    | Esquire Network      | |
| FAM    | Freeform             | |
| FOOD   | Food Network         | |
| FOX    | Fox / Tubi           | |
| FREE   | Freeform / Freevee   | |
| FYI    | FYI                  | |
| HGTV   | HGTV                 | |
| HIST   | History Channel      | |
| ID     | Investigation Discovery | |
| IFC    | IFC                  | |
| LIFE   | Lifetime             | |
| LN     | LMN (Lifetime Movies)| |
| MNBC   | MSNBC                | |
| MTOD   | Motor Trend OnDemand | |
| MTV    | MTV                  | |
| NATG   | National Geographic  | |
| NBA    | NBA TV               | |
| NBC    | NBC                  | |
| NFLN   | NFL Network          | |
| NFL    | NFL                  | |
| NICK   | Nickelodeon          | |
| OWN    | OWN                  | |
| PBS    | PBS                  | |
| PBSK   | PBS Kids             | |
| SHO    | Showtime             | Merging into Paramount+ |
| SHOW   | Showtime             | Alternate tag |
| SPIK   | Spike / Paramount Network | Legacy; now PMNT |
| STZ    | Starz                | |
| SYFY   | Syfy                 | |
| TBS    | TBS                  | |
| TLC    | TLC                  | |
| TRVL   | Travel Channel       | |
| TVL    | TV Land              | |
| UFC    | UFC Fight Pass       | |
| UNIV   | Univision            | |
| VH1    | VH1                  | |
| VICE   | Vice TV              | |
| WNET   | WNET / PBS           | |
| WME    | WME                  | |

## Sports Streaming

| Tag    | Service Name         | Notes |
|--------|----------------------|-------|
| CSPN   | C-SPAN               | |
| DAZN   | DAZN                 | Global sports streaming |
| ESPN   | ESPN+                | |
| NBA    | NBA League Pass      | |
| NFL    | NFL+                 | |
| NFLN   | NFL Network          | |
| UFC    | UFC Fight Pass       | |

## UK / Ireland Services

| Tag    | Service Name         | Notes |
|--------|----------------------|-------|
| iP     | BBC iPlayer          | |
| ITVX   | ITVX                 | Replaced ITV Hub (2022) |
| ITV    | ITV Hub              | Deprecated; now ITVX |
| ALL4   | All 4 / Channel 4    | |
| 4OD    | 4oD (Channel 4)      | Legacy tag; replaced by ALL4 |
| MY5    | My5 (Channel 5)      | |
| NOW    | NOW (Sky)            | Sky's streaming service |
| UKTV   | UKTV Play            | |
| RTE    | RTE Player           | Ireland |

## Australian / New Zealand Services

| Tag    | Service Name         | Notes |
|--------|----------------------|-------|
| AUBC   | ABC iview (Australia)| Australian Broadcasting Corporation |
| BINGE  | Binge                | Australian streaming service |
| FXTL   | Foxtel Now           | Australian pay-TV streaming |
| KAYO   | Kayo Sports          | Australian sports streaming |
| SBS    | SBS On Demand        | Australian public broadcaster |
| STAN   | Stan                 | Australian streaming service |
| TEN    | Network 10 / 10 Play | |
| GLBL   | Global TV            | |
| 9NOW   | 9Now                 | Australian free-to-air catch-up |

## Canadian Services

| Tag    | Service Name         | Notes |
|--------|----------------------|-------|
| CBC    | CBC Gem              | |
| CRAV   | Crave                | Bell Media's streaming service |
| CTV    | CTV                  | |
| SNET   | Sportsnet            | |

## European Services

| Tag    | Service Name         | Notes |
|--------|----------------------|-------|
| ARD    | ARD Mediathek        | German public broadcaster |
| ZDF    | ZDF Mediathek        | German public broadcaster |
| CNLP   | Canal+               | French pay-TV |
| CMORE  | C More               | Nordic streaming service |
| MyCANAL| MyCanal              | Canal+ streaming platform (France) |
| SALTO  | Salto                | Defunct (2023); French joint venture (TF1/M6/France TV) |
| AUViO  | RTBF Auvio           | Belgian French-language public broadcaster |
| NRK    | NRK TV               | Norwegian public broadcaster |
| SVT    | SVT Play             | Swedish public broadcaster |
| TV3    | TV3 Play             | Nordic |
| TV4    | TV4 Play             | Swedish |
| NLZ    | NLZiet               | Dutch streaming aggregator |
| VDL    | Videoland            | Dutch streaming service (RTL) |
| Pathe  | Pathe Thuis          | Dutch film streaming |
| RTBF   | RTBF                 | Belgian French broadcaster |
| PLUZ   | Pluzz (France TV)    | Deprecated; now france.tv |
| TFOU   | TFou (TF1)           | French children's content |
| A3P    | Atresplayer          | Spanish streaming service |
| SWER   | SwearNet             | |

## Asian Services

| Tag    | Service Name         | Notes |
|--------|----------------------|-------|
| HTSR   | Disney+ Hotstar      | India/Southeast Asia; rebranding to JioHotstar in India |
| HS     | Hotstar              | Alternate tag |
| TVING  | TVING                | Korean streaming service (CJ ENM) |
| WAVVE  | Wavve                | Korean streaming service |
| WATCHA | Watcha               | Korean streaming service |
| CPNG   | Coupang Play         | Korean streaming service |
| KBS    | KBS                  | Korean Broadcasting System |
| IMBC   | iMBC                 | Korean |
| KCW    | Kocowa               | Korean content for international audiences |
| ODK    | OnDemandKorea        | |
| VIU    | Viu                  | Hong Kong-based; Pan-Asian |
| WETV   | WeTV                 | Tencent's international streaming |
| iQIYI  | iQIYI                | Chinese streaming (Baidu) |
| BILI   | Bilibili             | Chinese video/anime platform |
| B-Global| Bilibili Global     | International Bilibili |
| FOD    | Fuji TV FOD          | Japanese |
| TVer   | TVer                 | Japanese catch-up TV |
| U-NEXT | U-NEXT               | Japanese streaming service |
| AJAZ   | Al Jazeera English   | |

## Anime-Focused Services

| Tag    | Service Name         | Notes |
|--------|----------------------|-------|
| CR     | Crunchyroll          | |
| FUNI   | Funimation           | Deprecated; merged into Crunchyroll (2024) |
| HIDIVE | HIDIVE               | Sentai Filmworks' streaming service |
| VRV    | VRV                  | Defunct (2023); was Crunchyroll bundle service |
| ABEMA  | ABEMA                | Japanese anime/variety streaming |
| ADN    | Anime Digital Network | French anime streaming |
| ANLB   | AnimeLab             | Defunct; merged into Funimation/Crunchyroll |
| WKN    | Wakanim              | Defunct; merged into Crunchyroll |

## Other / Niche Services

| Tag    | Service Name         | Notes |
|--------|----------------------|-------|
| CRKL   | Crackle              | Free ad-supported (Sony) |
| DEST   | Destination America  | |
| DDY    | Daddy                | |
| DTV    | DirecTV              | |
| ETV    | E! Entertainment     | |
| ETTV   | ETTV                 | |
| GO90   | Go90                 | Defunct (2018); Verizon's mobile video |
| GC     | Golf Channel         | |
| GLOB   | Globo / Globoplay    | Brazilian streaming |
| HIDI   | History Detectives   | |
| HLMK   | Hallmark Channel     | |
| PSN    | PlayStation Network  | |
| RSTR   | Roadster             | |
| SESO   | Seeso                | Defunct (2017); NBC comedy streaming |
| SHMI   | Shomi                | Defunct (2016); Canadian streaming |
| SPRT   | Sprout               | Now Universal Kids |
| STRP   | Star+                | Defunct (2024); merged into Disney+ |
| STRT   | Star+                | Alternate tag |
| VMEO   | Vimeo                | |
| WWEN   | WWE Network          | Now part of Peacock (US) |
| XBOX   | Xbox Video           | Now Microsoft Movies & TV |
| YHOO   | Yahoo! View          | Defunct |
| BKPL   | Blackpills           | |
| AOL    | AOL                  | |
| CHGD   | CHRGD                | |
| CCGC   | CCGC                 | |

## Deprecated / Renamed Tags

Services that have been renamed or shut down. Old tags may still appear in legacy releases.

| Old Tag | Was              | Status |
|---------|------------------|--------|
| HMAX    | HBO Max          | Rebranded to **Max** (May 2023); new tag: `MAX` |
| FUNI    | Funimation       | Merged into **Crunchyroll** (April 2024); new tag: `CR` |
| VRV     | VRV              | Shut down (November 2023); content moved to Crunchyroll |
| ANLB    | AnimeLab         | Merged into Funimation, then Crunchyroll |
| WKN     | Wakanim          | Merged into Crunchyroll (March 2022) |
| DCU     | DC Universe      | Video content moved to **Max** (2021) |
| SALTO   | Salto            | Shut down (March 2023) |
| STRP    | Star+            | Merged into **Disney+** (June 2024) |
| Qibi    | Quibi            | Shut down (December 2020); content sold to Roku |
| GO90    | Go90             | Shut down (July 2018) |
| SESO    | Seeso            | Shut down (November 2017) |
| SHMI    | Shomi            | Shut down (November 2016) |
| YHOO    | Yahoo! View      | Shut down (2019) |
| XBOX    | Xbox Video       | Rebranded to Microsoft Movies & TV |
| SPIK    | Spike            | Rebranded to **Paramount Network** (2018); tag: `PMNT` |
| RED     | YouTube Red      | Rebranded to **YouTube Premium** (2018) |
| 4OD     | 4oD              | Rebranded to **All 4** (2015); tag: `ALL4` |
| ITV     | ITV Hub          | Rebranded to **ITVX** (December 2022) |
| EPIX    | Epix             | Rebranded to **MGM+** (January 2023) |
| PLUZ    | Pluzz            | Rebranded to **france.tv** |
| CWS     | CW Seed          | Shut down (2019); absorbed into CW app |
| FREE    | Freevee          | Shut down (2024); content moved to Prime Video |
| WWEN    | WWE Network (US) | Moved to **Peacock** (March 2021); international standalone ended 2025 |
| HTSR    | Disney+ Hotstar  | Rebranding to **JioHotstar** in India (2025) |
| SHO     | Showtime         | Merging into **Paramount+** (2023-2024) |

## Notes

### Tag Placement in Filenames

The service tag appears between the resolution/year and the source type:

    Title.Year.SERVICE.WEB-DL.Resolution.Audio.Codec-GROUP

For example:
- `Sample Movie Thirteen.Part.Two.2024.AMZN.WEB-DL.2160p.DV.HDR.DDP5.1.Atmos.H.265-GROUP`
- `Shogun.S01E01.DSNP.WEB-DL.1080p.DDP5.1.H.264-GROUP`

### WEB-DL vs WEBRip

- **WEB-DL**: Losslessly captured from the streaming service (decrypted stream).
- **WEBRip**: Screen-captured or re-encoded from a streaming source. Lower quality.

Both carry a service tag when the source is known.

### Quality Tiers (per TRaSH Guides)

Some services are scored higher due to superior bitrate or source material:

| Tag   | Service           | Score | Reason |
|-------|-------------------|-------|--------|
| BCORE | Bravia Core       | 15    | Very high bitrate streams |
| CRiT  | Criterion Channel | 20    | High-quality masters |
| MA    | Movies Anywhere   | 10    | Good source material |

Most other service tags score 0 -- they exist for naming/identification only,
not quality preference.
