#!/bin/bash
# ============================
# Solutionz INC RMM Config Check (Linux)
# System Admin: Seneathia Williams
# Last Updated: 2025-11-18
# Description: Performs config diagnostics to verify the RMM Collector
configuration.
# ============================
# Define log file path
LOG_FILE="/var/log/RMM_Config_Check.log"
# Define ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color
# Function to colorize keywords, IPs, and hostnames
colorize() {
sed -E \
-e "s/\b(active)\b/${GREEN}\1${NC}/g" \
-e "s/\b(enabled)\b/${GREEN}\1${NC}/g" \
-e "s/\b(inactive)\b/${RED}\1${NC}/g" \
-e "s/\b(disabled)\b/${RED}\1${NC}/g" \
-e "s/\b(txt)\b/${YELLOW}\1${NC}/g" \
-e "s/([0-9]{1,3}(\.[0-9]{1,3}){3})/${YELLOW}\1${NC}/g" \
-e
"s/\b([a-zA-Z0-9._-]+\.local|[a-zA-Z0-9._-]+\.lan|[a-zA-Z0-9._-]+\.com|[a-zA-Z0-9._-
]+\.net)\b/${BLUE}\1${NC}/g"
}
# --- Display logo and welcome ---
echo -e "\033[36m"
cat <<'EOF'
_____ ____ _ _ _ _____ _ ____ _ _
/ ____| / __ \ | | | | | | |_ _| | | / __ \ | \ | | _____
| (___ | | | | | | | | | | | | | | | | | || \ | | |___ /
\___ \ | | | | | | | | | | | | | | | | | || |\ \| | / /
____) || |__| | | |___ | |__| | | | | | | |__| || | \ | / /__
|_____/ \____/ |_____| \____/ |_| |_| \____/ |_| \_| /_____|
Welcome to the Solutionz INC diagnostic script.
EOF
echo -e "\033[0m"
echo
"==============================================================================="
echo "Solutionz INC is now checking the RMM configurations. Please wait a moment..."
echo
"==============================================================================="
# Display header
echo -e "${YELLOW}===== RMM Configuration Check List =====${NC}"
echo "Date and Time: $(date)"
echo ""
echo -e "${YELLOW}=== Domotz Snap Connections ===${NC}"
sudo snap connections domotzpro-agent-publicstore | colorize
echo ""
echo -e "${YELLOW}=== SSH Service Status ===${NC}"
sudo systemctl status ssh --no-pager | colorize
echo ""
echo -e "${YELLOW}=== UFW Firewall Status ===${NC}"
sudo systemctl status ufw --no-pager | colorize
echo ""
echo -e "${YELLOW}=== Hostname Information ===${NC}"
hostnamectl | colorize
echo ""
echo -e "${YELLOW}=== Network Interfaces ===${NC}"
ip a | colorize
echo ""
echo -e "${YELLOW}=== Network Configuration ===${NC}"
ip route | colorize
echo ""
echo -e "${YELLOW}=== Netplan Configuration ===${NC}"
sudo cat /etc/netplan/00-installer-config.yaml | colorize
echo ""
echo -e "${YELLOW}===== End of RMM Configuration Check =====${NC}"
# Log plain-text version (no color codes)
{
echo "===== RMM Configuration Check List ====="
echo "Date and Time: $(date)"
echo ""
echo "=== Domotz Snap Connections ==="
sudo snap connections domotzpro-agent-publicstore
echo ""
echo "=== SSH Service Status ==="
sudo systemctl status ssh --no-pager
echo ""
echo "=== UFW Firewall Status ==="
sudo systemctl status ufw --no-pager
echo ""
echo "=== Hostname Information ==="
hostnamectl
echo ""
echo "=== Network Interfaces ==="
ip a
echo ""
echo "=== Network Configuration ==="
ip route
echo ""
echo "=== Netplan Configuration ==="
sudo cat /etc/netplan/00-installer-config.yaml
echo ""
echo "===== End of RMM Configuration Check ====="
echo ""
} >> "$LOG_FILE"
# --- Final timestamp and attribution ---
echo "======================================"
echo "Log completed at: $(date '+%Y-%m-%d %H:%M:%S')"
echo "Log saved to: $LOG_FILE"
echo "Script maintained by: RMM System Admin - Seneathia
Williams"echo "======================================"
