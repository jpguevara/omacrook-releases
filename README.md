# omacrook releases

Prebuilt binaries for [omacrook](https://github.com/jpguevara/omacrook), a web client for herdr agents.

## Download

Get the tarball for your platform and `SHA256SUMS` from the [latest release](https://github.com/jpguevara/omacrook-releases/releases/latest):

| Platform | Asset |
| --- | --- |
| Linux x86_64 | `omacrook-v<version>-linux-x86_64.tar.gz` |
| macOS Apple Silicon | `omacrook-v<version>-macos-arm64.tar.gz` |

Verify before extracting, in the directory holding both files:

```sh
sha256sum -c SHA256SUMS            # Linux
shasum -a 256 -c SHA256SUMS        # macOS
```

## Install

One-line installer, no sudo. It installs the binary to `~/.local/bin`, a systemd user service (Linux) or launchd agent (macOS), and a default config:

```sh
curl -fsSL https://raw.githubusercontent.com/jpguevara/omacrook-releases/main/install.sh | bash
```

| Option | Effect |
| --- | --- |
| `OMACROOK_VERSION=<tag>` | Install a specific release instead of the latest |
| `OMACROOK_LINGER=1` | Run `loginctl enable-linger` so the service starts without a login (Linux) |
| `bash -s -- --uninstall` | Remove the service/agent, unit/plist, symlink and `~/.local/share/omacrook/release`; config and models are kept |

Re-running the installer upgrades in place.

### Manual install (Linux)

```sh
tar -xzf omacrook-v<version>-linux-x86_64.tar.gz
cd omacrook-v<version>-linux-x86_64
mkdir -p ~/.local/bin ~/.config/systemd/user ~/.config/omacrook
cp omacrook ~/.local/bin/
cp omacrook.service ~/.config/systemd/user/
cp -n config.example.toml ~/.config/omacrook/config.toml
systemctl --user daemon-reload
systemctl --user enable --now omacrook
```

### Manual install (macOS, Apple Silicon)

```sh
tar -xzf omacrook-v<version>-macos-arm64.tar.gz
cd omacrook-v<version>-macos-arm64
mkdir -p ~/.local/bin ~/Library/LaunchAgents ~/.config/omacrook
cp omacrook ~/.local/bin/
sed "s#@HOME@#$HOME#g" omacrook.plist > ~/Library/LaunchAgents/io.github.jpguevara.omacrook.plist
cp -n config.example.toml ~/.config/omacrook/config.toml
launchctl bootstrap "gui/$(id -u)" ~/Library/LaunchAgents/io.github.jpguevara.omacrook.plist
launchctl enable "gui/$(id -u)/io.github.jpguevara.omacrook"
launchctl kickstart -k "gui/$(id -u)/io.github.jpguevara.omacrook"
```

## Run

omacrook listens on `127.0.0.1:7420` and needs herdr running, with its socket at `~/.config/herdr/herdr.sock`. Open <http://localhost:7420> and sign in with a passkey.

| | Linux | macOS |
| --- | --- | --- |
| Status | `systemctl --user status omacrook` | `launchctl print gui/$(id -u)/io.github.jpguevara.omacrook` |
| Restart | `systemctl --user restart omacrook` | `launchctl kickstart -k gui/$(id -u)/io.github.jpguevara.omacrook` |
| Logs | `journalctl --user -u omacrook` | `~/.local/share/omacrook/omacrook.log` |

## Configure

Config file: `~/.config/omacrook/config.toml` (or `$XDG_CONFIG_HOME/omacrook/config.toml`, or the path in `OMACROOK_CONFIG`). Every key is optional and commented out in the shipped file. It is read once at startup: restart the service after editing.

```toml
agent_types = ["claude", "pi"]
ffmpeg = "ffmpeg"
whisper_cli = "whisper-cli"
whisper_model = "/home/you/.local/share/omacrook/models/ggml-small.bin"
upload_retention_days = 7
check_for_updates = true
```

| Key | Default | Meaning |
| --- | --- | --- |
| `agent_types` | `["claude","pi"]` | herdr agent ids that may be started, in UI order |
| `ffmpeg` | `ffmpeg` | ffmpeg binary for voice input |
| `whisper_cli` | `whisper-cli` | whisper.cpp CLI binary |
| `whisper_model` | `~/.local/share/omacrook/models/ggml-small.bin` | Whisper model file |
| `upload_retention_days` | `7` | Delete image uploads older than this many days; `0` disables cleanup |
| `public_url` | unset | Public `https://` address, written by `omacrook setup` |

Environment variables:

| Variable | Default | Effect |
| --- | --- | --- |
| `OMACROOK_PORT` | `7420` | Listen port |
| `OMACROOK_CONFIG` | unset | Full path of the config file |
| `OMACROOK_ALLOWED_HOSTS` | unset | Extra comma-separated `Host` names to accept |

The service sets `OMACROOK_PORT=7420`. On Linux override it with `systemctl --user edit omacrook`:

```ini
[Service]
Environment=OMACROOK_PORT=8080
```

On macOS edit the installed plist, then `launchctl bootout` and re-run the `bootstrap`/`enable`/`kickstart` commands.

### Voice input (optional)

Install `ffmpeg` and `whisper-cli`, and put `ggml-small.bin` in `~/.local/share/omacrook/models/`.

### Phone access over Tailscale

The server binds to localhost only. Enable MagicDNS and HTTPS certificates in the Tailscale admin console, then:

```sh
tailscale serve --bg 7420
tailscale serve status
```

Open the printed `https://<host>.<tailnet>.ts.net` URL on a phone running Tailscale with the same account. HTTPS is required for the PWA and microphone. Never use Tailscale Funnel or any public tunnel.
