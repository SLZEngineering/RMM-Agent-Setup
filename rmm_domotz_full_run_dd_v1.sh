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
# Run directory behavior
# - RUN_DIR = where tech runs the command (matches your screenshot dir)
# - INTERNAL_DIR holds extra scripts so ls stays clean
# =========================
RUN_DIR="${ORIG_PWD:-$PWD}"
INTERNAL_DIR="${RUN_DIR}/.solutionz_rmm_full_run"

# Create/append logs in the same directory as your screenshot
SETUP_LOG="${RUN_DIR}/setup.log"

# Also keep a timestamped log copy under /var/log
LOGDIR="/var/log/solutionz_rmm"
TS="$(date +%Y%m%d_%H%M%S)"
LOGFILE="${LOGDIR}/domotz_full_run_${TS}.log"

say() { echo -e "\n[$(date +'%F %T')] $*"; }
have_cmd() { command -v "$1" >/dev/null 2>&1; }

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    export ORIG_PWD="${RUN_DIR}"
    say "Re-running as root with sudo..."
    exec sudo -E bash "$0" "$@"
  fi
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

  # Sanity checks (avoid saving HTML error pages)
  if [[ ! -s "${dest}" ]]; then
    say "ERROR: Downloaded file is empty: ${dest}"
    exit 1
  fi
  if head -n 2 "${dest}" | grep -qiE '<!doctype html|<html'; then
    say "ERROR: Download looks like HTML (bad URL/404): ${url}"
    exit 1
  fi
}

run_setup_auto_yes() {
  # Runs exactly like: sudo ./solutionz_domotz_setup_rev2.sh
  # (we're already root inside this wrapper)
  printf "yes\nyes\n" | "./${SETUP_SCRIPT}"
}

# -------------------------
# Main
# -------------------------
need_root "$@"

mkdir -p "${INTERNAL_DIR}" "${LOGDIR}"
touch "${SETUP_LOG}"

# Log to BOTH: setup.log in RUN_DIR AND a timestamped /var/log copy
exec > >(tee -a "${SETUP_LOG}" "${LOGFILE}") 2>&1

say "Starting Domotz full automation run"
say "Run directory: ${RUN_DIR}"
say "Internal dir:  ${INTERNAL_DIR}"
say "setup.log:     ${SETUP_LOG}"
say "full log copy: ${LOGFILE}"

cd "${RUN_DIR}"

# 1) Download setup script into RUN_DIR (so ls matches your screenshot)
say "Downloading ${SETUP_SCRIPT} into ${RUN_DIR}..."
download "${RAW_BASE}/${SETUP_SCRIPT}" "${RUN_DIR}/${SETUP_SCRIPT}"

# 2) Download other scripts into hidden INTERNAL_DIR (keeps ls clean)
say "Downloading ${CONFIG_CHECK_SCRIPT} into ${INTERNAL_DIR}..."
download "${RAW_BASE}/${CONFIG_CHECK_SCRIPT}" "${INTERNAL_DIR}/${CONFIG_CHECK_SCRIPT}"

say "Downloading ${COLLECTOR_CHECK_SCRIPT} into ${INTERNAL_DIR}..."
download "${RAW_BASE}/${COLLECTOR_CHECK_SCRIPT}" "${INTERNAL_DIR}/${COLLECTOR_CHECK_SCRIPT}"

# 3) Verify downloads (your doc's 'ls' step)
say "Directory contents (ls) — should match your screenshot style:"
ls

# 4) chmod +x (your Step 3)
chmod +x "${RUN_DIR}/${SETUP_SCRIPT}"
chmod +x "${INTERNAL_DIR}/${CONFIG_CHECK_SCRIPT}" "${INTERNAL_DIR}/${COLLECTOR_CHECK_SCRIPT}"

# 5) Run setup script with ./ (your Step 4 style)
say "=== RUN 1/3: sudo ./${SETUP_SCRIPT} (auto-YES x2) ==="
run_setup_auto_yes

# 6) Run config check
say "=== RUN 2/3: ${CONFIG_CHECK_SCRIPT} ==="
cd "${INTERNAL_DIR}"
./"${CONFIG_CHECK_SCRIPT}"

# 7) Run collector connection check
say "=== RUN 3/3: ${COLLECTOR_CHECK_SCRIPT} ==="
./"${COLLECTOR_CHECK_SCRIPT}"

say "DONE."
say "setup.log is in: ${SETUP_LOG}"
say "additional timestamped log is in: ${LOGFILE}"
