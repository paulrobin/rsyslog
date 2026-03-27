# rsyslog High Volume Log Ingestion — Disk & Rotation Advisory

This document outlines concerns, options, and recommendations for operating an rsyslog TLS server receiving approximately 1TB of syslog data per day.

## Current Server State

| Item | Current Value | Concern |
|------|--------------|---------|
| /var partition size | 8 GB | Will fill in minutes at 1TB/day |
| /var available space | 6.4 GB | Insufficient for any meaningful retention |
| Log rotation frequency | Weekly | Far too infrequent for high volume |
| Rotated logs kept | 4 (weeks) | Would require 4+ TB uncompressed |
| Compression | Disabled | Wastes approximately 90% of disk space |
| Max file size trigger | None | No protection against individual files growing too large |

> **⚠️ Critical:** At 1TB/day ingestion, the current 8GB /var partition will fill completely within minutes, causing rsyslog to stop writing and potentially drop incoming messages. This must be addressed before going live.

## Concern 1 — Disk Space

The `/var` filesystem is an LVM logical volume with only 8GB allocated. All syslog files (`/var/log/messages`, `/var/log/secure`, etc.) write to this partition. At 1TB/day, the disk will fill almost immediately regardless of how aggressively logs are rotated.

Even with compression (approximately 10:1 ratio for syslog text), retaining a single day of compressed logs would require around 100GB — far more than the 8GB available.

## Concern 2 — Log Rotation

The current logrotate configuration in `/etc/logrotate.d/rsyslog` uses global defaults:

```
/var/log/messages
/var/log/secure
/var/log/cron
/var/log/maillog
/var/log/spooler
{
    missingok
    sharedscripts
    postrotate
        /usr/bin/systemctl -s HUP kill rsyslog.service >/dev/null 2>&1 || true
    endscript
}
```

This inherits the global settings: weekly rotation, 4 copies kept, no compression, no size limit. For a high-volume server this provides no protection against disk exhaustion.

## Options

### Option A — Expand /var or Add a Dedicated Data Disk

Add a large data disk to the server and either:

- Extend the `/var` LV to provide more space, or
- Mount a dedicated disk at a new path (e.g. `/var/log/remote/`) and configure rsyslog to write received logs there, keeping the OS logs on the existing partition

This is the most robust option. Size the disk based on how many days of local retention are needed. For example, 1TB/day with 3 days retention compressed would need approximately 300GB minimum.

### Option B — Minimal Local Retention, Rely on Azure Monitor Agent

If Azure Monitor Agent (AMA) is forwarding all syslog to Microsoft Sentinel, treat the local server as a short-term buffer only:

- Keep minimal local retention (hours, not days)
- Apply aggressive logrotate settings (see Recommendations below)
- Still requires more disk than the current 8GB — a moderately sized expansion (e.g. 50–100GB) would provide a safe buffer

This reduces disk requirements but still needs expansion. If AMA forwarding stalls or falls behind, the buffer can fill quickly.

### Option C — Rate Limit or Filter at Source

Reduce the volume of logs arriving at the server by:

- Filtering at the firewall/sender — only forward critical events rather than all traffic
- Using rsyslog rate limiting to cap messages per second
- Filtering by facility/severity in the rsyslog config to discard low-value messages before writing to disk

This addresses the root cause if 1TB/day includes a large proportion of noise. Should be combined with Option A or B.

## Recommendations

### 1. Expand disk space (required)

At minimum, expand the `/var` partition or add a dedicated data disk. Sizing depends on the chosen retention period:

| Local Retention | Uncompressed | Compressed (approx) |
|----------------|-------------|---------------------|
| 6 hours | 250 GB | 25 GB |
| 1 day | 1 TB | 100 GB |
| 3 days | 3 TB | 300 GB |
| 7 days | 7 TB | 700 GB |

> **Note:** Compression ratios for syslog text are typically 10:1 but can vary depending on message content. Add a 20–30% safety margin to the compressed estimates.

### 2. Apply aggressive logrotate configuration

Replace the contents of `/etc/logrotate.d/rsyslog` with settings appropriate for high volume:

```
/var/log/messages
/var/log/secure
/var/log/cron
/var/log/maillog
/var/log/spooler
{
    hourly
    rotate 24
    maxsize 500M
    compress
    delaycompress
    missingok
    notifempty
    sharedscripts
    postrotate
        /usr/bin/systemctl -s HUP kill rsyslog.service >/dev/null 2>&1 || true
    endscript
}
```

This config will:

- **hourly** — rotate every hour instead of weekly
- **rotate 24** — keep 24 rotated files (approximately 1 day of history)
- **maxsize 500M** — rotate immediately if any log exceeds 500MB, even between hourly runs
- **compress** — gzip old logs, saving approximately 90% of disk space
- **delaycompress** — keep the most recent rotated file uncompressed for easier troubleshooting

> **Note:** Logrotate must be triggered hourly for the *hourly* directive to work. This requires enabling an hourly cron job or systemd timer for logrotate.

### 3. Enable hourly logrotate execution

By default, logrotate runs daily via cron or systemd timer. For hourly rotation, ensure it runs every hour:

```bash
sudo cp /etc/cron.daily/logrotate /etc/cron.hourly/logrotate
```

Or configure the systemd logrotate timer to run hourly if the system uses timers instead of cron.

### 4. Monitor disk usage

Set up monitoring to alert if `/var` usage exceeds 80%. This provides early warning before the disk fills completely. Azure Monitor can be configured to alert on disk space metrics.

## Summary

| Action | Priority | Status |
|--------|----------|--------|
| Expand /var or add data disk | Critical — must be done before go-live | Pending |
| Update logrotate config | Critical — must be done before go-live | Pending |
| Enable hourly logrotate | High — required for hourly rotation to work | Pending |
| Set up disk usage alerting | Recommended | Pending |
| Review source log filtering | Recommended — may significantly reduce volume | Pending |
