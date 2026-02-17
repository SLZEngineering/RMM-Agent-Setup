#!/usr/bin/env bash
# ============================================================
# Solutionz INC RMM Agent Setup (Linux) - Domotz Collector Install
# System Admin: Seneathia Williams
# Last Updated: 2026-02-17
# Description: Performs Ubuntu update and installs Domotz Pro Agent (Snap),
#              connects required interfaces, enables TUN for VPN-on-Demand,
#              and restarts the Domotz agent package.
#
# Notes:
# - This script intentionally does NOT open the Domotz web UI or perform portal pairing.
# - This script is idempotent: safe to re-run; it will skip completed items.
#
# Logs:
# - Writes to: <home>/rmm_logs/setup_<timestamp>.log
# ============================================================

set -euo pipefail

RUN_USER="${SUDO_USER:-${USER}}"
RUN_HOME="$(eval echo "~${RUN_USER}")"
LOG_DIR="${RUN_HOME}/rmm_logs"
TS="$(date +%Y%m%d_%H%M%S)"
LOG_FILE="${LOG_DIR}/setup_${TS}.log"

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

  # Determine if plug exists and is connected
  if snap connections domotzpro-agent-publicstore 2>/dev/null | awk '{print $1}' | grep -qx "${plug}"; then
    # If slot/connection is "-", it's not connected.
    if snap connections domotzpro-agent-publicstore 2>/dev/null | awk '$1=="'${plug}'" {print $2}' | grep -q "^-"; then
      say "Connecting snap interface: ${plug}"
      snap connect "domotzpro-agent-publicstore:${plug}"
    else
      say "Snap interface already connected: ${plug}"
    fi
  else
    say "WARNING: Snap plug not found on this version: ${plug} (skipping)"
  fi
}

main() {
  require_root

  say "Log file: ${LOG_FILE}"
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

  say "Step 4: Enable tun module for VPN-on-Demand"
  ensure_line_in_file "tun" "/etc/modules"
  if lsmod | awk '{print $1}' | grep -qx "tun"; then
    say "tun module already loaded"
  else
    modprobe tun || true
    if lsmod | awk '{print $1}' | grep -qx "tun"; then
      say "tun module loaded successfully"
    else
      say "WARNING: tun module did not load (check kernel/module support)"
    fi
  fi

  say "Step 5: Restart Domotz agent snap"
  snap restart domotzpro-agent-publicstore || true

  say "Setup complete."
  say "Logs saved: ${LOG_FILE}"
}

main "$@"
