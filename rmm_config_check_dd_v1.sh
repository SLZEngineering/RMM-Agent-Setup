#!/usr/bin/env bash
# ============================================================
# Solutionz INC RMM Agent Config Check (Linux)
# System Admin: Seneathia Williams
# Last Updated: 2026-02-17
# Description: Validates local Domotz collector configuration and prints results
#              in a consistent format (even when non-interactive).
#
# FIX INCLUDED:
# - Always prints the expected output (no TTY dependency)
# - Generates a timestamped log file automatically
# - Quick-fix for "Permission denied": script has proper shebang + you can run with sudo bash
#
# Logs:
# - <home>/rmm_logs/rmm_config_check_<timestamp>.log
# ============================================================

set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  exec sudo bash "$0" "$@"
fi

RUN_USER="${SUDO_USER:-${USER}}"
RUN_HOME="$(eval echo "~${RUN_USER}")"
LOG_DIR="${RUN_HOME}/rmm_logs"
TS="$(date +%Y%m%d_%H%M%S)"
LOG_FILE="${LOG_DIR}/rmm_config_check_${TS}.log"

mkdir -p "${LOG_DIR}"
exec > >(tee -a "${LOG_FILE}") 2>&1

hdr() { echo -e "\n*--- $1 ---"; }

main() {
  echo "RMM Config Check"
  echo "Host: $(hostname)"
  echo "Time: $(date -Is)"
  echo "Log file: $LOG_FILE"

  hdr "OS / KERNEL"
  if [[ -r /etc/os-release ]]; then . /etc/os-release; echo "$PRETTY_NAME"; fi
  echo "Kernel: $(uname -r)"

  hdr "DOMOTZ SNAP STATUS"
  if command -v snap >/dev/null 2>&1; then
    if snap list 2>/dev/null | awk 'NR>1{print $1}' | grep -qx "domotzpro-agent-publicstore"; then
      echo "domotzpro-agent-publicstore - INSTALLED"
      echo
      snap services domotzpro-agent-publicstore 2>/dev/null || true
      echo
      echo "Snap plugs (expected): firewall-control, network-observe, raw-usb, shutdown, system-observe"
      snap connections domotzpro-agent-publicstore 2>/dev/null | egrep "firewall-control|network-observe|raw-usb|shutdown|system-observe|^Interface" || true
    else
      echo "domotzpro-agent-publicstore - NOT INSTALLED"
    fi
  else
    echo "snap - NOT FOUND"
  fi

  hdr "TUN MODULE"
  grep -qxF "tun" /etc/modules 2>/dev/null && echo "/etc/modules - tun PRESENT" || echo "/etc/modules - tun MISSING"
  lsmod 2>/dev/null | awk '{print $1}' | grep -qx "tun" && echo "tun - LOADED" || echo "tun - NOT LOADED"

  hdr "NETWORK SUMMARY"
  ip -br addr || true
  echo
  ip route show default || true
  echo
  echo "/etc/resolv.conf:"
  [[ -r /etc/resolv.conf ]] && grep -E "^(nameserver|search)" /etc/resolv.conf || true

  hdr "NETPLAN FILES"
  if [[ -d /etc/netplan ]]; then
    ls -l /etc/netplan || true
    for f in /etc/netplan/*.yaml /etc/netplan/*.yml; do
      [[ -e "$f" ]] || continue
      echo -e "\n--- $f ---"
      sed -n '1,200p' "$f" || true
    done
  else
    echo "/etc/netplan - NOT FOUND"
  fi

  hdr "COMPLETE"
  echo "Log saved: $LOG_FILE"
}

main "$@"
