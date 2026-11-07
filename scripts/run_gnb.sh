#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: run_gnb.sh

Run the E2-enabled OAI gNB in the foreground on the POWDER Linux node.
Start the core and nearRT-RIC first. Uses RFsim, band 78, 106 PRBs,
numerology 1, one TX/RX chain, and PLMN 001/01.

Environment overrides:
  GNB_IP          Host's core-bridge address (default: 192.168.70.129)
  AMF_IP          AMF address (default: 192.168.70.132)
  RIC_IP          nearRT-RIC address (default: 127.0.0.1)
  FLEXRIC_SM_DIR  Service-model directory (default: /usr/local/lib/flexric/)
  MAC_LOG_LEVEL   MAC logging level (default: warning)
  LOG_DIR         Log directory (default: $HOME/oai-run-logs)

Each launch writes a timestamped log. Stop with Ctrl+C after stopping the UE.
EOF
}

if [[ "${1:-}" == --help || "${1:-}" == -h ]]; then usage; exit 0; fi
if (( $# > 0 )); then usage >&2; exit 2; fi
if [[ "$(uname -s)" != Linux ]]; then
  printf '%s\n' 'Run this launcher on the POWDER Linux node.' >&2
  exit 1
fi

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
oai="$repo_root/openairinterface5g"
build="$oai/cmake_targets/ran_build/build"
conf="$oai/targets/PROJECTS/GENERIC-NR-5GC/CONF/gnb.sa.band78.fr1.106PRB.usrpb210.conf"
sm_dir="${FLEXRIC_SM_DIR:-/usr/local/lib/flexric/}"
if [[ ! -x "$build/nr-softmodem" ]]; then
  printf 'Missing executable: %s/nr-softmodem\nBuild OAI first.\n' "$build" >&2
  exit 1
fi
if [[ ! -r "$build/CMakeCache.txt" ]] ||
   ! grep -Eq '^E2_AGENT:(STRING|BOOL|UNINITIALIZED)=ON$' "$build/CMakeCache.txt"; then
  printf '%s\n' 'E2_AGENT must be ON. Reconfigure OAI with -DE2_AGENT=ON and rebuild nr-softmodem.' >&2
  exit 1
fi
if [[ ! -r "$conf" || ! -d "$sm_dir" ]]; then
  printf 'Check the gNB configuration and installed service models:\n%s\n%s\n' "$conf" "$sm_dir" >&2
  exit 1
fi
sm_dir="$(realpath -- "$sm_dir")/"
log_dir="${LOG_DIR:-$HOME/oai-run-logs}"
mkdir -p -- "$log_dir"
log_dir="$(cd -- "$log_dir" && pwd)"
log_file="$log_dir/gnb-$(date +%Y%m%d-%H%M%S)-$$.log"

printf 'gNB log: %s\n' "$log_file"
cd "$build"
sudo ./nr-softmodem \
  -O "$conf" \
  --rfsim --rfsimulator.serveraddr server \
  '--gNBs.[0].min_rxtxtime' 6 \
  '--gNBs.[0].plmn_list.[0].mcc' 001 \
  '--gNBs.[0].plmn_list.[0].mnc' 01 \
  '--gNBs.[0].plmn_list.[0].mnc_length' 2 \
  '--gNBs.[0].amf_ip_address.[0].ipv4' "${AMF_IP:-192.168.70.132}" \
  '--gNBs.[0].NETWORK_INTERFACES.GNB_IPV4_ADDRESS_FOR_NG_AMF' "${GNB_IP:-192.168.70.129}" \
  '--gNBs.[0].NETWORK_INTERFACES.GNB_IPV4_ADDRESS_FOR_NGU' "${GNB_IP:-192.168.70.129}" \
  '--RUs.[0].nb_tx' 1 '--RUs.[0].nb_rx' 1 \
  --e2_agent.near_ric_ip_addr "${RIC_IP:-127.0.0.1}" \
  --e2_agent.sm_dir "$sm_dir" \
  --log_config.global_log_level info \
  --log_config.ngap_log_level info \
  --log_config.rrc_log_level info \
  --log_config.mac_log_level "${MAC_LOG_LEVEL:-warning}" \
  2>&1 | tee "$log_file"
