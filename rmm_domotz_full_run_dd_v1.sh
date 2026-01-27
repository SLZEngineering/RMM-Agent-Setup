#!/usr/bin/env bash
set -euo pipefail

# =========================
# GitHub Raw location
# =========================
REPO_OWNER="SLZEngineering"
REPO_NAME="domotz-setup"
BRANCH="main"
RAW_BASE="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${BRANCH}"

# =========================
# Script names (exact)
# =========================
SETUP_SCRIPT="solutionz_domotz_setup_rev2.sh"
CONFIG_CHECK_SCRIPT="rmm_config_check_dd_v1.sh"
COLLECTOR_CHECK_SCRIPT="rmm_collector_connection_check_dd_v1"   # no .sh

# =========================
# Domotz snap package + interfaces
# =========================
DOMOTZ_SNAP="domotzpro-agent-publicstore"
DOMOTZ_IFACES=(
  "firewall-control"
  "network-observe"
  "raw-usb"
  "shutdown"
  "system-observe"
)

# =========================
# State / logging
# =========================
STATE_DIR="/var/lib/solutionz_rmm"
STAGE_FILE="${STATE_DIR}/stage"
RUN_DIR_FILE="${STATE_DIR}/run_dir"
LOCK_FILE="${STATE_DIR}/lock"

# Keep setup.log in the directory tech ran the command from (matches your screenshot)
RUN_DIR="${ORIG_PWD:-$PWD}"
INTERNAL_DIR="${RUN_DIR}/.solutionz_rmm_full_run"
SETUP_LOG="${RUN_DIR}/setup.log"

# Timestamped log copy under /var/log
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
  for _ in {1..45}; do
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

install_resume_service() {
  # Install a small systemd oneshot service that runs this same script in --resume mode at boot
  if ! have_cmd systemctl; then
    say "systemctl not found; cannot enable auto-resume at boot."
    return 0
  fi

  local runner="/usr/local/sbin/solutionz_rmm_resume.sh"
  local unit="/etc/systemd/system/solutionz-rmm-resume.service"

  # Write runner that simply calls this GitHub-managed logic (embedded below) by copying this script content
  # NOTE: since this file is often streamed via wget|bash, we can't 'cp $0', so we install a standalone runner.
  cat > "${runner}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
# This runner just calls the current wrapper from the repo and runs it in resume mode.
# If the device has no internet at boot, it will try again next boot.
URL="https://raw.githubusercontent.com/SLZEngineering/domotz-setup/main/rmm_domotz_full_run_dd_v1.sh"
if command -v wget >/dev/null 2>&1; then
  wget -qO- "${URL}" | sudo bash -s -- --resume
elif command -v curl >/dev/null 2>&1; then
  curl -fsSL "${URL}" | sudo bash -s -- --resume
fi
EOF
  chmod +x "${runner}"

  cat > "${unit}" <<EOF
[Unit]
Description=Solutionz RMM Domotz Resume
After=network-online.target snapd.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=${runner}

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable solutionz-rmm-resume.service >/dev/null 2>&1 || true
}

disable_resume_service() {
  if have_cmd systemctl; then
    systemctl disable --now solutionz-rmm-resume.service >/dev/null 2>&1 || true
  fi
}

run_setup_auto_yes() {
  printf "yes\nyes\n" | "./${SETUP_SCRIPT}"
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

# -------------------------
# RESUME ENGINE (stage machine)
# -------------------------
resume_run() {
  mkdir -p "${STATE_DIR}" "${LOGDIR}"
  # Lock so we never run twice (manual + service)
  exec 9>"${LOCK_FILE}"
  flock -n 9 || exit 0

  # Determine RUN_DIR for logs/files
  if [[ -f "${RUN_DIR_FILE}" ]]; then
    RUN_DIR="$(cat "${RUN_DIR_FILE}")"
  else
    echo "${RUN_DIR}" > "${RUN_DIR_FILE}"
  fi

  INTERNAL_DIR="${RUN_DIR}/.solutionz_rmm_full_run"
  SETUP_LOG="${RUN_DIR}/setup.log"

  mkdir -p "${INTERNAL_DIR}"
  touch "${SETUP_LOG}"

  exec > >(tee -a "${SETUP_LOG}" "${LOGFILE}") 2>&1

  local stage=""
  [[ -f "${STAGE_FILE}" ]] && stage="$(cat "${STAGE_FILE}")"

  # If no stage yet, infer where we are
  if [[ -z "${stage}" ]]; then
    if snap_is_installed; then
      stage="post_snap"
    else
      stage="pre_snap"
    fi
    echo "${stage}" > "${STAGE_FILE}"
  fi

  say "Resume stage: ${stage}"
  say "Run directory: ${RUN_DIR}"
  say "setup.log: ${SETUP_LOG}"

  # If we crashed/rebooted during a stage, advance as requested:
  # - setup_inprogress -> run config next
  # - config_inprogress -> run collector next
  if [[ "${stage}" == "setup_inprogress" ]]; then
    stage="config_pending"; echo "${stage}" > "${STAGE_FILE}"
  elif [[ "${stage}" == "config_inprogress" ]]; then
    stage="collector_pending"; echo "${stage}" > "${STAGE_FILE}"
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
        echo "post_snap" > "${STAGE_FILE}"
        exit 0
      fi

      say "Installing snap: ${DOMOTZ_SNAP}"
      snap install "${DOMOTZ_SNAP}" || true

      # Mark that snap stage is done and STOP (tech reruns after reboot)
      echo "post_snap" > "${STAGE_FILE}"
      say "PHASE 1 complete. If the device rebooted, that is expected."
      say "Re-run the same one-liner ONCE after reboot to continue (auto-resume will handle later reboots)."
      exit 0
      ;;

    post_snap)
      # From here on, enable auto-resume for reboots between scripts
      say "Enabling auto-resume at boot for remaining stages."
      install_resume_service
      echo "setup_pending" > "${STAGE_FILE}"
      stage="setup_pending"
      ;;&  # fall-through

    setup_pending)
      say "Connecting snap interfaces + enabling tun + restarting snap..."
      do_connects_tun_restart

      say "Downloading setup script into run directory..."
      cd "${RUN_DIR}"
      download "${RAW_BASE}/${SETUP_SCRIPT}" "${RUN_DIR}/${SETUP_SCRIPT}"
      chmod +x "${RUN_DIR}/${SETUP_SCRIPT}"

      say "Directory contents (ls):"
      ls

      # Set in-progress before running so reboot will resume to config
      echo "setup_inprogress" > "${STAGE_FILE}"
      say "RUN: ./${SETUP_SCRIPT} (auto-YES x2)"
      run_setup_auto_yes || true

      # If it returns, advance normally
      echo "config_pending" > "${STAGE_FILE}"
      ;;&

    config_pending)
      say "Downloading + running config check..."
      mkdir -p "${INTERNAL_DIR}"
      cd "${INTERNAL_DIR}"
      download "${RAW_BASE}/${CONFIG_CHECK_SCRIPT}" "${INTERNAL_DIR}/${CONFIG_CHECK_SCRIPT}"
      chmod +x "${INTERNAL_DIR}/${CONFIG_CHECK_SCRIPT}"

      # Set in-progress before running so reboot will resume to collector
      echo "config_inprogress" > "${STAGE_FILE}"
      say "RUN: ./${CONFIG_CHECK_SCRIPT}"
      ./"${CONFIG_CHECK_SCRIPT}" || true

      # If it returns, advance normally
      echo "collector_pending" > "${STAGE_FILE}"
      ;;&

    collector_pending)
      say "Downloading + running collector connection check..."
      mkdir -p "${INTERNAL_DIR}"
      cd "${INTERNAL_DIR}"
      download "${RAW_BASE}/${COLLECTOR_CHECK_SCRIPT}" "${INTERNAL_DIR}/${COLLECTOR_CHECK_SCRIPT}"
      chmod +x "${INTERNAL_DIR}/${COLLECTOR_CHECK_SCRIPT}"

      echo "collector_inprogress" > "${STAGE_FILE}"
      say "RUN: ./${COLLECTOR_CHECK_SCRIPT}"
      ./"${COLLECTOR_CHECK_SCRIPT}" || true

      echo "complete" > "${STAGE_FILE}"
      say "All stages complete. Disabling auto-resume service."
      disable_resume_service
      ;;

    complete)
      say "Already complete. Nothing to do."
      disable_resume_service
      ;;

    *)
      say "Unknown stage '${stage}'. Resetting to post_snap."
      echo "post_snap" > "${STAGE_FILE}"
      ;;
  esac
}

# -------------------------
# Main
# -------------------------
need_root "$@"

# If called by resume service, we'll run resume mode directly
if [[ "${1:-}" == "--resume" ]]; then
  resume_run
  exit 0
fi

# Normal manual start: run resume engine once
resume_run
