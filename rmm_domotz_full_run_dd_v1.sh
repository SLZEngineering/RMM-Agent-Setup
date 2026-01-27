#!/usr/bin/env bash
set -euo pipefail

REPO_OWNER="SLZEngineering"
REPO_NAME="domotz-setup"
BRANCH="main"
RAW_BASE="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${BRANCH}"

SETUP_SCRIPT="solutionz_domotz_setup_rev2.sh"
CONFIG_CHECK_SCRIPT="rmm_config_check_dd_v1.sh"
COLLECTOR_CHECK_SCRIPT="rmm_collector_connection_check_dd_v1"   # no .sh

DOMOTZ_SNAP="domotzpro-agent-publicstore"
DOMOTZ_IFACES=(
  "firewall-control"
  "network-observe"
  "raw-usb"
  "shutdown"
  "system-observe"
)

STATE_DIR="/var/lib/solutionz_rmm"
STAGE_FILE="${STATE_DIR}/stage"
RUN_DIR_FILE="${STATE_DIR}/run_dir"
LOCK_FILE="${STATE_DIR}/lock"

RUN_DIR="${ORIG_PWD:-$PWD}"
LOGDIR="/var/log/solutionz_rmm"
TS="$(date +%Y%m%d_%H%M%S)"
LOGFILE="${LOGDIR}/domotz_full_run_${TS}.log"

say() { echo -e "\n[$(date +'%F %T')] $*"; }
have_cmd() { command -v "$1" >/dev/null 2>&1; }

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    export ORIG_PWD="${RUN_DIR}"
    exec sudo -E bash "$0" "$@"
  fi
}

wait_for_snapd() {
  for _ in {1..60}; do
    snap version >/dev/null 2>&1 && return 0
    sleep 2
  done
  return 0
}

snap_is_installed() {
  snap list "${DOMOTZ_SNAP}" >/dev/null 2>&1
}

download() {
  local url="$1"
  local dest="$2"

  if have_cmd wget; then
    wget -qO "${dest}" "${url}"
  elif have_cmd curl; then
    curl -fsSL "${url}" -o "${dest}"
  else
    say "ERROR: Neither wget nor curl is available."
    exit 1
  fi

  if [[ ! -s "${dest}" ]]; then
    say "ERROR: Downloaded file is empty: ${dest}"
    exit 1
  fi
  if head -n 2 "${dest}" | grep -qiE '<!doctype html|<html'; then
    say "ERROR: Download looks like HTML (bad URL/404): ${url}"
    exit 1
  fi
}

do_connects_tun_restart() {
  wait_for_snapd
  for iface in "${DOMOTZ_IFACES[@]}"; do
    snap connect "${DOMOTZ_SNAP}:${iface}" || true
  done
  grep -qxF "tun" /etc/modules 2>/dev/null || echo "tun" >> /etc/modules
  modprobe tun || true
  snap restart "${DOMOTZ_SNAP}" || true
}

install_resume_service() {
  # You already have the auto-resume service, so we keep this lightweight:
  # do nothing if systemctl missing.
  have_cmd systemctl || return 0
  systemctl enable solutionz-rmm-resume.service >/dev/null 2>&1 || true
}

disable_resume_service() {
  have_cmd systemctl || return 0
  systemctl disable --now solutionz-rmm-resume.service >/dev/null 2>&1 || true
}

run_setup_auto_yes() {
  printf "yes\nyes\n" | "./${SETUP_SCRIPT}"
}

read_stage() {
  if [[ -f "${STAGE_FILE}" ]]; then
    # strip CRLF + whitespace
    tr -d '\r' < "${STAGE_FILE}" | xargs
  else
    echo ""
  fi
}

write_stage() {
  local s="$1"
  echo "${s}" > "${STAGE_FILE}"
}

resume_run() {
  mkdir -p "${STATE_DIR}" "${LOGDIR}"

  # prevent concurrent runs (manual + service)
  exec 9>"${LOCK_FILE}"
  flock -n 9 || exit 0

  # Determine RUN_DIR for logs/files
  if [[ -f "${RUN_DIR_FILE}" ]]; then
    RUN_DIR="$(cat "${RUN_DIR_FILE}" | tr -d '\r' | xargs)"
  else
    echo "${RUN_DIR}" > "${RUN_DIR_FILE}"
  fi

  local INTERNAL_DIR="${RUN_DIR}/.solutionz_rmm_full_run"
  local SETUP_LOG="${RUN_DIR}/setup.log"
  mkdir -p "${INTERNAL_DIR}"
  touch "${SETUP_LOG}"

  exec > >(tee -a "${SETUP_LOG}" "${LOGFILE}") 2>&1

  local stage
  stage="$(read_stage)"

  # If no stage yet, infer it
  if [[ -z "${stage}" ]]; then
    if snap_is_installed; then
      stage="post_snap"
    else
      stage="pre_snap"
    fi
    write_stage "${stage}"
  fi

  # Backward-compat mapping (THIS FIXES YOUR CURRENT LOOP)
  case "${stage}" in
    setup_pending) stage="setup" ;;
    config_pending) stage="config" ;;
    collector_pending) stage="collector" ;;
  esac
  write_stage "${stage}"

  say "Resume stage: ${stage}"
  say "Run directory: ${RUN_DIR}"
  say "setup.log: ${SETUP_LOG}"

  # If a script rebooted mid-run, advance appropriately
  if [[ "${stage}" == "setup_inprogress" ]]; then
    stage="config"; write_stage "${stage}"
  elif [[ "${stage}" == "config_inprogress" ]]; then
    stage="collector"; write_stage "${stage}"
  elif [[ "${stage}" == "collector_inprogress" ]]; then
    # collector reboot -> retry collector
    stage="collector"; write_stage "${stage}"
  fi

  case "${stage}" in
    pre_snap)
      say "PHASE 1 (Option B): apt update + snap install ONLY, then STOP."
      export DEBIAN_FRONTEND=noninteractive
      apt update

      if ! have_cmd wget && ! have_cmd curl; then
        apt-get install -y wget curl
      fi
      if ! have_cmd snap; then
        apt-get install -y snapd
      fi

      wait_for_snapd

      if snap_is_installed; then
        say "Snap already installed."
        write_stage "post_snap"
        exit 0
      fi

      say "Installing snap: ${DOMOTZ_SNAP}"
      snap install "${DOMOTZ_SNAP}" || true

      write_stage "post_snap"
      say "PHASE 1 complete. If the device rebooted, that is expected."
      say "Re-run the same one-liner ONCE after reboot to continue."
      exit 0
      ;;

    post_snap)
      # From here on, auto-resume should handle reboots between scripts
      install_resume_service
      write_stage "setup"
      stage="setup"
      ;;&

    setup)
      say "Connecting snap interfaces + enabling tun + restarting snap..."
      do_connects_tun_restart

      say "Downloading setup script into run directory..."
      cd "${RUN_DIR}"
      download "${RAW_BASE}/${SETUP_SCRIPT}" "${RUN_DIR}/${SETUP_SCRIPT}"
      chmod +x "${RUN_DIR}/${SETUP_SCRIPT}"

      say "Directory contents (ls):"
      ls

      write_stage "setup_inprogress"
      say "RUN: ./${SETUP_SCRIPT} (auto-YES x2)"
      run_setup_auto_yes || true

      write_stage "config"
      ;;&

    config)
      say "Downloading + running config check..."
      cd "${INTERNAL_DIR}"
      download "${RAW_BASE}/${CONFIG_CHECK_SCRIPT}" "${INTERNAL_DIR}/${CONFIG_CHECK_SCRIPT}"
      chmod +x "${INTERNAL_DIR}/${CONFIG_CHECK_SCRIPT}"

      write_stage "config_inprogress"
      say "RUN: ./${CONFIG_CHECK_SCRIPT}"
      ./"${CONFIG_CHECK_SCRIPT}" || true

      write_stage "collector"
      ;;&

    collector)
      say "Downloading + running collector connection check..."
      cd "${INTERNAL_DIR}"
      download "${RAW_BASE}/${COLLECTOR_CHECK_SCRIPT}" "${INTERNAL_DIR}/${COLLECTOR_CHECK_SCRIPT}"
      chmod +x "${INTERNAL_DIR}/${COLLECTOR_CHECK_SCRIPT}"

      write_stage "collector_inprogress"
      say "RUN: ./${COLLECTOR_CHECK_SCRIPT}"
      ./"${COLLECTOR_CHECK_SCRIPT}" || true

      write_stage "complete"
      say "All stages complete. Disabling auto-resume service."
      disable_resume_service
      ;;

    complete)
      say "Already complete. Nothing to do."
      disable_resume_service
      ;;

    *)
      say "Unknown stage '${stage}'. Resetting to post_snap."
      write_stage "post_snap"
      ;;
  esac
}

need_root "$@"

# Resume mode (called by the boot service)
if [[ "${1:-}" == "--resume" ]]; then
  resume_run
  exit 0
fi

# Manual mode: run once
resume_run

