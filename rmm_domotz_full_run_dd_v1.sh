#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Solutionz INC RMM Agent All-in-One Steup(Linux)
# System Admin: Seneathia Williams
# Last Updated: 2026-01-27
# Description: Performs setup, configuration, and connectivity checks
# ============================================================

# =========================
# Repo + files
# =========================
REPO_BASE="https://raw.githubusercontent.com/SLZEngineering/domotz-setup/main"

DOMOTZ_SNAP="domotzpro-agent-publicstore"

STATE_DIR="/var/lib/solutionz_rmm"
STAGE_FILE="${STATE_DIR}/stage"
RUN_DIR_FILE="${STATE_DIR}/run_dir"

LOGDIR="/var/log/solutionz_rmm"
TS="$(date +%Y%m%d_%H%M%S)"
LOGFILE="${LOGDIR}/domotz_wrapper_${TS}.log"

RUN_DIR="${ORIG_PWD:-$PWD}"
SETUP_LOG="${RUN_DIR}/setup.log"

say(){ echo -e "\n[$(date +'%F %T')] $*"; }
have_cmd(){ command -v "$1" >/dev/null 2>&1; }

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
  # retry because snapd can be slow after boot
  for _ in {1..30}; do
    snap list "${DOMOTZ_SNAP}" >/dev/null 2>&1 && return 0
    sleep 2
  done
  return 1
}

ensure_prereqs() {
  export DEBIAN_FRONTEND=noninteractive

  say "apt update"
  apt update

  if ! have_cmd wget && ! have_cmd curl; then
    say "Installing wget + curl"
    apt-get install -y wget curl
  fi

  if ! have_cmd snap; then
    say "Installing snapd"
    apt-get install -y snapd
  fi

  wait_for_snapd
}

install_snap_phase1_then_stop() {
  # OPTION B: install snap then STOP (snap install may reboot)
  say "Installing Domotz snap: ${DOMOTZ_SNAP}"
  snap install "${DOMOTZ_SNAP}" || true

  # If we reach here, mark for post-snap continuation
  echo "post_snap" > "${STAGE_FILE}" || true

  say "PHASE 1 complete."
  say "If the device rebooted, that's expected."
  say "After reboot, run the same one-liner ONE time to continue."
  exit 0
}

write_local_engine() {
  sudo tee /usr/local/sbin/solutionz_rmm_engine.sh >/dev/null <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Solutionz INC RMM Agent All-in-One Steup(Linux)
# System Admin: Seneathia Williams
# Last Updated: 2026-01-27
# Description: Performs setup, configuration, and connectivity checks
# ============================================================

REPO_BASE="https://raw.githubusercontent.com/SLZEngineering/domotz-setup/main"

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

# Marker files (resilience if stage file is deleted)
MARK_SETUP_STARTED="${STATE_DIR}/setup.started"
MARK_SETUP_DONE="${STATE_DIR}/setup.done"
MARK_CONFIG_STARTED="${STATE_DIR}/config.started"
MARK_CONFIG_DONE="${STATE_DIR}/config.done"
MARK_COLLECTOR_STARTED="${STATE_DIR}/collector.started"
MARK_COLLECTOR_DONE="${STATE_DIR}/collector.done"

LOGDIR="/var/log/solutionz_rmm"
TS="$(date +%Y%m%d_%H%M%S)"
LOGFILE="${LOGDIR}/domotz_engine_${TS}.log"

say(){ echo -e "\n[$(date +'%F %T')] $*"; }

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
  local url="$1" dest="$2"
  if command -v wget >/dev/null 2>&1; then
    wget -qO "${dest}" "${url}"
  elif command -v curl >/dev/null 2>&1; then
    curl -fsSL "${url}" -o "${dest}"
  else
    exit 1
  fi
  [[ -s "${dest}" ]] || exit 1
  if head -n 2 "${dest}" | grep -qiE '<!doctype html|<html'; then
    exit 1
  fi
}

read_stage() {
  [[ -f "${STAGE_FILE}" ]] || { echo ""; return; }
  tr -d '\r' < "${STAGE_FILE}" | xargs
}

write_stage() { echo "$1" > "${STAGE_FILE}"; }

normalize_stage() {
  local s="$1"
  case "$s" in
    setup_pending) echo "setup" ;;
    config_pending) echo "config" ;;
    collector_pending) echo "collector" ;;
    post_snap) echo "setup" ;;
    pre_snap) echo "pre_snap" ;;
    "") echo "" ;;
    *) echo "$s" ;;
  esac
}

infer_stage_from_markers() {
  # Highest precedence: done markers
  if [[ -f "${MARK_COLLECTOR_DONE}" ]]; then echo "complete"; return; fi
  if [[ -f "${MARK_CONFIG_DONE}" ]]; then echo "collector"; return; fi
  if [[ -f "${MARK_SETUP_DONE}" ]]; then echo "config"; return; fi

  # Started markers help recover if stage file is missing/deleted mid-run
  if [[ -f "${MARK_COLLECTOR_STARTED}" ]]; then echo "collector"; return; fi
  if [[ -f "${MARK_CONFIG_STARTED}" ]]; then echo "collector"; return; fi
  if [[ -f "${MARK_SETUP_STARTED}" ]]; then echo "config"; return; fi

  echo "setup"
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

run_setup_auto_yes() {
  # auto-answer the two prompts in your setup script
  printf "yes\nyes\n" | "./${SETUP_SCRIPT}"
}

main() {
  mkdir -p "${STATE_DIR}" "${LOGDIR}"

  # prevent double runs (manual + service)
  exec 9>"${LOCK_FILE}"
  if command -v flock >/dev/null 2>&1; then
    flock -n 9 || exit 0
  fi

  # Determine RUN_DIR (where setup.log lives)
  local RUN_DIR="/root"
  if [[ -f "${RUN_DIR_FILE}" ]]; then
    RUN_DIR="$(cat "${RUN_DIR_FILE}" | tr -d '\r' | xargs)"
  fi
  [[ -d "${RUN_DIR}" ]] || RUN_DIR="/root"

  local INTERNAL_DIR="${RUN_DIR}/.solutionz_rmm_full_run"
  local SETUP_LOG="${RUN_DIR}/setup.log"
  mkdir -p "${INTERNAL_DIR}"
  touch "${SETUP_LOG}"

  exec > >(tee -a "${SETUP_LOG}" "${LOGFILE}") 2>&1

  # If snap isn't installed yet, wait until wrapper finishes phase 1
  if ! snap_is_installed; then
    say "Domotz snap not installed yet (${DOMOTZ_SNAP}). Waiting for wrapper phase."
    exit 1
  fi

  local raw stage
  raw="$(read_stage)"
  stage="$(normalize_stage "${raw}")"

  # If reboot happened mid-run, advance
  if [[ "${stage}" == "setup_running" ]]; then stage="config"; fi
  if [[ "${stage}" == "config_running" ]]; then stage="collector"; fi
  if [[ "${stage}" == "collector_running" ]]; then stage="collector"; fi

  # If stage empty/unknown, infer from markers
  if [[ -z "${stage}" ]]; then
    stage="$(infer_stage_from_markers)"
  fi

  # Only accept known stages; otherwise infer
  case "${stage}" in
    setup|config|collector|complete) : ;;
    *) stage="$(infer_stage_from_markers)" ;;
  esac

  write_stage "${stage}"
  say "Stage: ${stage}"
  say "Run dir: ${RUN_DIR}"

  case "${stage}" in
    setup)
      touch "${MARK_SETUP_STARTED}" || true

      do_connects_tun_restart
      cd "${RUN_DIR}"

      download "${REPO_BASE}/${SETUP_SCRIPT}" "${RUN_DIR}/${SETUP_SCRIPT}"
      chmod +x "${RUN_DIR}/${SETUP_SCRIPT}"

      say "Directory contents (ls):"
      ls

      write_stage "setup_running"
      say "RUN: ./${SETUP_SCRIPT} (auto-YES x2)"
      run_setup_auto_yes || true

      # If it returns, mark done and move on
      touch "${MARK_SETUP_DONE}" || true
      write_stage "config"
      ;;&

    config)
      touch "${MARK_CONFIG_STARTED}" || true

      cd "${INTERNAL_DIR}"
      download "${REPO_BASE}/${CONFIG_CHECK_SCRIPT}" "${INTERNAL_DIR}/${CONFIG_CHECK_SCRIPT}"
      chmod +x "${INTERNAL_DIR}/${CONFIG_CHECK_SCRIPT}"

      write_stage "config_running"
      say "RUN: ./${CONFIG_CHECK_SCRIPT}"
      ./"${CONFIG_CHECK_SCRIPT}" || true

      touch "${MARK_CONFIG_DONE}" || true
      write_stage "collector"
      ;;&

    collector)
      touch "${MARK_COLLECTOR_STARTED}" || true

      cd "${INTERNAL_DIR}"
      download "${REPO_BASE}/${COLLECTOR_CHECK_SCRIPT}" "${INTERNAL_DIR}/${COLLECTOR_CHECK_SCRIPT}"
      chmod +x "${INTERNAL_DIR}/${COLLECTOR_CHECK_SCRIPT}"

      write_stage "collector_running"
      say "RUN: ./${COLLECTOR_CHECK_SCRIPT}"
      ./"${COLLECTOR_CHECK_SCRIPT}" || true

      touch "${MARK_COLLECTOR_DONE}" || true
      write_stage "complete"

      say "Complete. Disabling auto-resume service."
      systemctl disable --now solutionz-rmm-resume.service >/dev/null 2>&1 || true
      ;;

    complete)
      say "Already complete. Disabling auto-resume service."
      systemctl disable --now solutionz-rmm-resume.service >/dev/null 2>&1 || true
      ;;
  esac
}

main
EOF

  sudo chmod +x /usr/local/sbin/solutionz_rmm_engine.sh
}

write_resume_service() {
  sudo tee /etc/systemd/system/solutionz-rmm-resume.service >/dev/null <<'EOF'
[Unit]
Description=Solutionz RMM Domotz Auto-Resume
After=network-online.target snapd.service
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/sbin/solutionz_rmm_engine.sh
Restart=always
RestartSec=20

[Install]
WantedBy=multi-user.target
EOF

  sudo systemctl daemon-reload
  sudo systemctl enable --now solutionz-rmm-resume.service
}

main() {
  need_root "$@"

  mkdir -p "${STATE_DIR}" "${LOGDIR}"
  touch "${SETUP_LOG}"

  exec > >(tee -a "${SETUP_LOG}" "${LOGFILE}") 2>&1

  say "Starting wrapper (Option B + Auto-resume)"
  say "Run dir: ${RUN_DIR}"
  say "setup.log: ${SETUP_LOG}"

  # Persist run dir for service boots
  echo "${RUN_DIR}" > "${RUN_DIR_FILE}"

  ensure_prereqs

  # Phase 1: snap install then STOP to avoid reboot loops
  if ! snap_is_installed; then
    echo "pre_snap" > "${STAGE_FILE}" || true
    install_snap_phase1_then_stop
  fi

  # Phase 2: install local engine + service that handles reboots automatically
  say "Snap present. Installing local resume engine + service..."

  # Stop any older looping service before replacing it
  sudo systemctl disable --now solutionz-rmm-resume.service >/dev/null 2>&1 || true

  # Initialize stage if missing/empty/legacy
  if [[ -f "${STAGE_FILE}" ]]; then
    s="$(tr -d '\r' < "${STAGE_FILE}" | xargs)"
    case "${s}" in
      setup_pending|config_pending|collector_pending|post_snap|pre_snap|"") echo "setup" > "${STAGE_FILE}" ;;
      setup|setup_running|config|config_running|collector|collector_running|complete) : ;;
      *) echo "setup" > "${STAGE_FILE}" ;;
    esac
  else
    echo "setup" > "${STAGE_FILE}"
  fi

  write_local_engine
  write_resume_service

  # Kick engine immediately (service will also retry on reboot)
  sudo systemctl restart solutionz-rmm-resume.service

  say "Auto-resume enabled."
  say "It will continue after each reboot until complete, then disable itself."
  say "Watch progress: tail -f ${SETUP_LOG}"
}

main "$@"
