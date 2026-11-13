#!/usr/bin/env bash
# ==============================================================================
# Script Name : setup_environment.sh
# Description : Automated setup script for Ubuntu 24.04 LTS according to specification
# Usage       : sudo bash setup_environment.sh
# ==============================================================================

set -euo pipefail

# Ensure script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "[ERROR] This setup script must be run as root (sudo)." >&2
    exit 1
fi

echo "======================================================================"
echo " Starting System Environment Setup for Agent App (Ubuntu 24.04 LTS)"
echo "======================================================================"

# ------------------------------------------------------------------------------
# 1. Basic Security & Network Configuration (SSH & UFW)
# ------------------------------------------------------------------------------
echo ""
echo "[1/5] Configuring SSH and Firewall..."

# 1-1. SSH Port & Root Login configuration
SSH_CONFIG_DROPIN="/etc/ssh/sshd_config.d/agent-security.conf"
echo "Creating SSH security drop-in config: ${SSH_CONFIG_DROPIN}"
cat << 'EOF' > "$SSH_CONFIG_DROPIN"
Port 20022
PermitRootLogin no
EOF

# In Ubuntu 24.04 LTS, SSH may be managed via ssh.socket or ssh.service
systemctl daemon-reload || true
if systemctl is-active --quiet ssh.socket; then
    # If socket activated, restart socket and service
    systemctl restart ssh.socket || true
fi
systemctl restart ssh || systemctl restart sshd || true
echo "  -> SSH Port set to 20022 and PermitRootLogin set to no."

# 1-2. Firewall configuration (UFW)
if command -v ufw >/dev/null 2>&1; then
    echo "Configuring UFW rules..."
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow 20022/tcp comment 'SSH Custom Port'
    ufw allow 15034/tcp comment 'Agent App Port'
    echo "y" | ufw enable || true
    echo "  -> UFW enabled with ports 20022/tcp and 15034/tcp."
else
    echo "  [WARNING] UFW is not installed. Installing ufw..."
    apt-get update -y && apt-get install -y ufw
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow 20022/tcp
    ufw allow 15034/tcp
    echo "y" | ufw enable || true
fi

# ------------------------------------------------------------------------------
# 2. Account & Group Configuration (RBAC & Least Privilege)
# ------------------------------------------------------------------------------
echo ""
echo "[2/5] Creating Groups and Users..."

# Groups
for grp in agent-common agent-core; do
    if ! getent group "$grp" >/dev/null 2>&1; then
        groupadd "$grp"
        echo "  -> Group created: $grp"
    else
        echo "  -> Group already exists: $grp"
    fi
done

# Users:
# agent-admin (member of agent-common, agent-core)
# agent-dev   (member of agent-common, agent-core)
# agent-test  (member of agent-common)
create_user() {
    local username="$1"
    local groups="$2"
    if ! id "$username" >/dev/null 2>&1; then
        useradd -m -s /bin/bash -G "$groups" "$username"
        echo "  -> User created: $username (groups: $groups)"
        # Set default password for convenience (user can change later)
        echo "${username}:${username}1234!" | chpasswd || true
    else
        usermod -a -G "$groups" "$username"
        echo "  -> User updated: $username (groups: $groups)"
    fi
}

create_user "agent-admin" "agent-common,agent-core"
create_user "agent-dev"   "agent-common,agent-core"
create_user "agent-test"  "agent-common"

# ------------------------------------------------------------------------------
# 3. Directory Structure & Permissions Setup
# ------------------------------------------------------------------------------
echo ""
echo "[3/5] Setting up Directory Structure and File Permissions..."

AGENT_HOME="/home/agent-admin/agent-app"
AGENT_LOG_DIR="/var/log/agent-app"

# Ensure parent directory is accessible
chmod 755 /home/agent-admin

# Create directories
mkdir -p "${AGENT_HOME}/upload_files"
mkdir -p "${AGENT_HOME}/api_keys"
mkdir -p "${AGENT_HOME}/bin"
mkdir -p "${AGENT_LOG_DIR}"

# Set permissions according to policy:
# 1) upload_files: group=agent-common, R/W
chown -R agent-admin:agent-common "${AGENT_HOME}/upload_files"
chmod 2775 "${AGENT_HOME}/upload_files"

# 2) api_keys: group=agent-core ONLY, R/W
chown -R agent-admin:agent-core "${AGENT_HOME}/api_keys"
chmod 2770 "${AGENT_HOME}/api_keys"

# 3) /var/log/agent-app: group=agent-core ONLY, R/W
chown -R agent-admin:agent-core "${AGENT_LOG_DIR}"
chmod 2770 "${AGENT_LOG_DIR}"

# 4) Key File Creation
KEY_FILE="${AGENT_HOME}/api_keys/t_secret.key"
echo "agent_api_key_test" > "$KEY_FILE"
chown agent-admin:agent-core "$KEY_FILE"
chmod 660 "$KEY_FILE"
echo "  -> Secret key file created: $KEY_FILE"

# ------------------------------------------------------------------------------
# 4. Copying Scripts and Setting Execution Permissions
# ------------------------------------------------------------------------------
echo ""
echo "[4/5] Deploying Monitoring Scripts..."

SCRIPT_SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/bin"

if [ -d "$SCRIPT_SRC_DIR" ]; then
    cp -f "${SCRIPT_SRC_DIR}/monitor.sh" "${AGENT_HOME}/bin/monitor.sh"
    [ -f "${SCRIPT_SRC_DIR}/report.sh" ] && cp -f "${SCRIPT_SRC_DIR}/report.sh" "${AGENT_HOME}/bin/report.sh"
    [ -f "${SCRIPT_SRC_DIR}/cleanup_archive.sh" ] && cp -f "${SCRIPT_SRC_DIR}/cleanup_archive.sh" "${AGENT_HOME}/bin/cleanup_archive.sh"
else
    echo "  [INFO] Local bin/ directory not found. Please ensure scripts are copied to ${AGENT_HOME}/bin/"
fi

# Set ownership and permissions for monitor.sh:
# Owner: agent-dev, Group: agent-core, Permission: 750 (rwxr-x---)
if [ -f "${AGENT_HOME}/bin/monitor.sh" ]; then
    chown agent-dev:agent-core "${AGENT_HOME}/bin/monitor.sh"
    chmod 750 "${AGENT_HOME}/bin/monitor.sh"
    echo "  -> monitor.sh permissions set to 750 (agent-dev:agent-core)"
fi

# Set permissions for other utility scripts if present
chown -R agent-dev:agent-core "${AGENT_HOME}/bin" 2>/dev/null || true
chmod 750 "${AGENT_HOME}/bin" 2>/dev/null || true

# ------------------------------------------------------------------------------
# 5. Environment Variables & Crontab Setup
# ------------------------------------------------------------------------------
echo ""
echo "[5/5] Configuring Environment Variables and Crontab..."

# Global environment variables profile
ENV_PROFILE="/etc/profile.d/agent_env.sh"
cat << 'EOF' > "$ENV_PROFILE"
export AGENT_HOME=/home/agent-admin/agent-app
export AGENT_PORT=15034
export AGENT_UPLOAD_DIR=$AGENT_HOME/upload_files
export AGENT_KEY_PATH=$AGENT_HOME/api_keys/t_secret.key
export AGENT_LOG_DIR=/var/log/agent-app
export PATH=$PATH:$AGENT_HOME/bin
EOF
chmod 644 "$ENV_PROFILE"
echo "  -> Environment profile created at ${ENV_PROFILE}"

# Append to agent-admin's .bashrc for convenience
if ! grep -q "AGENT_HOME" /home/agent-admin/.bashrc 2>/dev/null; then
    cat "$ENV_PROFILE" >> /home/agent-admin/.bashrc
fi

# Register crontab for agent-admin (Runs every minute)
CRON_JOB="* * * * * /home/agent-admin/agent-app/bin/monitor.sh > /dev/null 2>&1"
CURRENT_CRON=$(crontab -u agent-admin -l 2>/dev/null || true)
if ! echo "$CURRENT_CRON" | grep -Fq "/home/agent-admin/agent-app/bin/monitor.sh"; then
    (echo "$CURRENT_CRON"; echo "$CRON_JOB") | crontab -u agent-admin -
    echo "  -> Crontab registered for agent-admin (Every minute)."
else
    echo "  -> Crontab already registered for agent-admin."
fi

# App Binary copy helper (Deploy from bin/)
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARCH=$(uname -m)
SRC_BINARY=""

if [ "$ARCH" = "x86_64" ] && [ -f "${REPO_ROOT}/bin/agent-app-linux-x86" ]; then
    SRC_BINARY="${REPO_ROOT}/bin/agent-app-linux-x86"
elif [ "$ARCH" = "aarch64" ] && [ -f "${REPO_ROOT}/bin/agent-app-linux-arm64" ]; then
    SRC_BINARY="${REPO_ROOT}/bin/agent-app-linux-arm64"
fi

if [ -n "$SRC_BINARY" ]; then
    # Deploy executable to AGENT_HOME
    cp -f "$SRC_BINARY" "${AGENT_HOME}/agent-app"
    chmod 755 "${AGENT_HOME}/agent-app"
    chown agent-admin:agent-core "${AGENT_HOME}/agent-app"
    
    # Also create a symlink in AGENT_HOME/bin for PATH convenience
    ln -sf "${AGENT_HOME}/agent-app" "${AGENT_HOME}/bin/agent-app"
    echo "  -> Deployed agent-app binary (${ARCH}) from ${SRC_BINARY} to ${AGENT_HOME}/agent-app"
else
    echo "  [WARNING] Target binary for architecture (${ARCH}) not found in ${REPO_ROOT}/bin/!"
fi

echo ""
echo "======================================================================"
echo " Setup Completed Successfully!"
echo "======================================================================"
echo "Next Steps to verify:"
echo " 1. Switch to user: su - agent-admin"
echo " 2. Run the agent app: ./agent-app"
echo " 3. Verify in another terminal: /home/agent-admin/agent-app/bin/monitor.sh"
echo " 4. Check monitor log: tail -f /var/log/agent-app/monitor.log"
echo "======================================================================"

