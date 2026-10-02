#!/usr/bin/env bash
set -euo pipefail

REPO="jpguevara/omacrook-releases"
PORT=7420
PLIST_LABEL="io.github.jpguevara.omacrook"

data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
app_dir="$data_home/omacrook"
release_dir="$app_dir/release"
bin_link="$HOME/.local/bin/omacrook"
unit_dir="$config_home/systemd/user"
unit_file="$unit_dir/omacrook.service"
plist_dir="$HOME/Library/LaunchAgents"
plist_file="$plist_dir/$PLIST_LABEL.plist"
log_file="$app_dir/omacrook.log"
tmp=""
PLATFORM=""

log() { printf '==> %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

cleanup() { [ -z "$tmp" ] || rm -rf "$tmp"; }

have_systemd_user() {
  command -v systemctl >/dev/null 2>&1 && systemctl --user show-environment >/dev/null 2>&1
}

have_launchd() {
  command -v launchctl >/dev/null 2>&1
}

detect_platform() {
  case "$(uname -s)" in
    Linux) PLATFORM=linux ;;
    Darwin) PLATFORM=macos ;;
    *) die "unsupported OS $(uname -s); only Linux and macOS are supported" ;;
  esac
}

check_platform() {
  detect_platform
  case "$PLATFORM" in
    linux)
      case "$(uname -m)" in
        x86_64) ;;
        *) die "unsupported architecture $(uname -m); Linux releases are built for x86_64 only" ;;
      esac
      command -v sha256sum >/dev/null 2>&1 || die "missing required tool: sha256sum"
      ;;
    macos)
      case "$(uname -m)" in
        arm64) ;;
        *) die "unsupported architecture $(uname -m); macOS releases are built for Apple Silicon (arm64) only" ;;
      esac
      command -v shasum >/dev/null 2>&1 || die "missing required tool: shasum"
      ;;
  esac
  for tool in curl tar; do
    command -v "$tool" >/dev/null 2>&1 || die "missing required tool: $tool"
  done
}

verify_checksum() {
  if [ "$PLATFORM" = "linux" ]; then
    sha256sum -c -
  else
    shasum -a 256 -c -
  fi
}

release_base() {
  local version="${OMACROOK_VERSION:-latest}"
  if [ "$version" = "latest" ]; then
    printf 'https://github.com/%s/releases/latest/download' "$REPO"
  else
    printf 'https://github.com/%s/releases/download/%s' "$REPO" "$version"
  fi
}

download_and_verify() {
  local base tarball pattern
  base="$(release_base)"
  log "Downloading ${OMACROOK_VERSION:-latest} release"
  curl -fsSL "$base/SHA256SUMS" -o "$tmp/SHA256SUMS" || die "could not download SHA256SUMS from $base"
  if [ "$PLATFORM" = "linux" ]; then
    pattern='^\*?omacrook-.*-linux-x86_64\.tar\.gz$'
  else
    pattern='^\*?omacrook-.*-macos-arm64\.tar\.gz$'
  fi
  tarball="$(awk -v pat="$pattern" '$2 ~ pat { sub(/^\*/, "", $2); print $2; exit }' "$tmp/SHA256SUMS")"
  [ -n "$tarball" ] || die "SHA256SUMS lists no tarball for this platform"
  curl -fsSL "$base/$tarball" -o "$tmp/$tarball" || die "could not download $tarball"
  log "Verifying checksum"
  (cd "$tmp" && grep -F -- "$tarball" SHA256SUMS | verify_checksum) || die "checksum verification failed"
  printf '%s' "$tarball" > "$tmp/tarball-name"
}

install_files() {
  local tarball staged
  tarball="$(cat "$tmp/tarball-name")"
  staged="$tmp/extract"
  mkdir -p "$staged" "$app_dir" "$HOME/.local/bin"
  tar -xzf "$tmp/$tarball" -C "$staged" --strip-components=1
  [ -x "$staged/omacrook" ] || die "tarball does not contain the omacrook binary"
  rm -rf "$release_dir.old"
  [ ! -d "$release_dir" ] || mv "$release_dir" "$release_dir.old"
  mv "$staged" "$release_dir"
  rm -rf "$release_dir.old"
  ln -sfn "$release_dir/omacrook" "$bin_link"
  if [ -f "$release_dir/config.example.toml" ] && [ ! -e "$config_home/omacrook/config.toml" ]; then
    mkdir -p "$config_home/omacrook"
    cp "$release_dir/config.example.toml" "$config_home/omacrook/config.toml"
  fi
  log "Installed $("$bin_link" --version 2>/dev/null || echo omacrook) to $release_dir"
}

write_unit() {
  mkdir -p "$unit_dir"
  cat > "$unit_file" <<UNIT
[Unit]
Description=omacrook web frontend for herdr
After=network.target

[Service]
ExecStart=%h/.local/bin/omacrook
Environment=OMACROOK_PORT=$PORT
Restart=on-failure
RestartSec=3

[Install]
WantedBy=default.target
UNIT
}

write_launchd_plist() {
  mkdir -p "$plist_dir" "$app_dir"
  cat > "$plist_file" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$PLIST_LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$bin_link</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>OMACROOK_PORT</key>
    <string>$PORT</string>
  </dict>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <dict>
    <key>SuccessfulExit</key>
    <false/>
  </dict>
  <key>StandardOutPath</key>
  <string>$log_file</string>
  <key>StandardErrorPath</key>
  <string>$log_file</string>
</dict>
</plist>
PLIST
}

start_service() {
  if [ "$PLATFORM" = "linux" ]; then
    if ! have_systemd_user; then
      warn "systemctl --user is not available; the service was not started"
      warn "run it manually with: OMACROOK_PORT=$PORT $bin_link"
      return 0
    fi
    systemctl --user daemon-reload
    systemctl --user enable omacrook
    systemctl --user restart omacrook
    if [ "${OMACROOK_LINGER:-0}" = "1" ]; then
      loginctl enable-linger "$USER" || warn "could not enable linger"
    fi
  else
    if ! have_launchd; then
      warn "launchctl is not available; the service was not started"
      warn "run it manually with: OMACROOK_PORT=$PORT $bin_link"
      return 0
    fi
    if [ "${OMACROOK_LINGER:-0}" = "1" ]; then
      warn "OMACROOK_LINGER has no effect on macOS; launch agents already start at login"
    fi
    launchctl bootout "gui/$(id -u)" "$plist_file" >/dev/null 2>&1 || true
    launchctl bootstrap "gui/$(id -u)" "$plist_file"
    launchctl enable "gui/$(id -u)/$PLIST_LABEL"
    launchctl kickstart -k "gui/$(id -u)/$PLIST_LABEL"
  fi
}

check_path() {
  case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) warn "$HOME/.local/bin is not in PATH" ;;
  esac
}

install() {
  check_platform
  tmp="$(mktemp -d)"
  trap cleanup EXIT
  download_and_verify
  install_files
  if [ "$PLATFORM" = "linux" ]; then
    write_unit
  else
    write_launchd_plist
  fi
  start_service
  check_path
  log "omacrook is running at http://127.0.0.1:$PORT"
  log "Next step: run  omacrook setup  to open it from your phone"
}

uninstall() {
  detect_platform
  if [ "$PLATFORM" = "linux" ]; then
    if have_systemd_user; then
      systemctl --user disable --now omacrook 2>/dev/null || true
    fi
    rm -f "$unit_file" "$bin_link"
    rm -rf "$release_dir"
    if have_systemd_user; then
      systemctl --user daemon-reload || true
    fi
  else
    if have_launchd; then
      launchctl bootout "gui/$(id -u)" "$plist_file" >/dev/null 2>&1 || true
    fi
    rm -f "$plist_file" "$bin_link"
    rm -rf "$release_dir"
  fi
  log "Removed omacrook (config in $config_home/omacrook and models in $app_dir/models were left in place)"
}

main() {
  case "${1:-}" in
    "") install ;;
    --uninstall) uninstall ;;
    *) die "unknown argument: $1 (only --uninstall is supported)" ;;
  esac
}

main "$@"
