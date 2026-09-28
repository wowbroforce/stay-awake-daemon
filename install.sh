#!/usr/bin/env bash
# One-line installer for stay-awake-daemon.
#
#   curl -fsSL https://raw.githubusercontent.com/wowbroforce/stay-awake-daemon/main/install.sh | bash
#
# Downloads a release tarball from GitHub Releases, installs the binary to
# ~/.local/bin and the systemd user unit to ~/.config/systemd/user/, and
# seeds a config file if one doesn't already exist. Does NOT enable/start
# the service or touch `loginctl` linger, see the printed next steps.
#
# Usage: install.sh [version]
#   version   A release tag (e.g. v0.1.0-alpha). Defaults to the latest
#             release. Can also be set via $STAY_AWAKE_VERSION.

set -euo pipefail

REPO="wowbroforce/stay-awake-daemon"
VERSION="${1:-${STAY_AWAKE_VERSION:-}}"
BIN_NAME="StayAwakeDaemon"
INSTALL_NAME="stay-awake-daemon"
BIN_DIR="${HOME}/.local/bin"
SYSTEMD_USER_DIR="${HOME}/.config/systemd/user"
CONFIG_DIR="${XDG_CONFIG_HOME:-${HOME}/.config}/stay-awake-daemon"

log() { printf '==> %s\n' "$1"; }
die() { printf 'error: %s\n' "$1" >&2; exit 1; }

command -v curl >/dev/null 2>&1 || die "curl is required"
command -v tar >/dev/null 2>&1 || die "tar is required"

if [ -z "$VERSION" ]; then
  log "Looking up latest release..."
  VERSION="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
    | grep -m1 '"tag_name"' | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/')"
  [ -n "$VERSION" ] || die "could not determine latest release tag"
fi

ASSET="stay-awake-daemon-${VERSION}-linux-x86_64.tar.gz"
URL="https://github.com/${REPO}/releases/download/${VERSION}/${ASSET}"
CHECKSUM_URL="${URL}.sha256"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

log "Downloading ${ASSET} (${VERSION})..."
curl -fsSL "$URL" -o "${WORK_DIR}/${ASSET}" \
  || die "failed to download ${URL} (does this release/asset exist?)"

if curl -fsSL "$CHECKSUM_URL" -o "${WORK_DIR}/${ASSET}.sha256" 2>/dev/null; then
  log "Verifying checksum..."
  (cd "$WORK_DIR" && sha256sum -c "${ASSET}.sha256") \
    || die "checksum verification failed"
else
  log "No checksum file found for this release, skipping verification."
fi

log "Extracting..."
tar -xzf "${WORK_DIR}/${ASSET}" -C "$WORK_DIR"
[ -f "${WORK_DIR}/${BIN_NAME}" ] || die "binary ${BIN_NAME} not found in archive"

mkdir -p "$BIN_DIR" "$SYSTEMD_USER_DIR" "$CONFIG_DIR"

install -m 755 "${WORK_DIR}/${BIN_NAME}" "${BIN_DIR}/${INSTALL_NAME}"
log "Installed binary to ${BIN_DIR}/${INSTALL_NAME}"

if [ -f "${WORK_DIR}/stay-awake-daemon.service" ]; then
  install -m 644 "${WORK_DIR}/stay-awake-daemon.service" "${SYSTEMD_USER_DIR}/stay-awake-daemon.service"
  log "Installed systemd user unit to ${SYSTEMD_USER_DIR}/stay-awake-daemon.service"
fi

if [ -f "${CONFIG_DIR}/config.json" ]; then
  log "Existing config found at ${CONFIG_DIR}/config.json, leaving it untouched."
elif [ -f "${WORK_DIR}/config.example.json" ]; then
  install -m 600 "${WORK_DIR}/config.example.json" "${CONFIG_DIR}/config.json"
  log "Seeded ${CONFIG_DIR}/config.json from the example (edit it before starting the service)."
fi

if command -v systemctl >/dev/null 2>&1; then
  systemctl --user daemon-reload || true
fi

cat <<EOF

Install complete.

Next steps:
  1. Edit your config:        \$EDITOR ${CONFIG_DIR}/config.json
  2. Enable and start it:     systemctl --user enable --now stay-awake-daemon.service
  3. (HTPC/headless use) keep it running with no one logged in:
                               loginctl enable-linger "\$USER"
  4. Check it's running:      systemctl --user status stay-awake-daemon.service
                               journalctl --user -u stay-awake-daemon.service -f

EOF
