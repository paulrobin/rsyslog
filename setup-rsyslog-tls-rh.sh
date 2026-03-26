#!/bin/bash
#####################################################
# rsyslog TLS Setup Script for Red Hat
# (RHEL, CentOS Stream, Rocky Linux, AlmaLinux)
#
# This script:
#   1. Installs required packages (rsyslog-gnutls, gnutls-utils)
#   2. Creates certificate and spool directories
#   3. Configures SELinux policies for rsyslog TLS
#   4. Opens firewall port 6514
#   5. Deploys the rsyslog.conf.rh configuration
#   6. Validates the setup
#
# Usage:
#   sudo ./setup-rsyslog-tls-rh.sh
#
# Prerequisites:
#   - Run as root or with sudo
#   - rsyslog.conf.rh must be in the same directory as this script
#   - Certificate files (ca.pem, server-cert.pem, server-key.pem) must be
#     in a 'certs/' subfolder alongside this script
#
# Expected folder structure:
#   ./setup-rsyslog-tls-rh.sh
#   ./rsyslog.conf.rh
#   ./certs/ca.pem
#   ./certs/server-cert.pem
#   ./certs/server-key.pem
#
#####################################################

set -e

# ---------------------------------------------------
# Configuration variables
# ---------------------------------------------------
KEYS_DIR="/etc/rsyslog.d/keys"
SPOOL_DIR="/var/spool/rsyslog"
BACKUP_DIR="${KEYS_DIR}/backup"
TLS_PORT="6514"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_SOURCE="${SCRIPT_DIR}/rsyslog.conf.rh"
CONFIG_DEST="/etc/rsyslog.conf"
CERTS_SOURCE="${SCRIPT_DIR}/certs"

# ---------------------------------------------------
# Colours for output
# ---------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No colour

print_step() {
    echo -e "\n${GREEN}[STEP]${NC} $1"
}

print_info() {
    echo -e "${YELLOW}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_ok() {
    echo -e "${GREEN}[OK]${NC} $1"
}

# ---------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------
print_step "Running pre-flight checks..."

# Check running as root
if [[ $EUID -ne 0 ]]; then
    print_error "This script must be run as root (use sudo)"
    exit 1
fi
print_ok "Running as root"

# Check Red Hat-based OS
if [[ ! -f /etc/redhat-release ]]; then
    print_error "This script is designed for Red Hat-based systems (RHEL, CentOS, Rocky, Alma)"
    print_info "Detected OS: $(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d= -f2)"
    exit 1
fi
print_ok "Red Hat-based OS detected: $(cat /etc/redhat-release)"

# Check config file exists
if [[ ! -f "$CONFIG_SOURCE" ]]; then
    print_error "Configuration file not found: $CONFIG_SOURCE"
    print_info "Ensure rsyslog.conf.rh is in the same directory as this script"
    exit 1
fi
print_ok "Configuration file found: $CONFIG_SOURCE"

# Check certificate files exist
CERTS_FOUND=0
CERTS_MISSING=0
for cert_file in ca.pem server-cert.pem server-key.pem; do
    if [[ -f "${CERTS_SOURCE}/${cert_file}" ]]; then
        print_ok "Certificate found: certs/${cert_file}"
        CERTS_FOUND=$((CERTS_FOUND + 1))
    else
        print_error "Certificate missing: certs/${cert_file}"
        CERTS_MISSING=$((CERTS_MISSING + 1))
    fi
done

if [[ $CERTS_MISSING -gt 0 ]]; then
    print_error "${CERTS_MISSING} certificate file(s) missing from ${CERTS_SOURCE}/"
    print_info "Expected folder structure:"
    print_info "  ${SCRIPT_DIR}/"
    print_info "    setup-rsyslog-tls-rh.sh"
    print_info "    rsyslog.conf.rh"
    print_info "    certs/"
    print_info "      ca.pem"
    print_info "      server-cert.pem"
    print_info "      server-key.pem"
    exit 1
fi

# ---------------------------------------------------
# Step 1: Install required packages
# ---------------------------------------------------
print_step "Installing required packages..."

dnf install -y rsyslog rsyslog-gnutls gnutls-utils policycoreutils-python-utils 2>&1 | tail -5

# Verify installations
for pkg in rsyslog rsyslog-gnutls gnutls-utils; do
    if rpm -q "$pkg" &>/dev/null; then
        print_ok "$pkg installed ($(rpm -q "$pkg"))"
    else
        print_error "Failed to install $pkg"
        exit 1
    fi
done

# Verify certtool is available
if command -v certtool &>/dev/null; then
    print_ok "certtool available ($(certtool --version 2>&1 | head -1))"
else
    print_error "certtool not found after installing gnutls-utils"
    exit 1
fi

# ---------------------------------------------------
# Step 2: Create directories
# ---------------------------------------------------
print_step "Creating directories..."

# Certificate directory
if [[ ! -d "$KEYS_DIR" ]]; then
    mkdir -p "$KEYS_DIR"
    chmod 755 "$KEYS_DIR"
    print_ok "Created $KEYS_DIR"
else
    print_info "$KEYS_DIR already exists"
fi

# Backup directory for certificates
if [[ ! -d "$BACKUP_DIR" ]]; then
    mkdir -p "$BACKUP_DIR"
    chmod 755 "$BACKUP_DIR"
    print_ok "Created $BACKUP_DIR"
else
    print_info "$BACKUP_DIR already exists"
fi

# Spool directory for disk-assisted queues
if [[ ! -d "$SPOOL_DIR" ]]; then
    mkdir -p "$SPOOL_DIR"
    print_ok "Created $SPOOL_DIR"
else
    print_info "$SPOOL_DIR already exists"
fi

# ---------------------------------------------------
# Step 3: Configure SELinux
# ---------------------------------------------------
print_step "Configuring SELinux..."

# Check SELinux status
SELINUX_STATUS=$(getenforce 2>/dev/null || echo "Disabled")
print_info "SELinux status: $SELINUX_STATUS"

if [[ "$SELINUX_STATUS" != "Disabled" ]]; then

    # Allow rsyslog to listen on port 6514
    if semanage port -l | grep -q "syslogd_port_t.*tcp.*${TLS_PORT}"; then
        print_info "Port ${TLS_PORT} already allowed for syslogd"
    else
        semanage port -a -t syslogd_port_t -p tcp "$TLS_PORT" 2>/dev/null || \
        semanage port -m -t syslogd_port_t -p tcp "$TLS_PORT" 2>/dev/null
        print_ok "SELinux: allowed port ${TLS_PORT} for syslogd"
    fi

    # Label certificate directory
    semanage fcontext -a -t cert_t "${KEYS_DIR}(/.*)?" 2>/dev/null || \
    semanage fcontext -m -t cert_t "${KEYS_DIR}(/.*)?" 2>/dev/null
    restorecon -Rv "$KEYS_DIR" 2>&1 | head -5
    print_ok "SELinux: labelled $KEYS_DIR as cert_t"

    # Label spool directory
    semanage fcontext -a -t syslogd_var_lib_t "${SPOOL_DIR}(/.*)?" 2>/dev/null || \
    semanage fcontext -m -t syslogd_var_lib_t "${SPOOL_DIR}(/.*)?" 2>/dev/null
    restorecon -Rv "$SPOOL_DIR" 2>&1 | head -5
    print_ok "SELinux: labelled $SPOOL_DIR as syslogd_var_lib_t"

    # Allow AMA port 28330 (if AMA will be installed later)
    if semanage port -l | grep -q "syslogd_port_t.*tcp.*28330"; then
        print_info "Port 28330 already allowed for syslogd (AMA)"
    else
        semanage port -a -t syslogd_port_t -p tcp 28330 2>/dev/null || \
        semanage port -m -t syslogd_port_t -p tcp 28330 2>/dev/null
        print_ok "SELinux: allowed port 28330 for AMA"
    fi

else
    print_info "SELinux is disabled — skipping SELinux configuration"
fi

# ---------------------------------------------------
# Step 4: Configure firewall
# ---------------------------------------------------
print_step "Configuring firewall..."

if systemctl is-active --quiet firewalld; then
    if firewall-cmd --list-ports | grep -q "${TLS_PORT}/tcp"; then
        print_info "Port ${TLS_PORT}/tcp already open in firewalld"
    else
        firewall-cmd --permanent --add-port="${TLS_PORT}/tcp"
        firewall-cmd --reload
        print_ok "Opened port ${TLS_PORT}/tcp in firewalld"
    fi
    print_info "Active firewall ports: $(firewall-cmd --list-ports)"
else
    print_info "firewalld is not running — skipping firewall configuration"
    print_info "Ensure port ${TLS_PORT}/tcp is allowed at the network level (e.g., Azure NSG)"
fi

# ---------------------------------------------------
# Step 5: Backup and deploy rsyslog.conf
# ---------------------------------------------------
print_step "Deploying rsyslog configuration..."

# Backup existing config
if [[ -f "$CONFIG_DEST" ]]; then
    BACKUP_FILE="${CONFIG_DEST}.backup.$(date +%Y%m%d%H%M%S)"
    cp "$CONFIG_DEST" "$BACKUP_FILE"
    print_ok "Backed up existing config to $BACKUP_FILE"
fi

# Deploy new config
cp "$CONFIG_SOURCE" "$CONFIG_DEST"
chmod 644 "$CONFIG_DEST"
print_ok "Deployed $CONFIG_SOURCE to $CONFIG_DEST"

# ---------------------------------------------------
# Step 6: Deploy certificate files
# ---------------------------------------------------
print_step "Deploying certificate files..."

# Backup existing certs if present
if ls ${KEYS_DIR}/*.pem &>/dev/null 2>&1; then
    print_info "Backing up existing certificates to ${BACKUP_DIR}/"
    cp ${KEYS_DIR}/*.pem "$BACKUP_DIR/" 2>/dev/null || true
    print_ok "Existing certificates backed up"
fi

# Copy certificate files
cp "${CERTS_SOURCE}/ca.pem" "${KEYS_DIR}/ca.pem"
cp "${CERTS_SOURCE}/server-cert.pem" "${KEYS_DIR}/server-cert.pem"
cp "${CERTS_SOURCE}/server-key.pem" "${KEYS_DIR}/server-key.pem"
print_ok "Certificate files copied to ${KEYS_DIR}/"

# Set ownership
chown root:root ${KEYS_DIR}/ca.pem ${KEYS_DIR}/server-cert.pem ${KEYS_DIR}/server-key.pem
print_ok "Ownership set to root:root"

# Set permissions
chmod 644 "${KEYS_DIR}/ca.pem"
chmod 644 "${KEYS_DIR}/server-cert.pem"
chmod 600 "${KEYS_DIR}/server-key.pem"
print_ok "Permissions set: ca.pem=644, server-cert.pem=644, server-key.pem=600"

# Restore SELinux labels on new cert files
SELINUX_STATUS=$(getenforce 2>/dev/null || echo "Disabled")
if [[ "$SELINUX_STATUS" != "Disabled" ]]; then
    restorecon -Rv "$KEYS_DIR/" 2>&1 | head -5
    print_ok "SELinux labels restored on certificate files"
fi

# Verify cert files
print_info "Verifying certificate files..."
for cert_file in ca.pem server-cert.pem server-key.pem; do
    if [[ -f "${KEYS_DIR}/${cert_file}" ]]; then
        print_ok "  ${cert_file} deployed ($(stat -c '%a %U:%G' ${KEYS_DIR}/${cert_file}))"
    else
        print_error "  ${cert_file} NOT found in ${KEYS_DIR}/"
    fi
done

# Verify certificate chain
if command -v certtool &>/dev/null; then
    if certtool --verify --load-ca-certificate "${KEYS_DIR}/ca.pem" --infile "${KEYS_DIR}/server-cert.pem" 2>&1 | grep -q "Verified"; then
        print_ok "Server certificate verified against CA chain"
    else
        print_error "Server certificate verification FAILED against CA chain"
        print_info "Check that ca.pem contains the correct CA chain (issuing CA first, root CA last)"
    fi
fi

# ---------------------------------------------------
# Step 7: Validate configuration
# ---------------------------------------------------
print_step "Validating rsyslog configuration..."

# Check rsyslog config syntax
if rsyslogd -N 1 2>&1 | grep -q "rsyslogd: version"; then
    print_ok "rsyslog configuration syntax is valid"
else
    print_error "rsyslog configuration has errors:"
    rsyslogd -N 1 2>&1
    print_info "Fix the errors above, then restart rsyslog manually"
fi

# ---------------------------------------------------
# Summary
# ---------------------------------------------------
print_step "Setup complete!"

echo ""
echo "============================================="
echo "  rsyslog TLS Setup Summary"
echo "============================================="
echo ""
echo "  Packages installed:"
echo "    - rsyslog $(rpm -q rsyslog --qf '%{VERSION}')"
echo "    - rsyslog-gnutls $(rpm -q rsyslog-gnutls --qf '%{VERSION}')"
echo "    - gnutls-utils $(rpm -q gnutls-utils --qf '%{VERSION}')"
echo ""
echo "  Directories created:"
echo "    - ${KEYS_DIR}           (certificates)"
echo "    - ${BACKUP_DIR}      (certificate backups)"
echo "    - ${SPOOL_DIR}       (queue spool)"
echo ""
echo "  SELinux: ${SELINUX_STATUS}"
if [[ "$SELINUX_STATUS" != "Disabled" ]]; then
echo "    - Port ${TLS_PORT}/tcp allowed for syslogd"
echo "    - Port 28330/tcp allowed for AMA"
echo "    - ${KEYS_DIR} labelled as cert_t"
echo "    - ${SPOOL_DIR} labelled as syslogd_var_lib_t"
fi
echo ""
echo "  Firewall:"
if systemctl is-active --quiet firewalld; then
echo "    - Port ${TLS_PORT}/tcp open"
else
echo "    - firewalld not active"
fi
echo ""
echo "  Certificates:"
echo "    - ${KEYS_DIR}/ca.pem           ($(stat -c '%a' ${KEYS_DIR}/ca.pem 2>/dev/null || echo 'missing'))"
echo "    - ${KEYS_DIR}/server-cert.pem  ($(stat -c '%a' ${KEYS_DIR}/server-cert.pem 2>/dev/null || echo 'missing'))"
echo "    - ${KEYS_DIR}/server-key.pem   ($(stat -c '%a' ${KEYS_DIR}/server-key.pem 2>/dev/null || echo 'missing'))"
echo ""
echo "  Configuration:"
echo "    - Deployed to ${CONFIG_DEST}"
echo "    - Original backed up to ${BACKUP_FILE:-N/A}"
echo ""
echo "============================================="
echo "  NEXT STEPS"
echo "============================================="
echo ""
echo "  1. Restart rsyslog:"
echo "     systemctl restart rsyslog"
echo ""
echo "  2. Verify with:"
echo "     systemctl status rsyslog"
echo "     journalctl -u rsyslog --no-pager -n 20"
echo "     ss -tlnp | grep ${TLS_PORT}"
echo ""
echo "============================================="