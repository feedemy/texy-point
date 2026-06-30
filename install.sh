#!/usr/bin/env bash
#
# TexyPoint — one-line installer (Linux: x86_64 + ARM/aarch64 Pi 5 / Pi Zero 2W)
#
#   curl -fsSL https://raw.githubusercontent.com/feedemy/texy-point/main/install.sh | bash
#
# Variant selection (camera/ANPR, or on-board NFC+QR reader):
#   curl -fsSL .../install.sh | bash -s -- --variant camera
#   curl -fsSL .../install.sh | bash -s -- --variant internal-reader
#
# This installer is served over HTTPS (raw.githubusercontent) — that is the trust
# root. It downloads the latest release, VERIFIES its signature (p256) against the
# EMBEDDED public key, and installs it.
#
set -euo pipefail

REPO="feedemy/texy-point"
VARIANT="default"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --variant) VARIANT="${2:?missing value for --variant}"; shift 2 ;;
        -h|--help) sed -n '2,/^$/{ s/^# \{0,1\}//; p }' "$0"; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 1 ;;
    esac
done

# ── Trust root: prod release public key (SPKI PEM) ────────────────────────────
# Used only to VERIFY signatures — it cannot PRODUCE them (private key is offline).
# Since this script is HTTPS-served, the trust root lives here; the downloaded
# package's signature is checked against it (a compromised distribution channel
# still cannot forge a valid package).
PROD_PUBKEY_PEM='-----BEGIN PUBLIC KEY-----
MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEY61dkq1+/awxVJhauo6doSg1+xr4
1lj/rbw5If5YLFJwXg4M+U6iFqtfYUasgDqiTJ2zwOk/4SjGJPs+QMuaNQ==
-----END PUBLIC KEY-----'

info() { echo ":: $*"; }
die()  { echo "ERROR: $*" >&2; exit 1; }

for tool in curl tar openssl; do
    command -v "$tool" >/dev/null 2>&1 || die "$tool is required (not installed)"
done

# ── Privilege check (up front, before downloading) ────────────────────────────
# Installing registers a system service (systemd) and writes to system paths, so
# the install step needs root. The bootstrap itself downloads/verifies as the
# current user; the bundled installer then elevates via sudo. Check now so we
# give clear guidance BEFORE doing any work, not midway through.
if [[ "$(id -u)" -ne 0 ]]; then
    if command -v sudo >/dev/null 2>&1; then
        info "note: installation needs root — you will be prompted for your sudo password"
        info "      (for a non-interactive install run: curl -fsSL <url> | sudo bash)"
    else
        die "installation requires root, and 'sudo' is not available — run this as root"
    fi
fi

# ── Platform → target triple ──────────────────────────────────────────────────
os="$(uname -s)"; arch="$(uname -m)"
case "$os" in
    Linux)
        case "$arch" in
            x86_64|amd64)  target="x86_64-unknown-linux-gnu" ;;
            aarch64|arm64) target="aarch64-unknown-linux-gnu" ;;
            *) die "unsupported architecture: $arch (x86_64 / aarch64 supported)" ;;
        esac ;;
    Darwin) die "macOS is not a production target — use Linux or Windows" ;;
    *) die "unsupported operating system: $os" ;;
esac

# Pi Zero (gpio) cannot take the camera variant — use internal-reader or default.
suffix=""
[[ "$VARIANT" != "default" ]] && suffix="-${VARIANT}"

# ── Resolve latest release + download ─────────────────────────────────────────
info "querying latest release ($REPO)..."
tag="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
       | grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"[^"]+"' | head -1 \
       | sed -E 's/.*"([^"]+)"$/\1/')"
[[ -n "$tag" ]] || die "no latest release found — none may be published yet"

asset="texpass-ap-${tag}-${target}${suffix}.tar.gz"
url="https://github.com/${REPO}/releases/download/${tag}/${asset}"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
info "downloading: ${asset}  (${tag})"
curl -fsSL "$url" -o "$tmp/$asset" \
    || die "download failed: $url  (does variant '$VARIANT' exist in this release?)"
tar -xzf "$tmp/$asset" -C "$tmp"

dir="$tmp/texpass-ap-${tag}-${target}${suffix}"
[[ -d "$dir" ]] || dir="$(find "$tmp" -maxdepth 1 -type d -name 'texpass-ap-*' | head -1)"
[[ -d "$dir" && -f "$dir/SHA256SUMS" && -f "$dir/SHA256SUMS.sig" ]] \
    || die "package contents incomplete (missing SHA256SUMS / .sig) — corrupt or unsigned release"

# ── Verify signature (embedded trust root) ────────────────────────────────────
info "verifying signature (p256, embedded public key)..."
printf '%s\n' "$PROD_PUBKEY_PEM" > "$tmp/trust.pem"
openssl dgst -sha256 -verify "$tmp/trust.pem" \
    -signature "$dir/SHA256SUMS.sig" "$dir/SHA256SUMS" >/dev/null 2>&1 \
    || die "SIGNATURE VERIFICATION FAILED — package is not trusted (tampered/forged), aborting"
info "signature verified ✓"

# ── Install (delegate to bundled installer: checksum + slot + service) ────────
info "installing (may require administrator/sudo)..."
chmod +x "$dir/install.sh"
"$dir/install.sh"

echo ""
info "Installation complete. Open a new terminal → 'texpass-ap --help'"
