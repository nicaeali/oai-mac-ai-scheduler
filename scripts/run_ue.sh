#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: run_ue.sh

Run one OAI nrUE in the foreground on the POWDER Linux node.
Start the core and gNB first. Uses RFsim, band 78, 106 PRBs,
numerology 1, and center frequency 3619200000 Hz.

Environment overrides:
  RF_SIM_SERVER   RFsim gNB address (default: 127.0.0.1)
  UE_IMSI         Subscriber IMSI (default: 001010000000001)
  UE_KEY          Authentication key (default: bundled core test key)
  UE_OPC          Operator key (default: bundled core test OPc)
  UE_DNN          Data network name (default: oai)
  UE_SST          Slice service type (default: 1)
  LOG_DIR         Log directory (default: $HOME/oai-run-logs)

Each launch writes a timestamped log. Stop with Ctrl+C after stopping traffic.
EOF
}

if [[ "${1:-}" == --help || "${1:-}" == -h ]]; then usage; exit 0; fi
if (( $# > 0 )); then usage >&2; exit 2; fi
if [[ "$(uname -s)" != Linux ]]; then
  printf '%s\n' 'Run this launcher on the POWDER Linux node.' >&2
  exit 1
fi

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
build="$repo_root/openairinterface5g/cmake_targets/ran_build/build"
if [[ ! -x "$build/nr-uesoftmodem" ]]; then
  printf 'Missing executable: %s/nr-uesoftmodem\nBuild OAI first.\n' "$build" >&2
  exit 1
fi
log_dir="${LOG_DIR:-$HOME/oai-run-logs}"
mkdir -p -- "$log_dir"
log_dir="$(cd -- "$log_dir" && pwd)"
log_file="$log_dir/ue-$(date +%Y%m%d-%H%M%S)-$$.log"

printf 'nrUE log: %s\n' "$log_file"
cd "$build"
sudo ./nr-uesoftmodem \
  -r 106 --numerology 1 --band 78 -C 3619200000 \
  --rfsim --rfsimulator.serveraddr "${RF_SIM_SERVER:-127.0.0.1}" \
  --uicc0.imsi "${UE_IMSI:-001010000000001}" \
  --uicc0.key "${UE_KEY:-fec86ba6eb707ed08905757b1bb44b8f}" \
  --uicc0.opc "${UE_OPC:-C42449363BBAD02B66D16BC975D77CC1}" \
  --uicc0.dnn "${UE_DNN:-oai}" \
  --uicc0.nssai_sst "${UE_SST:-1}" \
  2>&1 | tee "$log_file"
