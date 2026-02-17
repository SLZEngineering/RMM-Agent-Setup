#!/usr/bin/env bash
# ============================================================
# Solutionz INC RMM Agent Setup (Linux) - Domotz Collector Install
# System Admin: Seneathia Williams
# Last Updated: 2026-02-17
# Description: Performs Ubuntu update and installs Domotz Pro Agent (Snap),
#              connects required interfaces, enables TUN for VPN-on-Demand,
#              and restarts the Domotz agent package.
#
# SAFETY / LOOP PREVENTION:
# - Creates a completion marker at /var/lib/solutionz_rmm/setup.done
# - If marker exists, script exits cleanly (use --force to rerun)
#
# Logs:
# - Writes to: <home>/rmm_logs/setup_<timestamp>.log
# ============================================================

set -euo pipefail

FORCE="false"
if [[ "${1:-}" == "--force" ]]; then
  FORCE="true"
  shift || true
fi

RUN_USER="${SUDO_USER:-${USER}}"
RUN_HOME="$(eval echo "~${RUN_USER}")"
LOG_DIR="${RUN_HOME}/rmm_logs"
TS="$(date +%Y%m%d_%H%M%S)"
LOG_FILE="${LOG_DIR}/setup_${TS}.log"

STATE_DIR="/var/lib/solutionz_rmm"
DONE_MARK="${STATE_DIR}/setup.done"

mkdir -p "${LOG_DIR}"
exec > >(tee -a "${LOG_FILE}") 2>&1

say() { echo -e "\n[$(date +'%F %T')] $*"; }

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "ERROR: Please run with sudo (root required)." >&2
    exit 1
  fi
}

snap_is_installed() {
  snap list 2>/dev/null | awk 'NR>1{print $1}' | grep -qx "domotzpro-agent-publicstore"
}

ensure_line_in_file() {
  local line="$1" file="$2"
  touch "$file"
  if ! grep -qxF "$line" "$file" 2>/dev/null; then
    echo "$line" >> "$file"
  fi
}

snap_connect_if_needed() {
  local plug="$1"
  if ! snap_is_installed; then return 0; fi

  if snap connections domotzpro-agent-publicstore 2>/dev/null | awk '{print $1}' | grep -qx "${plug}"; then
    if snap connections domotzpro-agent-publicstore 2>/dev/null | awk '$1=="'${plug}'" {print $2}' | grep -q "^-"; then
      say "Connecting snap interface: ${plug}"
      snap connect "domotzpro-agent-publicstore:${plug}" || true
    else
      say "Snap interface already connected: ${plug}"
    fi
  else
    say "WARNING: Snap plug not found on this version: ${plug} (skipping)"
  fi
}

tun_ready() {
  [[ -c /dev/net/tun ]]
}

ensure_tun() {
  say "Step 4: Enable tun for VPN-on-Demand"
  ensure_line_in_file "tun" "/etc/modules"
  modprobe tun >/dev/null 2>&1 || true

  if tun_ready; then
    say "tun is available: /dev/net/tun present"
    return 0
  fi

  local kver
  kver="$(uname -r)"
  say "tun device missing. Attempting to install linux-modules-extra for kernel: $kver"
  apt-get update -y || true
  apt-get install -y "linux-modules-extra-${kver}" || true

  modprobe tun >/dev/null 2>&1 || true

  if tun_ready; then
    say "tun is available after installing linux-modules-extra: /dev/net/tun present"
    return 0
  fi

  say "WARNING: tun is still not available (/dev/net/tun missing)."
  say "This can happen in some minimal kernels or containerized environments."
  return 1
}

main() {
  require_root

  say "Log file: ${LOG_FILE}"
  mkdir -p "${STATE_DIR}"

  if [[ -f "${DONE_MARK}" && "${FORCE}" != "true" ]]; then
    say "Setup already completed (marker exists): $DONE_MARK"
    say "If you need to re-run anyway, use: sudo bash <script> --force"
    exit 0
  fi

  say "Step 1: Update package index"
  apt-get update -y

  say "Step 2: Install Domotz Pro Agent (snap) if missing"
  if snap_is_installed; then
    say "Domotz snap already installed: domotzpro-agent-publicstore"
  else
    snap install domotzpro-agent-publicstore
  fi

  say "Step 3: Connect required snap interfaces"
  snap_connect_if_needed "firewall-control"
  snap_connect_if_needed "network-observe"
  snap_connect_if_needed "raw-usb"
  snap_connect_if_needed "shutdown"
  snap_connect_if_needed "system-observe"

  ensure_tun || true

  say "Step 5: Restart Domotz agent snap"
  snap restart domotzpro-agent-publicstore || true

  echo "completed=$(date -Is)" > "${DONE_MARK}"

  say "Setup complete."
  say "Logs saved: ${LOG_FILE}"
  say "Completion marker: ${DONE_MARK}"
}

main "$@"
