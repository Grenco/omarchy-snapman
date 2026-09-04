#!/usr/bin/env bash
set -euo pipefail

PLUGIN_DIR="${SNAPMAN_PLUGIN_DIR:-$HOME/.config/omarchy/plugins/grenco.snapman}"

mkdir -p "$HOME/.local/bin"
install -m 0755 "$PLUGIN_DIR/scripts/omarchy-snapman-tui" "$HOME/.local/bin/omarchy-snapman-tui"

mkdir -p "$HOME/.config/systemd/user"
install -m 0644 "$PLUGIN_DIR/scripts/snapman-retention.service" "$HOME/.config/systemd/user/snapman-retention.service"
install -m 0644 "$PLUGIN_DIR/scripts/snapman-retention.timer" "$HOME/.config/systemd/user/snapman-retention.timer"

systemctl --user daemon-reload >/dev/null 2>&1 || true

if [[ -f /etc/snapper/configs/root ]] && ! grep -q '^ALLOW_USERS=' /etc/snapper/configs/root; then
  echo "Snapman hint: your user may need ALLOW_USERS access for passwordless snapshot actions." >&2
  echo "  Grant your user passwordless snapshot access once with:" >&2
  echo "    sudo snapper -c root set-config ALLOW_USERS=\"$USER\"" >&2
fi
