#!/bin/bash
# ============================
# Solutionz INC RMM Collector Image (Linux)
# System Admin: Darrel Della
# Last Updated: 2025-11-18
# Description: Install and update the collector to Solutionz RMM configuration.
# Custom MOTD for Ubuntu Minimal Server
# ============================

set -e
exec > >(tee -i RMM Collector.log)
exec 2>&1

# --- Display logo and welcome ---
echo -e "\e[36m
  _____   ____    _      _    _   _____   _    ____   _     _
 / ____| / __ \  | |    | |  | | |_   _| | |  / __ \ | \   | |  _____
| (___  | |  | | | |    | |  | |   | |   | | | |  | ||  \  | | |___ /
 \___ \ | |  | | | |    | |  | |   | |   | | | |  | || |\ \| |   / /
 ____) || |__| | | |___ | |__| |   | |   | | | |__| || |  \  |  / /__
|_____/  \____/  |_____| \____/    |_|   |_|  \____/ |_|   \_| /_____|

Welcome to the Solutionz INC configuration script.
\e[0m"

# Confirmation message
echo "------------------------------------------------------------"
echo "This script will perform the following actions:"
echo "1. Update System and install key packages"
echo "2. Load the 'tun' module if not already loaded"
echo "3. Install Domotz Pro agent via Snap Store"
echo "4. Grant permissions to Domotz Pro agent"
echo "5. Enabling UFW Firewall and allow SSH"
echo "6. Allow port 3000 in UFW"
echo "7. Configure netplan for DHCP on attached NICs"
echo "8. Resolve VPN on Demand issue with DNS"
echo "9. Disable cloud-init's network configuration"
echo "10. Enable and start SSH service, install package lists..."
echo "11. Adding hostnames solzrmm and solz-rmm if they do not exist"
echo "12. Automatically append kernel parameters to GRUB config"
echo "13. Configuring Serial Console Access on Protectli"
echo "14. Update Banner"
echo "------------------------------------------------------------"
echo "Disclaimer:"
echo
echo "1. Purpose: This script is designed for Solutionz RMM Collector, created by Darrel Della, RMM Engineer."
echo "2. By proceeding, you confirm that:"
echo "   - The script will modify system configurations and install necessary packages."
echo "   - It may update system files and settings as per its instructions."
echo "   - Using this script on an already configured system may lead to unexpected behavior."
echo "3. Responsibility: You are responsible for any consequences resulting from running this script."
echo
read -p "Type 'yes' to proceed: " confirmation1
if [ "$confirmation1" != "yes" ]; then
    echo "Confirmation not received. Exiting script."
    exit 1
fi
echo "------------------------------------------------------------"
echo "Please confirm again to proceed."
read -p "Type 'yes' to proceed: " confirmation2
if [ "$confirmation2" != "yes" ]; then
    echo "Confirmation not received. Exiting script."
    exit 1
fi
# Set non-interactive mode for package configuration and disables NEEDRESTART MESSAGES
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
# Function to display step messages
step_message() {
    echo "------------------------------------------------------------"
    echo "Step $1: $2"
    echo "------------------------------------------------------------"
}
# Function to display real-time feedback
progress_message() {
    echo "   [+] $1"
}
# Step 1: Update and install packages
step_message 1 "Updating System and installing key packages"

progress_message "Suppressing apt script warnings..."
echo "Apt::Cmd::Disable-Script-Warning true;" | sudo tee /etc/apt/apt.conf.d/90disablescriptwarning

progress_message "Updating package lists..."
sudo apt update

progress_message "Upgrading packages..."
sudo apt upgrade -y

progress_message "Installing required diagnostic and connectivity tools..."
declare -A packages=(
  [net-tools]="Legacy networking tools"
  [openvswitch-switch]="Virtual switch for advanced networking"
  [traceroute]="Packet path tracing"
  [dnsutils]="DNS resolution testing"
  [curl]="HTTP/S data transfer"
  [openssl]="SSL/TLS diagnostics"
  [netcat-openbsd]="TCP/UDP connectivity testing"
  [nano]="Text editor"
  [iputils-ping]="ICMP ping utility"
)
for pkg in "${!packages[@]}"; do
  if ! dpkg -s "$pkg" &> /dev/null; then
    progress_message "Installing $pkg - ${packages[$pkg]}"
    sudo apt install -y "$pkg"
  else
    progress_message "$pkg is already installed."
  fi
done
# Step 2
step_message 2 "Loading tun module if not already loaded"
progress_message "Loading 'tun' module..."
sudo modprobe tun
sudo grep -qxF "tun" /etc/modules || sudo sh -c 'echo "tun" >> /etc/modules'
# Step 3
step_message 3 "Installing Domotz Pro agent via Snap Store"
progress_message "Installing Domotz Pro agent..."
sudo snap install domotzpro-agent-publicstore
# Step 4
step_message 4 "Granting permissions to Domotz Pro agent"
permissions=("firewall-control" "network-observe" "raw-usb" "shutdown" "system-observe")
for permission in "${permissions[@]}"; do
    progress_message "Connecting Domotz Pro agent: $permission..."
    sudo snap connect "domotzpro-agent-publicstore:$permission"
done
# Step 5
step_message 5 "Enabling UFW Firewall and allow SSH"
progress_message "Installing and enabling UFW..."
# Install UFW if not already installed
if ! dpkg -s ufw >/dev/null 2>&1; then
    sudo apt-get install -y ufw
    echo "UFW installed successfully."
else
    echo "UFW is already installed."
fi
progress_message "Allowing SSH through UFW..."
# Allow SSH through UFW
sudo ufw allow ssh
# Enable UFW without interactive prompt
sudo ufw --force enable
# Show verbose status
sudo ufw status verbose
# Step 6
step_message 6 "Allowing port 3000 in UFW"
progress_message "Creating firewall rule"
sudo ufw allow 3000
# Step 7
step_message 7 "Configuring netplan for DHCP on attached NICs"
progress_message "Editing netplan configuration file..."
sudo tee /etc/netplan/00-installer-config.yaml > /dev/null <<EOL
network:
    version: 2
    ethernets:
        all-en:
            match:
                name: "en*"
            dhcp4: true
            dhcp6: false
            accept-ra: false
        all-eth:
            match:
                name: "eth*"
            dhcp4: true
            dhcp6: false
            accept-ra: false
EOL
sudo chmod 600 /etc/netplan/00-installer-config.yaml
sudo rm -f /etc/netplan/50-cloud-init.yaml
sudo rm -f /etc/netplan/50-cloud-init.yaml.save
sudo rm -f /etc/netplan/90-solutionz-config.yaml
sudo netplan apply
# Step 8
step_message 8 "Resolving VPN on Demand issue with DNS"
progress_message "Swapping resolv.conf file link..."
sudo unlink /etc/resolv.conf
sudo ln -s /run/systemd/resolve/resolv.conf /etc/resolv.conf
ls -l /etc/resolv.conf
# Step 9
step_message 9 "Disabling cloud-init's network configuration"
progress_message "Creating /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg"
echo "network: {config: disabled}" | sudo tee /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
# Step 10
step_message 10 "Enabling SSH Service, install package lists..."
progress_message "Installing and starting OpenSSH server..."
sudo apt install -y openssh-server
sudo systemctl enable ssh
sudo systemctl start ssh
sudo systemctl status ssh --no-pager
echo "Installing nano..."
sudo apt install -y nano
echo "Installing iputils-ping..."
sudo apt install -y iputils-ping
echo "All requested packages are installed."
# Step 11
step_message 11 "Adding hostnames solzrmm and solz-rmm if they do not exist"

progress_message "Checking and adding hostname entries to /etc/hosts..."

HOST_ENTRIES=("127.0.1.1    solzrmm" "127.0.1.1    solz-rmm")

for entry in "${HOST_ENTRIES[@]}"; do
    if grep -q "$entry" /etc/hosts; then
        echo "Hostname entry '$entry' already exists in /etc/hosts."
    else
        echo "Adding hostname entry '$entry' to /etc/hosts..."
        echo "$entry" | sudo tee -a /etc/hosts > /dev/null
        echo "Hostname entry '$entry' added successfully."
    fi
done

# Step 12
step_message 12 "Automatically append kernel parameters to GRUB config"
progress_message "Safely modify GRUB to disable predictable network interface names"
GRUB_FILE="/etc/default/grub"
PARAMS="net.ifnames=0 biosdevname=0"
echo "Modifying GRUB configuration..."
# Backup GRUB config
sudo cp "$GRUB_FILE" "${GRUB_FILE}.bak"
# Check if GRUB_CMDLINE_LINUX exists
if grep -q "^GRUB_CMDLINE_LINUX=" "$GRUB_FILE"; then
    # Append only if parameters are not already present
    if ! grep -q "$PARAMS" "$GRUB_FILE"; then
        sudo sed -i "/^GRUB_CMDLINE_LINUX=/ s/\"\(.*\)\"/\"\1 $PARAMS\"/" "$GRUB_FILE"
        echo "Added kernel parameters to GRUB_CMDLINE_LINUX."
    else
        echo "Kernel parameters already set in GRUB config."
    fi
else
    # Add the line if it doesn't exist
    echo "GRUB_CMDLINE_LINUX=\"$PARAMS\"" | sudo tee -a "$GRUB_FILE"
    echo "Created GRUB_CMDLINE_LINUX entry with kernel parameters."
fi
# Step 13
step_message 13 "Configuring Serial Console Access on Protectli"

progress_message "Editing GRUB configuration for serial console..."
sudo sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=".*"/GRUB_CMDLINE_LINUX_DEFAULT="console=tty0 console=ttyS0,115200n8"/' /etc/default/grub

progress_message "Creating systemd drop-in for serial-getty@ttyS0..."
sudo mkdir -p /etc/systemd/system/serial-getty@ttyS0.service.d
cat <<EOF | sudo tee /etc/systemd/system/serial-getty@ttyS0.service.d/override.conf > /dev/null
[Service]
ExecStart=
ExecStart=-/sbin/agetty -o -p -- \\u --keep-baud 115200,57600,38400,9600 ttyS0 vt220
EOF

progress_message "Reloading systemd daemon..."
sudo systemctl daemon-reexec
sudo systemctl daemon-reload

progress_message "Enabling and starting serial-getty@ttyS0 service..."
sudo systemctl enable serial-getty@ttyS0.service
sudo systemctl restart serial-getty@ttyS0.service

progress_message "Verifying agetty process on ttyS0..."
ps aux | grep '[a]getty' | grep ttyS0 || echo "Warning: agetty not detected on ttyS0"

echo "Serial console configuration completed."
echo "------------------------------------------------------------"

# Step 14
step_message 14 "Update Banner"
progress_message "Adding Banner"

sudo tee /etc/update-motd.d/slz-dd-login > /dev/null <<'EOF'
#!/bin/bash
# /etc/update-motd.d/slz-dd-login
# Custom MOTD for Ubuntu Minimal Server

YELLOW='\033[1;33m'
NC='\033[0m'

cat << "BANNER"
  _____   ____    _      _    _   _____   _    ____   _     _
 / ____| / __ \  | |    | |  | | |_   _| | |  / __ \ | \   | |  _____
| (___  | |  | | | |    | |  | |   | |   | | | |  | ||  \  | | |___ /
 \___ \ | |  | | | |    | |  | |   | |   | | | |  | || |\ \| |   / /
 ____) || |__| | | |___ | |__| |   | |   | | | |__| || |  \  |  / /__
|_____/  \____/  |_____| \____/    |_|   |_|  \____/ |_|   \_| /_____|
BANNER

echo -e "${YELLOW}Welcome to the Solutionz RMM Collector Login.${NC}"
echo "============================================================"
echo "Solutionz RMM System Admin: Darrel Della '''\_(~_-)_/'''"
echo "------------------------------------------------------------"
hostnamectl
echo "------------------------------------------------------------"
ip a
echo "------------------------------------------------------------"
echo "Uptime:   $(uptime -p)"
echo -e "${YELLOW}Kernel:   $(uname -r)${NC}"
echo "CPU:      $(lscpu | grep 'Model name' | awk -F: '{print $2}' | xargs)"
echo "Memory:   $(free -h | awk '/Mem:/ {print $3 \"/\" $2}')"
echo "Disk:     $(df -h / | awk 'NR==2 {print $3\"/\"$2 \" used\"}')"
echo "IP Addr:  $(hostname -I)"
echo "============================================================"
echo " System information as of $(date)"
EOF

sudo chmod +x /etc/update-motd.d/slz-dd-login

# System info summary
echo " System information as of $(date)"
echo ""
echo "  System load:  $(uptime | awk -F'load average:' '{print $2}' | cut -d, -f1)"
echo "  Usage of /:   $(df -h / | awk 'NR==2 {print $5}') of $(df -h / | awk 'NR==2 {print $2}')"
echo "  Memory usage: $(free | awk '/Mem:/ {printf(\"%.0f%%\", $3/$2*100)}')"
echo "  Swap usage:   $(free | awk '/Swap:/ {printf(\"%.0f%%\", $3/$2*100)}')"
echo "  Processes:    $(ps -e | wc -l)"
echo "  Users logged in: $(who | wc -l)"
echo "  IPv4 address for eth0: $(ip -4 addr show eth0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')"

apt list --upgradable 2>/dev/null | grep -c upgradable | awk '{print $1 " updates can be applied immediately."}'
echo "To see these additional updates run: apt list --upgradable"

echo "============================================================"

# Apply changes
echo "GRUB updated. Rebooting system now..."
read -p "Press Enter to reboot now or Ctrl+C to cancel..." < /dev/tty

# Log completion timestamp
echo "------------------------------------------------------------"
echo "   [+] Setup completed successfully!"
echo "   [+] Completion Time: $(date)"
echo "   [+] Hostname: $(hostname)"
echo "   [+] Script Version: v2.0"
echo "------------------------------------------------------------"

sudo update-grub
sudo reboot
