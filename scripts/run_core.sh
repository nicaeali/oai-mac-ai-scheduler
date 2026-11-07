#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: run_core.sh [start|stop|status|logs [SERVICE...]]

Manage the bundled OAI 5G core on the POWDER Linux node.
  start   Start MySQL/NRF, wait for readiness, then start the data services.
          Existing local images are reused; missing images are pulled by Compose.
  stop    Stop the containers while retaining their database storage.
  status  Show all containers in this Compose project.
  logs    Show the last 100 log lines, optionally for selected services.

Requires Docker Engine, Compose v2, and sudo access. The default action is start.
EOF
}

action="${1:-start}"
if (( $# > 0 )); then shift; fi
case "$action" in
  -h|--help) usage; exit 0 ;;
  start|stop|status|logs) ;;
  *) usage >&2; exit 2 ;;
esac
if [[ "$action" != logs && $# -ne 0 ]]; then
  usage >&2
  exit 2
fi
if [[ "$(uname -s)" != Linux ]]; then
  printf '%s\n' 'Run this launcher on the POWDER Linux node.' >&2
  exit 1
fi

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
compose_file="$repo_root/openairinterface5g/doc/tutorial_resources/oai-cn5g/docker-compose.yaml"
if [[ ! -r "$compose_file" ]]; then
  printf 'Missing core configuration: %s\n' "$compose_file" >&2
  exit 1
fi
if ! command -v docker >/dev/null 2>&1; then
  printf '%s\n' 'Install Docker Engine and Compose v2 first; see docs/POWDER_RFSIM.md.' >&2
  exit 1
fi

compose=(sudo docker compose -f "$compose_file")
services=(mysql oai-nrf oai-udr oai-udm oai-ausf oai-amf oai-smf oai-upf oai-ext-dn)
case "$action" in
  start)
    "${compose[@]}" config --quiet
    sudo modprobe sctp
    "${compose[@]}" up -d --wait --wait-timeout 180 mysql oai-nrf
    "${compose[@]}" up -d --wait --wait-timeout 240 "${services[@]}"
    "${compose[@]}" ps -a
    ;;
  stop) exec "${compose[@]}" stop -t 30 ;;
  status) exec "${compose[@]}" ps -a ;;
  logs) exec "${compose[@]}" logs --tail=100 "$@" ;;
esac
