# Acquisition

End-user acquisition documentation has moved to the wiki:

- **[Prowlarr Integration](https://github.com/media-centaur/media-centaur/wiki/Prowlarr-Integration)** — what acquisition provides, how to install and configure Prowlarr, how to connect Media Centaur.
- **[Download Clients](https://github.com/media-centaur/media-centaur/wiki/Download-Clients)** — per-client configuration, which clients have driver support for the in-app queue view.
- **[Release Tracking](https://github.com/media-centaur/media-centaur/wiki/Release-Tracking)** — automated grabs for upcoming titles.

**Contributors:** the download-client architecture (two protocol slots, prowlarr-stack bootstrap contract) and the full add-a-client checklist are in [`docs/download-clients.md`](../download-clients.md); the `@behaviour` contract lives in the `@moduledoc`s under `lib/media_centaur/downloads/download_client/`.
