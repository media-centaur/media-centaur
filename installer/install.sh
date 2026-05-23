#!/bin/sh
# Media Centaur — bootstrap installer.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/media-centaur/media-centaur/main/installer/install.sh | sh
#
# Resolves the latest GitHub Release, downloads the tarball for this
# platform (Linux x86_64, or macOS Apple Silicon — experimental), verifies
# it, and hands off to the bundled `bin/media-centaur-install` in the tree.
#
# Optional flags:
#   --version <vX.Y.Z>   Install a specific release tag instead of latest.
#
# Optional env:
#   MEDIA_CENTAUR_INSTALL_ROOT  override install root (default ~/.local/lib/media-centaur)
#   MEDIA_CENTAUR_CONFIG_DIR    override config dir   (default ~/.config/media-centaur)

set -eu

GITHUB_REPO="media-centaur/media-centaur"

die()    { printf 'Error: %s\n' "$1" >&2; exit 1; }
banner() { printf '==> %s\n' "$1"; }
need()   { command -v "$1" >/dev/null 2>&1 || die "$1 is required"; }

# Validate a tag string against the canonical release shape.
# Rejected strings never reach URL construction or filesystem paths.
# POSIX grep -E for a precise character class — shell `case` globs can't
# enforce digits-only, which opens injections like "v0.7.1; rm".
validate_tag() {
    printf '%s' "$1" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.]+)?$'
}

# ---- platform check -------------------------------------------------------
#
# Resolve the release artifact for this OS + arch. Linux x86_64 is the
# primary, fully-supported platform; macOS on Apple Silicon (arm64) is
# experimental — the darwin build ships and self-updates, but is
# Linux-developer-tested only. Report rough edges with a [macOS] issue.

case "$(uname -s)" in
    Linux)
        case "$(uname -m)" in
            x86_64|amd64) platform="linux-x86_64" ;;
            *) die "On Linux, only x86_64 is supported (saw $(uname -m))." ;;
        esac
        if [ -f /etc/os-release ] && grep -qi 'alpine\|musl' /etc/os-release; then
            die "musl libc is not supported. Releases are built against glibc."
        fi
        ;;
    Darwin)
        case "$(uname -m)" in
            arm64|aarch64) platform="darwin-arm64" ;;
            *) die "On macOS, only Apple Silicon (arm64) is supported (saw $(uname -m)). Intel Macs aren't built yet." ;;
        esac
        ;;
    *) die "Unsupported OS: $(uname -s). Supported: Linux (x86_64), macOS (Apple Silicon)." ;;
esac

# Portable SHA-256 verifier — macOS ships `shasum -a 256` but not
# `sha256sum`; most Linux distros are the reverse. Honor whichever exists.
sha256_check() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum -c -
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 -c -
    else
        die "Neither sha256sum nor shasum is available; cannot verify the download."
    fi
}

need curl
need tar
need awk
# Service setup (systemd on Linux, launchd on macOS) is handled by the
# bundled per-platform installer, which degrades gracefully when absent —
# so the bootstrap doesn't hard-require either init system.

# ---- arg parsing ----------------------------------------------------------

requested_tag=""
# Flags we don't recognize locally get passed through to the bundled
# installer — this keeps `curl … | sh -s -- --no-service` working without
# the bootstrap having to keep pace with every bundled-installer flag.
forward_args=""
while [ $# -gt 0 ]; do
    case "$1" in
        --version) requested_tag="$2"; shift 2 ;;
        --version=*) requested_tag="${1#--version=}"; shift ;;
        --help|-h)
            sed -n '2,/^$/p' "$0" 2>/dev/null | sed 's/^# //;s/^#$//' || true
            exit 0
            ;;
        *)
            # Preserve spacing-safe quoting for argv pass-through.
            if [ -z "$forward_args" ]; then
                forward_args="$1"
            else
                forward_args="$forward_args $1"
            fi
            shift
            ;;
    esac
done

# ---- resolve tag ----------------------------------------------------------

if [ -n "$requested_tag" ]; then
    tag="$requested_tag"
    banner "Using requested release: $tag"
else
    banner "Resolving latest release"
    api_url="https://api.github.com/repos/$GITHUB_REPO/releases/latest"
    tag=$(curl -fsSL "$api_url" | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n1)
    [ -n "$tag" ] || die "Could not resolve latest release tag from $api_url"
    banner "Latest is $tag"
fi

validate_tag "$tag" || die "Rejected malformed tag: $tag"

version=${tag#v}
tarball="media-centaur-${version}-${platform}.tar.gz"
base_url="https://github.com/$GITHUB_REPO/releases/download/$tag"

# ---- download + verify ----------------------------------------------------

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

banner "Downloading $tarball"
curl -fsSL --progress-bar -o "$tmpdir/$tarball"   "$base_url/$tarball"
curl -fsSL                -o "$tmpdir/SHA256SUMS" "$base_url/SHA256SUMS"

banner "Verifying checksum"
(cd "$tmpdir" && grep " $tarball\$" SHA256SUMS | sha256_check) \
    || die "Checksum verification failed"

# ---- extract + hand off ---------------------------------------------------

banner "Extracting"
mkdir -p "$tmpdir/extract"
tar -xzf "$tmpdir/$tarball" -C "$tmpdir/extract"

bundled_installer="$tmpdir/extract/bin/media-centaur-install"
[ -x "$bundled_installer" ] || die "Tarball missing bin/media-centaur-install — was this built before the install flow shipped?"

banner "Handing off to bundled installer"
# shellcheck disable=SC2086 # intentional word-split of forward_args
exec "$bundled_installer" $forward_args
