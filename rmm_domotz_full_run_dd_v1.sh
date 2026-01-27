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
COLLECTOR_CHECK_SCRIPT="rmm_collector_connection_check_dd_v1"   # (no .sh)

# =========================
# Runtime locations
# =========================
WORKDIR="/tmp/solutionz_rmm_full_run"
LOGDIR="/var/log/solutionz_rmm"
TS="$(date +%Y%m%d_%H%M%S)"
LOGFILE="${LOGDIR}/domotz_full_run_${TS}.log"

say() { echo -e "\n[$(date +'%F %T')] $*"; }

have_cmd() { command -v "$1" >/dev/null 2>&1; }

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
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

  # sanity checks (avoid saving HTML error pages)
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
  local setup_path="$1"
  # Feeds exactly 2 yes answers ("Answer yes to both questions")
  printf "yes\nyes\n" | bash "${setup_path}"
}

# -------------------------
# Main
# -------------------------
need_root "$@"

mkdir -p "${WORKDIR}" "${LOGDIR}"
chmod 700 "${WORKDIR}" || true

# Log everything
exec > >(tee -a "${LOGFILE}") 2>&1

say "Starting Domotz full automation run"
say "Workdir: ${WORKDIR}"
say "Logfile: ${LOGFILE}"

cd "${WORKDIR}"

# 1) Download all scripts
say "Downloading ${SETUP_SCRIPT}..."
download "${RAW_BASE}/${SETUP_SCRIPT}" "${WORKDIR}/${SETUP_SCRIPT}"

say "Downloading ${CONFIG_CHECK_SCRIPT}..."
download "${RAW_BASE}/${CONFIG_CHECK_SCRIPT}" "${WORKDIR}/${CONFIG_CHECK_SCRIPT}"

say "Downloading ${COLLECTOR_CHECK_SCRIPT}..."
download "${RAW_BASE}/${COLLECTOR_CHECK_SCRIPT}" "${WORKDIR}/${COLLECTOR_CHECK_SCRIPT}"

# 2) Verify downloads (like your 'ls' step)
say "Downloaded files (ls):"
ls -la

# 3) Make executable
chmod +x "${WORKDIR}/${SETUP_SCRIPT}" "${WORKDIR}/${CONFIG_CHECK_SCRIPT}" "${WORKDIR}/${COLLECTOR_CHECK_SCRIPT}"

# 4) Run setup script (auto-YES)
say "=== RUN 1/3: ${SETUP_SCRIPT} ==="
run_setup_auto_yes "${WORKDIR}/${SETUP_SCRIPT}"

# 5) Run config check
say "=== RUN 2/3: ${CONFIG_CHECK_SCRIPT} ==="
bash "${WORKDIR}/${CONFIG_CHECK_SCRIPT}"

# 6) Run collector connection check
say "=== RUN 3/3: ${COLLECTOR_CHECK_SCRIPT} ==="
bash "${WORKDIR}/${COLLECTOR_CHECK_SCRIPT}"

say "DONE. Review log if needed: ${LOGFILE}"
