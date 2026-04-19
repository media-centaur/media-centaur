#!/bin/sh
# Media Centarr — bootstrap installer.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/media-centarr/media-centarr/main/installer/install.sh | sh
#
# Resolves the latest GitHub Release, downloads the Linux x86_64 tarball,
# verifies it, and hands off to the bundled `bin/media-centarr-install`
# inside the extracted tree.
#
# Optional flags:
#   --version <vX.Y.Z>   Install a specific release tag instead of latest.
#
# Optional env:
#   MEDIA_CENTARR_INSTALL_ROOT  override install root (default ~/.local/lib/media-centarr)
#   MEDIA_CENTARR_CONFIG_DIR    override config dir   (default ~/.config/media-centarr)

set -eu

GITHUB_REPO="media-centarr/media-centarr"

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

case "$(uname -s)" in
    Linux) ;;
    *) die "Only Linux is supported (saw $(uname -s)). See docs/installation.md for source builds." ;;
esac

case "$(uname -m)" in
    x86_64|amd64) ;;
    *) die "Only x86_64 is supported (saw $(uname -m))." ;;
esac

if [ -f /etc/os-release ] && grep -qi 'alpine\|musl' /etc/os-release; then
    die "musl libc is not supported. Releases are built against glibc."
fi

need curl
need tar
need sha256sum
need systemctl
need awk

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
tarball="media-centarr-${version}-linux-x86_64.tar.gz"
base_url="https://github.com/$GITHUB_REPO/releases/download/$tag"

# ---- download + verify ----------------------------------------------------

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

banner "Downloading $tarball"
curl -fsSL --progress-bar -o "$tmpdir/$tarball"   "$base_url/$tarball"
curl -fsSL                -o "$tmpdir/SHA256SUMS" "$base_url/SHA256SUMS"

banner "Verifying checksum"
(cd "$tmpdir" && grep " $tarball\$" SHA256SUMS | sha256sum -c -) \
    || die "Checksum verification failed"

# ---- extract + hand off ---------------------------------------------------

banner "Extracting"
mkdir -p "$tmpdir/extract"
tar -xzf "$tmpdir/$tarball" -C "$tmpdir/extract"

bundled_installer="$tmpdir/extract/bin/media-centarr-install"
[ -x "$bundled_installer" ] || die "Tarball missing bin/media-centarr-install — was this built before the install flow shipped?"

banner "Handing off to bundled installer"
# shellcheck disable=SC2086 # intentional word-split of forward_args
exec "$bundled_installer" $forward_args
