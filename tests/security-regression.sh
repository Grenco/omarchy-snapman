#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

plugin_dir="$tmpdir/plugin"
bin_dir="$tmpdir/bin"
marker="$tmpdir/omarchy-called"
mkdir -p "$plugin_dir/scripts" "$bin_dir" "$tmpdir/.config/omarchy"
install -m 0755 "$repo_dir/scripts/snapman-apply-update" "$plugin_dir/scripts/snapman-apply-update"

cat >"$bin_dir/omarchy" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >"$SNAPMAN_TEST_MARKER"
EOF
chmod +x "$bin_dir/omarchy"

cat >"$plugin_dir/scripts/snapman-update-status" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "${SNAPMAN_TEST_STATUS}"
EOF
chmod +x "$plugin_dir/scripts/snapman-update-status"

if SNAPMAN_PLUGIN_DIR="$plugin_dir" SNAPMAN_TEST_MARKER="$marker" SNAPMAN_TEST_STATUS='{"state":"available","verificationVerified":false}' PATH="$bin_dir:$PATH" "$plugin_dir/scripts/snapman-apply-update"; then
  printf 'unverified update unexpectedly succeeded\n' >&2
  exit 1
fi
[[ ! -e "$marker" ]]

SNAPMAN_PLUGIN_DIR="$plugin_dir" SNAPMAN_TEST_MARKER="$marker" SNAPMAN_TEST_STATUS='{"state":"available","verificationVerified":true}' PATH="$bin_dir:$PATH" "$plugin_dir/scripts/snapman-apply-update"
[[ $(<"$marker") == "plugin update grenco.snapman" ]]

if HOME="$tmpdir" "$repo_dir/scripts/snapman-write-config" count 21; then
  printf 'out-of-range count retention unexpectedly succeeded\n' >&2
  exit 1
fi

if HOME="$tmpdir" "$repo_dir/scripts/snapman-write-config" age 366; then
  printf 'out-of-range age retention unexpectedly succeeded\n' >&2
  exit 1
fi

printf 'security regression checks passed\n'
