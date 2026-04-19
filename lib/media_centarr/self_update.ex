defmodule MediaCentarr.SelfUpdate do
  use Boundary,
    deps: [MediaCentarr.Settings],
    exports: [UpdateChecker]

  @moduledoc """
  In-app release check + self-update for Media Centarr.

  Owns the relationship between the running release and the
  `media-centarr/media-centarr` GitHub repository: polls the GitHub
  Releases API for the latest tag, caches the result, and drives the
  download → verify → stage → hand-off pipeline that applies an update.

  The context is deliberately small and boundary-visible so the web
  layer can wire the Settings > Overview card, a scheduled Oban
  worker can keep state fresh, and nothing else reaches into the
  update internals directly.

  ## Trust model

  Trust is anchored to GitHub's account and release process for
  `media-centarr/media-centarr`. TLS verification is always on, the
  download URL is built from a fixed template (never pulled from API
  response fields), and `tag_name` values are validated against a
  strict semver regex before being used anywhere. A compromised
  GitHub account defeats these checks — release signing is tracked
  as a follow-up.

  ## Current surface

  The initial scaffold exposes the moved `UpdateChecker` module. The
  facade functions (`subscribe/0`, `check_now/0`, `apply_pending/0`,
  `current_status/0`, `cached_release/0`) land alongside the
  `CheckerJob`, `Updater`, and related modules in follow-up slices.
  """
end
