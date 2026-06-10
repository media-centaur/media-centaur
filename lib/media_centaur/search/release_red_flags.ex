defmodule MediaCentaur.Search.ReleaseRedFlags do
  @moduledoc """
  Conservative detector for fake-release malware bait in release
  titles — the `Sample.Movie.2026.1080p.exe` pattern: an indexer
  result whose name advertises an executable or password-protected
  archive instead of a video.

  Flagged releases are **never auto-picked** (planner options, worker
  best-match, alternatives lists all filter through here). The check
  is deliberately token-based — `exe` as a delimited token trips it,
  `Executive` does not — and the list stays short: false positives
  hide legitimate releases (campaign risk #3's twin), so only
  unambiguous bait shapes belong here. Append-only test table per
  ADR-027.

  Pure module — no I/O.
  """

  # Executable / installer tokens that have no business in a video
  # release name, matched as whole delimited tokens.
  @executable_token ~r/(?:^|[\s._\-\[\(])(?:exe|scr|bat|cmd|msi|apk)(?:$|[\s._\-\]\)])/i

  # Password-protected archive bait.
  @password_bait ~r/\bpassword\b/i

  # No legitimate video release is this small — the classic bait payload
  # is a 1–5MB executable. Conservative floor: real episodes start around
  # 50MB even at SD; 25MB keeps a wide margin against false positives.
  @min_plausible_video_bytes 25 * 1024 * 1024

  @spec suspicious?(String.t()) :: boolean()
  def suspicious?(title) when is_binary(title) do
    Regex.match?(@executable_token, title) or Regex.match?(@password_bait, title)
  end

  @doc """
  Full-result check: the title patterns plus a size floor — a release
  claiming video content at under #{div(@min_plausible_video_bytes, 1024 * 1024)}MB
  is bait regardless of what it's named. Unknown size falls back to the
  title check alone.
  """
  @spec suspicious?(String.t(), integer() | nil) :: boolean()
  def suspicious?(title, nil), do: suspicious?(title)

  def suspicious?(title, size_bytes) when is_integer(size_bytes) do
    suspicious?(title) or size_bytes < @min_plausible_video_bytes
  end
end
