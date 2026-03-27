# rsyslog TLS Syslog Server — Full Configuration Summary

**syslog.prcomputing.co.uk** — LinuxConnecter (10.0.0.19) — Generated 20 March 2026

## Contents

1. [Architecture & Data Flow](#1-architecture--data-flow)
2. [Prerequisites & Installed Packages](#2-prerequisites--installed-packages)
3. [rsyslog.conf Configuration](#3-rsyslogconf-configuration)
4. [Certificate Configuration](#4-certificate-configuration)
5. [Certificate Generation Commands](#5-certificate-generation-commands)
6. [Drop-in Configuration Files (/etc/rsyslog.d/)](#6-drop-in-configuration-files-etcrsyslogd)
7. [Azure Monitor Agent (AMA) Configuration](#7-azure-monitor-agent-ama-configuration)
8. [Sentinel Data Collection Rule (DCR)](#8-sentinel-data-collection-rule-dcr)
9. [Files Required on Each Host](#9-files-required-on-each-host)
10. [Network & Firewall](#10-network--firewall)
11. [Verification Commands](#11-verification-commands--evidence)
12. [Maintenance & Renewal](#12-maintenance--renewal)
13. [Security Notes](#13-security-notes)
14. [Troubleshooting](#14-troubleshooting)

---

## 1. Architecture & Data Flow

| Component | Hostname | IP | Role |
|-----------|----------|-----|------|
| Syslog Server | LinuxConnecter | `10.0.0.19` | Receives logs over TLS, forwards to Sentinel via AMA |
| Firewall (Sender) | SyslogLogger | `10.0.0.20` | Forwards syslog over TLS to the server |

### End-to-End Data Flow

```
Firewall (10.0.0.20) —TLS:6514→ rsyslog —TCP:28330→ AMA (mdsd) —HTTPS→ Log Analytics → Sentinel
```

### Listening Ports on the Server

| Port | Protocol | Process | Purpose |
|------|----------|---------|---------|
| `6514` | TCP (TLS) | rsyslogd | Receive syslog from remote clients over TLS |
| `28330` | TCP (localhost) | mdsd (AMA) | Receive syslog from rsyslog for upload to Azure |

---

## 2. Prerequisites & Installed Packages

### Operating System

| Property | Value |
|----------|-------|
| Distribution | Ubuntu 24.04.4 LTS (Noble Numbat) |
| Kernel | 6.17.0-1008-azure |
| Platform | Azure VM |

### Packages Installed

| Package | Version | Purpose | Install Command |
|---------|---------|---------|-----------------|
| `rsyslog` | 8.2312.0 | Core syslog daemon | Pre-installed on Ubuntu |
| `rsyslog-gnutls` | 8.2312.0 | TLS support for rsyslog via GnuTLS | `sudo apt install rsyslog-gnutls` |
| `gnutls-bin` | 3.8.3 | GnuTLS CLI tools (`certtool`) for certificate generation | `sudo apt install gnutls-bin` |
| `libgnutls30t64` | 3.8.3 | GnuTLS runtime library | Installed as dependency |
| Azure Monitor Agent | 1.40.3 (mdsd) | Forwards syslog to Log Analytics / Sentinel | Installed via Azure portal (VM extension) |

### Directories Created

| Directory | Owner | Permissions | Purpose |
|-----------|-------|-------------|---------|
| `/etc/rsyslog.d/keys/` | root:root | 755 | TLS certificates and private keys |
| `/etc/rsyslog.d/keys/backup/` | root:root | 755 | Backup of original certificates |
| `/var/spool/rsyslog/` | syslog:syslog | 700 | Disk-assisted queue spool directory for rsyslog |

---

## 3. rsyslog.conf Configuration

**Location:** `/etc/rsyslog.conf` | **Working copy:** `/home/paul/rsyslog.conf`

### Complete Configuration File

```
#####################################################
# rsyslog TLS-Only Configuration for Ubuntu
# Encrypts all syslog traffic, blocks UDP and plain TCP
#####################################################

# Load required modules
module(load="imuxsock")   # local system logging
module(load="imklog" permitnonkernelfacility="on")     # kernel logging

# Set work directory for disk-assisted queues
$WorkDirectory /var/spool/rsyslog

# ---------------------------------------------------
# TLS Stream Driver Configuration (GnuTLS)
# ---------------------------------------------------
global(
    defaultNetstreamDriver="gtls"                                          # Use GnuTLS for all TLS connections
    defaultNetstreamDriverCAFile="/etc/rsyslog.d/keys/ca.pem"              # CA certificate for verifying clients
    defaultNetstreamDriverCertFile="/etc/rsyslog.d/keys/server-cert.pem"   # Server certificate for TLS
    defaultNetstreamDriverKeyFile="/etc/rsyslog.d/keys/server-key.pem"     # Server private key for TLS
    # defaultNetstreamDriverCRLFile="/etc/rsyslog.d/keys/crl.pem"          # CRL for revoking client certificates (uncomment when needed)
)

# ---------------------------------------------------
# INPUT: TLS-encrypted TCP only (port 6514)
# ---------------------------------------------------
# NOTE: Do NOT load imudp — UDP is intentionally blocked.
# NOTE: Do NOT load imtcp without TLS — plain TCP is blocked.

module(
    load="imtcp"                        # Load TCP input module for TLS
    streamDriver.name="gtls"            # Use GnuTLS for this input
    streamDriver.mode="1"               # TLS-only mode (no fallback to plain TCP). 1 = TLS-only, 0 = allow fallback to plain TCP
    streamDriver.authMode="x509/name"   # Authenticate clients by their certificate name
    permittedPeer=["syslog.prcomputing.co.uk"]  # Only allow clients with certificates matching this name
)

input(
    name="tls-input"            # Name for this input
    type="imtcp"                # Listen for TLS-encrypted syslog messages on TCP
    port="6514"                 # Standard port for syslog over TLS
    keepAlive="on"              # Enable TCP keep-alive on connections
    keepAlive.time="60"         # Seconds before first keep-alive probe
    keepAlive.interval="10"     # Seconds between keep-alive probes
    keepAlive.probes="3"        # Number of failed probes before dropping connection
)

# NOTE: Local logging rules (auth, syslog, kern, mail, emerg) are handled by
# /etc/rsyslog.d/50-default.conf to avoid duplication. Do not add them here.

# ---------------------------------------------------
# Include additional configuration files
# ---------------------------------------------------
$IncludeConfig /etc/rsyslog.d/*.conf
```

### Modules Loaded

| Module | Purpose | Notes |
|--------|---------|-------|
| `imuxsock` | Local system logging via Unix socket | Standard — receives logs from local processes |
| `imklog` | Kernel logging | `permitnonkernelfacility="on"` |
| `imtcp` | TCP input with TLS | Configured for TLS-only mode via GnuTLS |

> **Intentionally NOT loaded:** `imudp` (UDP blocked) and plain `imtcp` without TLS (plain TCP blocked).

### Work Directory

| Directive | Value | Purpose |
|-----------|-------|---------|
| `$WorkDirectory` | `/var/spool/rsyslog` | Required for disk-assisted queues (used by AMA forwarder) |

### TLS Global Settings

| Directive | Value | Purpose |
|-----------|-------|---------|
| `defaultNetstreamDriver` | `gtls` | Use GnuTLS for all TLS connections |
| `defaultNetstreamDriverCAFile` | `/etc/rsyslog.d/keys/ca.pem` | CA certificate for verifying client certs |
| `defaultNetstreamDriverCertFile` | `/etc/rsyslog.d/keys/server-cert.pem` | Server certificate presented during TLS handshake |
| `defaultNetstreamDriverKeyFile` | `/etc/rsyslog.d/keys/server-key.pem` | Server private key for TLS |
| `defaultNetstreamDriverCRLFile` | `/etc/rsyslog.d/keys/crl.pem` | CRL for revocation (commented out, for future use) |

### Input Module — TLS Configuration

| Setting | Value | Meaning |
|---------|-------|---------|
| `streamDriver.name` | `gtls` | Use GnuTLS for this input |
| `streamDriver.mode` | `1` | TLS-only — plain TCP is rejected |
| `streamDriver.authMode` | `x509/name` | Mutual TLS — verify client certificate CN |
| `permittedPeer` | `syslog.prcomputing.co.uk` | Only accept clients with this certificate CN |

### Input Listener

| Setting | Value | Purpose |
|---------|-------|---------|
| `name` | `tls-input` | Identifier for this input |
| `type` | `imtcp` | TCP input type |
| `port` | `6514` | Standard syslog-TLS port (RFC 5425) |
| `keepAlive` | `on` | Enable TCP keep-alive |
| `keepAlive.time` | `60` | Seconds before first keep-alive probe |
| `keepAlive.interval` | `10` | Seconds between keep-alive probes |
| `keepAlive.probes` | `3` | Failed probes before dropping connection |

### Local Logging Rules

Handled by `/etc/rsyslog.d/50-default.conf` (not duplicated in rsyslog.conf):

| Selector | Destination | Write Mode |
|----------|-------------|------------|
| `auth,authpriv.*` | `/var/log/auth.log` | Synchronous |
| `*.*;auth,authpriv.none` | `/var/log/syslog` | Asynchronous |
| `kern.*` | `/var/log/kern.log` | Asynchronous |
| `mail.*` | `/var/log/mail.log` | Asynchronous |
| `mail.err` | `/var/log/mail.err` | Synchronous |
| `*.emerg` | `:omusrmsg:*` | Broadcast |

### Configuration Processing Order

| Order | File | What It Does |
|-------|------|-------------|
| 1 | `/etc/rsyslog.conf` | Modules, TLS global config, TLS input listener |
| 2 | `/etc/rsyslog.d/10-azuremonitoragent-omfwd.conf` | Forward all messages to AMA on localhost:28330 |
| 3 | `/etc/rsyslog.d/20-ufw.conf` | UFW firewall logging |
| 4 | `/etc/rsyslog.d/21-cloudinit.conf` | Cloud-init logging |
| 5 | `/etc/rsyslog.d/50-default.conf` | Local logging rules (auth, syslog, kern, mail, emerg) |

---

## 4. Certificate Configuration

**Common Name:** `syslog.prcomputing.co.uk` | **Key Size:** 3072-bit RSA | **Signature:** RSA-SHA256

**Location:** `/etc/rsyslog.d/keys/` | **Backups:** `/etc/rsyslog.d/keys/backup/`

### Certificate Authority (CA)

| Property | Value |
|----------|-------|
| Certificate | `/etc/rsyslog.d/keys/ca.pem` |
| Private key | `/etc/rsyslog.d/keys/ca-key.pem` |
| Template | `/etc/rsyslog.d/keys/ca-template.cfg` |
| Subject | `CN=syslog.prcomputing.co.uk, O=prcomputing.co.uk, C=GB` |
| Basic Constraints | `CA: TRUE` |
| Key Usage | Certificate signing |
| Validity | 10 years (2026-03-20 to 2036-03-17) |
| Permissions | `ca-key.pem`: **400** / `ca.pem`: 644 |

### Server Certificate

| Property | Value |
|----------|-------|
| Certificate | `/etc/rsyslog.d/keys/server-cert.pem` |
| Private key | `/etc/rsyslog.d/keys/server-key.pem` |
| Template | `/etc/rsyslog.d/keys/server-template.cfg` |
| Subject | `CN=syslog.prcomputing.co.uk, O=prcomputing.co.uk, C=GB` |
| SAN | `DNSname: syslog.prcomputing.co.uk` |
| Extended Key Usage | TLS WWW Server |
| Key Usage | Digital signature, Key encipherment |
| Validity | 1 year (2026-03-20 to 2027-03-20) |
| Permissions | `server-key.pem`: **600** / `server-cert.pem`: 644 |

### Client Certificate (for the firewall)

| Property | Value |
|----------|-------|
| Certificate | `/etc/rsyslog.d/keys/client-cert.pem` |
| Private key | `/etc/rsyslog.d/keys/client-key.pem` |
| Template | `/etc/rsyslog.d/keys/client-template.cfg` |
| Subject | `CN=syslog.prcomputing.co.uk, O=prcomputing.co.uk, C=GB` |
| SAN | `DNSname: syslog.prcomputing.co.uk` |
| Extended Key Usage | TLS WWW Client |
| Key Usage | Digital signature, Key encipherment |
| Validity | 1 year (2026-03-20 to 2027-03-20) |
| Permissions | `client-key.pem`: **600** / `client-cert.pem`: 644 |

### All Files in /etc/rsyslog.d/keys/

| File | Type | Permissions | Used By |
|------|------|-------------|---------|
| `ca.pem` | CA certificate | 644 | Server & Client |
| `ca-key.pem` | CA private key | **400** | Certificate signing only |
| `ca-template.cfg` | certtool template | 644 | CA generation |
| `server-cert.pem` | Server certificate | 644 | rsyslog server |
| `server-key.pem` | Server private key | **600** | rsyslog server |
| `server-template.cfg` | certtool template | 644 | Server cert generation |
| `client-cert.pem` | Client certificate | 644 | Firewall |
| `client-key.pem` | Client private key | **600** | Firewall |
| `client-template.cfg` | certtool template | 644 | Client cert generation |
| `request.pem` | Legacy CSR | 600 | Not used (from initial setup) |

---

## 5. Certificate Generation Commands

All commands use `certtool` from the `gnutls-bin` package. Run from `/etc/rsyslog.d/keys/`.

### Step 1: Generate CA

```bash
certtool --generate-privkey --outfile ca-key.pem --bits 3072
certtool --generate-self-signed --load-privkey ca-key.pem \
  --template ca-template.cfg --outfile ca.pem
```

**ca-template.cfg:**

```
cn = "syslog.prcomputing.co.uk"
organization = "prcomputing.co.uk"
country = GB
ca
cert_signing_key
expiration_days = 3650
```

### Step 2: Generate Server Certificate

```bash
certtool --generate-privkey --outfile server-key.pem --bits 3072
certtool --generate-certificate --load-privkey server-key.pem \
  --load-ca-certificate ca.pem --load-ca-privkey ca-key.pem \
  --template server-template.cfg --outfile server-cert.pem
```

**server-template.cfg:**

```
cn = "syslog.prcomputing.co.uk"
organization = "prcomputing.co.uk"
country = GB
tls_www_server
encryption_key
signing_key
expiration_days = 365
dns_name = "syslog.prcomputing.co.uk"
```

### Step 3: Generate Client Certificate

```bash
certtool --generate-privkey --outfile client-key.pem --bits 3072
certtool --generate-certificate --load-privkey client-key.pem \
  --load-ca-certificate ca.pem --load-ca-privkey ca-key.pem \
  --template client-template.cfg --outfile client-cert.pem
```

**client-template.cfg:**

```
cn = "syslog.prcomputing.co.uk"
organization = "prcomputing.co.uk"
country = GB
tls_www_client
encryption_key
signing_key
expiration_days = 365
dns_name = "syslog.prcomputing.co.uk"
```

### Step 4: Set Permissions

```bash
sudo chmod 400 ca-key.pem
sudo chmod 600 server-key.pem client-key.pem
```

### Step 5: Verify Certificates

```bash
certtool --verify --load-ca-certificate ca.pem --infile server-cert.pem
certtool --verify --load-ca-certificate ca.pem --infile client-cert.pem
```

### Step 6: Copy Client Files to Firewall

```bash
sudo scp ca.pem client-cert.pem client-key.pem azureuser@10.0.0.20:/home/azureuser
```

---

## 6. Drop-in Configuration Files (/etc/rsyslog.d/)

| File | Purpose | Managed By |
|------|---------|------------|
| `10-azuremonitoragent-omfwd.conf` | Forward all syslog to AMA daemon on localhost:28330 | AMA (auto-generated) |
| `20-ufw.conf` | UFW firewall logging | Ubuntu/UFW |
| `21-cloudinit.conf` | Cloud-init logging | Ubuntu/cloud-init |
| `50-default.conf` | Local file logging rules (auth, syslog, kern, mail, emerg) | Ubuntu (standard) |

---

## 7. Azure Monitor Agent (AMA) Configuration

### Installation

AMA was installed as an Azure VM extension via the Azure portal (Sentinel → Data connectors → Syslog via AMA).

| Property | Value |
|----------|-------|
| Agent daemon | `mdsd` version 1.40.3 |
| Install location | `/opt/microsoft/azuremonitoragent/` |
| Config cache | `/etc/opt/microsoft/azuremonitoragent/config-cache/` |
| Logs | `/var/opt/microsoft/azuremonitoragent/log/` |

### AMA Services

| Service | Status | Purpose |
|---------|--------|---------|
| `azuremonitoragent.service` | Active | Main AMA daemon |
| `azuremonitor-coreagent.service` | Active | Core agent (mdsd — processes and uploads data) |
| `azuremonitor-agentlauncher.service` | Active | Agent launcher / watchdog |
| `azuremonitor-astextension.service` | Active | AST extension daemon |

### AMA rsyslog Forwarder Config

**File:** `/etc/rsyslog.d/10-azuremonitoragent-omfwd.conf` (auto-generated by AMA)

| Setting | Value | Purpose |
|---------|-------|---------|
| Selector | `*.*` | Forward ALL messages to AMA |
| Target | `127.0.0.1` | Localhost (AMA daemon) |
| Port | `28330` | AMA listening port |
| Protocol | `tcp` | Reliable delivery |
| Queue type | `LinkedList` (disk-assisted) | Buffered with disk spillover |
| Queue max disk | `1g` | Max 1 GB disk queue |
| Queue size | `25000` messages | In-memory queue capacity |
| Worker threads | `100` (max) | Scales down to 0 when idle |
| Save on shutdown | `on` | Persist queued messages across restarts |
| Resume retry | `-1` (infinite) | Never stop retrying |

---

## 8. Sentinel Data Collection Rule (DCR)

| Property | Value |
|----------|-------|
| DCR ID | `dcr-316dd192dc1e4754bdab4a160aacbf80` |
| Subscription | `72cf9259-8010-4b21-9791-423900f34e25` |
| Resource Group | `ulrobinson.com` |
| VM | `LinuxConnecter` |
| Region | `uksouth` |
| Destination stream | `LINUX_SYSLOGS_BLOB` |
| Solution | `LogManagement` |
| Log Analytics endpoint | `da6958c9-d107-4636-a787-e88028f3c7ff.ods.opinsights.azure.com` |

### Facilities Collected

| Facility | Typical Source |
|----------|---------------|
| `auth` | Authentication events (login, SSH) |
| `authpriv` | Private auth (sudo, PAM) |
| `daemon` | System daemons |
| `kern` | Kernel messages |
| `local0` – `local7` | Custom / Firewall logs |
| `syslog` | Syslog internal messages |
| `user` | User-level messages |

### Log Levels Collected (all)

`Debug`, `Info`, `Notice`, `Warning`, `Error`, `Critical`, `Alert`, `Emergency`

### KQL Query to Verify in Sentinel

```kql
Syslog
| where Computer == "SyslogLogger"
| where SyslogMessage contains "TLS syslog test from SyslogLogger"
| project TimeGenerated, Computer, Facility, SeverityLevel, SyslogMessage
| order by TimeGenerated desc
```

---

## 9. Files Required on Each Host

### Syslog Server (10.0.0.19)

| File | Path |
|------|------|
| `ca.pem` | `/etc/rsyslog.d/keys/ca.pem` |
| `server-cert.pem` | `/etc/rsyslog.d/keys/server-cert.pem` |
| `server-key.pem` | `/etc/rsyslog.d/keys/server-key.pem` |
| `ca-key.pem` | `/etc/rsyslog.d/keys/ca-key.pem` |

> **Note:** `ca-key.pem` is only needed for signing new certificates. Keep it secure.

### Firewall / Sender (10.0.0.20)

| File | Purpose |
|------|---------|
| `ca.pem` | Verify server identity |
| `client-cert.pem` | Present to server for mTLS |
| `client-key.pem` | Client private key |

---

## 10. Network & Firewall

| Layer | Status | Notes |
|-------|--------|-------|
| UFW (host firewall) | Inactive | Not enabled — consider enabling for defence in depth |
| Azure NSG | Must allow inbound | TCP port 6514 from 10.0.0.20 to 10.0.0.19 |

**Recommended UFW configuration (if enabling):**

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw allow from 10.0.0.20 to any port 6514 proto tcp
sudo ufw enable
```

---

## 11. Verification Commands & Evidence

The following checks provide end-to-end proof that syslog messages are being received over TLS, from the firewall through to Sentinel.

### 1. Verify Messages Are Being Received

**Source:** `/var/log/syslog`

All messages from the remote firewall are written here. Messages from the firewall show hostname `SyslogLogger`, while local server messages show `LinuxConnecter`.

```bash
# Show recent messages from the firewall
sudo grep "SyslogLogger" /var/log/syslog | tail -20

# Count messages in the last 2 minutes
now=$(date -u +%Y-%m-%dT%H:%M)
two_min_ago=$(date -u -d '2 minutes ago' +%Y-%m-%dT%H:%M)
sudo grep "SyslogLogger" /var/log/syslog | awk -v start="$two_min_ago" -v end="$now" '$0 >= start && $0 <= end' | wc -l
```

**What it proves:** Messages from the firewall are being received and stored on this server.

### 2. Verify rsyslog Service is Healthy

**Source:** `journalctl -u rsyslog`

The systemd journal shows startup messages, TLS errors, and connection events. A clean startup with no errors confirms the TLS configuration is valid.

```bash
sudo systemctl status rsyslog
sudo journalctl -u rsyslog --since "$(systemctl show rsyslog --property=ActiveEnterTimestamp --value)" --no-pager
```

**What it proves:** rsyslog is running with a valid TLS configuration and no errors.

### 3. Verify Active TLS Connection from Firewall

**Source:** `ss -tnp`

Shows live TCP connections on port 6514. An ESTABLISHED connection from 10.0.0.20 confirms the firewall has an active TLS session.

```bash
sudo ss -tnp | grep 6514
```

Expected output:

```
ESTAB  10.0.0.19:6514  10.0.0.20:xxxxx  rsyslogd
```

**What it proves:** There is a live TCP connection from the firewall to the TLS syslog port.

### 4. Verify rsyslog is Listening on Port 6514

**Source:** `ss -tlnp`

```bash
sudo ss -tlnp | grep 6514
```

**What it proves:** The server is accepting connections on the correct TLS port.

### 5. Verify TLS is Mandatory (Configuration Evidence)

**Source:** `/etc/rsyslog.conf`

```bash
grep -n "streamDriver.mode\|streamDriver.authMode\|permittedPeer\|imudp\|imtcp" /etc/rsyslog.conf
```

| Setting | Value | Significance |
|---------|-------|-------------|
| `streamDriver.mode="1"` | TLS-only | Plain TCP is rejected — no fallback |
| `streamDriver.authMode="x509/name"` | Mutual TLS | Client must present a valid certificate |
| `permittedPeer` | syslog.prcomputing.co.uk | Only this certificate CN is accepted |
| No `imudp` loaded | — | UDP is completely blocked |

**What it proves:** There is no path for an unencrypted syslog message to reach this server.

### 6. Verify Certificate Chain

**Source:** `/etc/rsyslog.d/keys/`

```bash
certtool --verify --load-ca-certificate /etc/rsyslog.d/keys/ca.pem --infile /etc/rsyslog.d/keys/server-cert.pem
certtool --verify --load-ca-certificate /etc/rsyslog.d/keys/ca.pem --infile /etc/rsyslog.d/keys/client-cert.pem
```

Expected output for both: `Chain verification output: Verified. The certificate is trusted.`

**What it proves:** The TLS certificates are valid, properly signed, and form a trusted chain.

### 7. Check Certificate Expiry Dates

```bash
for f in ca.pem server-cert.pem client-cert.pem; do
  echo "=== $f ==="
  certtool --certificate-info --infile /etc/rsyslog.d/keys/$f | grep "Not After:"
done
```

**What it proves:** Certificates are within their validity period.

### 8. Verify Kernel-Level TCP Connection

**Source:** `/proc/net/tcp`

The raw kernel TCP connection table confirms established connections on port 6514 (hex `1972`) at the OS kernel level, independent of any userspace tool.

```bash
grep "1972" /proc/net/tcp
```

**What it proves:** At the OS kernel level, there is an established TCP session on the TLS port.

### 9. Verify rsyslog → AMA Forwarding Connection

**Source:** `ss -tnp`

Confirms rsyslog has an active TCP connection to the Azure Monitor Agent daemon on localhost port 28330.

```bash
sudo ss -tnp | grep 28330
```

Expected output:

```
ESTAB  rsyslogd:xxxxx  ->  mdsd:28330
```

**What it proves:** rsyslog is forwarding messages to AMA for delivery to Sentinel.

### 10. Verify AMA Services are Running

```bash
systemctl is-active azuremonitoragent.service azuremonitor-coreagent.service azuremonitor-agentlauncher.service
```

**What it proves:** All AMA services are active and processing data.

### 11. Verify AMA Data Collection Rule (DCR)

**Source:** `/etc/opt/microsoft/azuremonitoragent/config-cache/configchunks/*.json`

```bash
sudo find /etc/opt/microsoft/azuremonitoragent/config-cache/configchunks/ \
  -name "*.json" -exec cat {} \; | python3 -m json.tool
```

**What it proves:** AMA is configured to collect the correct syslog facilities from this server.

### 12. Verify AMA is Uploading to Azure

**Source:** `/var/opt/microsoft/azuremonitoragent/log/mdsd.info`

```bash
sudo tail -20 /var/opt/microsoft/azuremonitoragent/log/mdsd.info
sudo tail -20 /var/opt/microsoft/azuremonitoragent/log/mdsd.err
```

**What it proves:** AMA is running, authenticated to Azure, and actively uploading data.

### 13. Verify Data in Sentinel (KQL)

Run in your Log Analytics workspace to confirm end-to-end delivery:

```kql
Syslog
| where Computer == "SyslogLogger"
| where TimeGenerated > ago(30m)
| project TimeGenerated, Computer, Facility, SeverityLevel, SyslogMessage
| order by TimeGenerated desc
```

**What it proves:** Messages have been received, processed, and are queryable in Microsoft Sentinel.

### Evidence Summary

| Check | Source | Proves |
|-------|--------|--------|
| Messages from firewall in syslog | `/var/log/syslog` | Messages are received |
| No rsyslog errors | `journalctl -u rsyslog` | TLS config is valid |
| Active connection on port 6514 | `ss -tnp` | Firewall is connected |
| Listening on port 6514 | `ss -tlnp` | Server accepting connections |
| `streamDriver.mode="1"` | `/etc/rsyslog.conf` | TLS is mandatory |
| `x509/name` auth mode | `/etc/rsyslog.conf` | Mutual cert auth enforced |
| No UDP/plain TCP listeners | `/etc/rsyslog.conf` | No unencrypted path exists |
| Certificates verified | `certtool --verify` | Valid certificate chain |
| Kernel TCP table | `/proc/net/tcp` | OS-level connection proof |
| rsyslog connected to AMA | `ss -tnp` port 28330 | Forwarding to Sentinel pipeline |
| AMA services active | `systemctl` | Agent is running |
| DCR has correct facilities | AMA config cache | Collecting right data |
| AMA uploading | `mdsd.info` heartbeat | Data reaching Azure |
| Data in Sentinel | KQL query | End-to-end delivery confirmed |

---

## 12. Maintenance & Renewal

### Certificate Expiry Dates

| Certificate | Expires | Action Required |
|-------------|---------|-----------------|
| CA | 2036-03-17 (10 years) | No action needed for years |
| Server cert | **2027-03-20** (1 year) | Regenerate before expiry, restart rsyslog |
| Client cert | **2027-03-20** (1 year) | Regenerate before expiry, copy to firewall |

### Renewal Process

1. Generate new server key and cert using the existing CA
2. Generate new client key and cert using the existing CA
3. Set permissions on new key files
4. Restart rsyslog: `sudo systemctl restart rsyslog`
5. Copy new client files to firewall
6. Restart rsyslog on firewall

### After Any Configuration Change

```bash
sudo cp /home/paul/rsyslog.conf /etc/rsyslog.conf
sudo systemctl restart rsyslog
sudo journalctl -u rsyslog --since "$(systemctl show rsyslog --property=ActiveEnterTimestamp --value)" --no-pager
```

---

## 13. Security Notes

- **Encryption:** UDP and plain TCP are intentionally disabled. Only TLS on port 6514 is accepted.
- **Mutual TLS:** Both server and client authenticate via x509 certificates (`x509/name` auth mode).
- **CRL:** CRL checking is pre-configured in rsyslog.conf but commented out. Uncomment and generate a CRL file when needed.
- **Backups:** Original certificates from initial setup are backed up at `/etc/rsyslog.d/keys/backup/`.
- **⚠️ Stray files:** There are old `ca-key.pem` and `ca.pem` files in `/etc/rsyslog.d/` (outside the keys directory) with insecure permissions (setuid/setgid). These should be removed: `sudo rm /etc/rsyslog.d/ca-key.pem /etc/rsyslog.d/ca.pem`
- **⚠️ UFW:** Host firewall is currently inactive. Azure NSG provides network-level filtering, but enabling UFW adds defence in depth.
- **⚠️ Renewal reminder:** Server and client certificates expire **2027-03-20**. Set a calendar reminder to renew before that date.

---

## 14. Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| GnuTLS error -53 / "Error in the push function" | Server restarted while client had active connection | Wait for auto-reconnect (~1 second) or restart rsyslog on the sender |
| "certificate invalid: signer not found" | Server has old CA, client has new cert (or vice versa) | Ensure matching CA and certs on both sides, restart rsyslog |
| "not permitted to talk to peer" | Client cert CN doesn't match `permittedPeer` | Check cert CN matches `syslog.prcomputing.co.uk` |
| "error creating disk queue" (e/2036) | `$WorkDirectory` missing or wrong permissions | `sudo mkdir -p /var/spool/rsyslog && sudo chown syslog:syslog /var/spool/rsyslog` |
| Duplicate log entries | Same logging rules in rsyslog.conf and 50-default.conf | Keep rules in only one place (50-default.conf) |
| AMA not uploading | DCR has wrong facilities/levels | Check DCR config in Azure portal; verify with `mdsd.info` logs |
| No data in Sentinel | AMA not connected or DCR not applied | Restart AMA: `sudo systemctl restart azuremonitoragent` |
| Connection drops from firewall | Server-side rsyslog restart or network issue | Check `keepAlive` settings; sender will auto-reconnect |

---

*rsyslog TLS Configuration — syslog.prcomputing.co.uk — prcomputing.co.uk — 20 March 2026*
