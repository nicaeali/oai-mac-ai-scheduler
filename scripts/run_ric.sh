#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: run_ric.sh

Run the bundled nearRT-RIC in the foreground on the POWDER Linux node.
Requires a completed FlexRIC build and installed service models.

Environment overrides:
  RIC_IP          RIC listening address (default: 127.0.0.1)
  FLEXRIC_CONF    Configuration file (default: /usr/local/etc/flexric/flexric.conf)
  FLEXRIC_SM_DIR  Service-model directory (default: /usr/local/lib/flexric/)
  LOG_DIR         Log directory (default: $HOME/oai-run-logs)

Each launch writes a timestamped log. Stop with Ctrl+C after stopping the gNB.
EOF
}

if [[ "${1:-}" == --help || "${1:-}" == -h ]]; then usage; exit 0; fi
if (( $# > 0 )); then usage >&2; exit 2; fi
if [[ "$(uname -s)" != Linux ]]; then
  printf '%s\n' 'Run this launcher on the POWDER Linux node.' >&2
  exit 1
fi

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
flexric="$repo_root/openairinterface5g/openair2/E2AP/flexric"
binary="$flexric/build/examples/ric/nearRT-RIC"
conf="${FLEXRIC_CONF:-/usr/local/etc/flexric/flexric.conf}"
sm_dir="${FLEXRIC_SM_DIR:-/usr/local/lib/flexric/}"
if [[ ! -x "$binary" ]]; then
  printf 'Missing executable: %s\nBuild FlexRIC first.\n' "$binary" >&2
  exit 1
fi
if [[ ! -r "$conf" || ! -d "$sm_dir" ]]; then
  printf 'Check the installed FlexRIC configuration and service models:\n%s\n%s\n' "$conf" "$sm_dir" >&2
  exit 1
fi
conf="$(realpath -- "$conf")"
sm_dir="$(realpath -- "$sm_dir")/"
log_dir="${LOG_DIR:-$HOME/oai-run-logs}"
mkdir -p -- "$log_dir"
log_dir="$(cd -- "$log_dir" && pwd)"
log_file="$log_dir/ric-$(date +%Y%m%d-%H%M%S)-$$.log"

printf 'RIC log: %s\n' "$log_file"
cd "$flexric/build"
"$binary" -c "$conf" -p "$sm_dir" -a "${RIC_IP:-127.0.0.1}" \
  2>&1 | tee "$log_file"
