# rsyslog Log Rotation — Best Practices for High Volume Servers

A guide to configuring logrotate for rsyslog on Red Hat-based systems (RHEL, CentOS, Rocky Linux, AlmaLinux) handling high volumes of syslog traffic.

## Why Log Rotation Matters

rsyslog writes to plain text log files that grow indefinitely unless rotated. On a server receiving syslog from network devices, firewalls, or other infrastructure, log files can grow extremely fast. Without proper rotation:

- The disk fills up and rsyslog stops writing
- Incoming syslog messages are dropped or queued until they expire
- System stability is affected as `/var` runs out of space
- Other services sharing the partition may also fail

## Default Configuration (RHEL)

On a fresh RHEL-based install, rsyslog log rotation is configured in `/etc/logrotate.d/rsyslog`:

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

This file contains no explicit rotation settings, so it inherits the global defaults from `/etc/logrotate.conf`:

| Setting | Default | Meaning |
|---------|---------|---------|
| Frequency | weekly | Logs rotate once per week |
| rotate | 4 | Keep 4 rotated copies |
| compress | disabled | Old logs are not compressed |
| maxsize | none | No size-based rotation trigger |

For a low-traffic server this is adequate. For a server ingesting hundreds of gigabytes or more per day, it provides no protection against disk exhaustion.

## Recommended Configuration for High Volume

Replace the contents of `/etc/logrotate.d/rsyslog` with:

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

### What each setting does

| Setting | Purpose |
|---------|---------|
| `hourly` | Rotate every hour instead of weekly |
| `rotate 24` | Keep 24 rotated files — approximately 1 day of history |
| `maxsize 500M` | Rotate immediately if a log exceeds 500MB, even between scheduled runs |
| `compress` | Gzip old log files, saving approximately 90% of disk space |
| `delaycompress` | Keep the most recent rotated file uncompressed for easier troubleshooting |
| `missingok` | Don't error if a log file is missing |
| `notifempty` | Don't rotate if the log file is empty |
| `sharedscripts` | Run the postrotate script once for all files, not once per file |
| `postrotate` | Sends SIGHUP to rsyslog so it reopens log files after rotation |

### Adjusting for your environment

- **Lower volume (~10–50 GB/day):** `daily` with `rotate 7` and `maxsize 1G` may be sufficient
- **Very high volume (1 TB+/day):** Reduce `maxsize` to `200M` and increase `rotate` if disk allows
- **Longer retention needed:** Increase `rotate` — e.g. `rotate 168` for 7 days at hourly rotation
- **Disk constrained:** Reduce `rotate` to keep fewer copies

## Enabling Hourly Logrotate

By default, logrotate runs once per day via cron or a systemd timer. The `hourly` directive only works if logrotate itself is triggered every hour.

**Option 1 — Copy the cron job:**

```bash
sudo cp /etc/cron.daily/logrotate /etc/cron.hourly/logrotate
```

**Option 2 — Modify the systemd timer (if your system uses timers):**

Check current schedule:

```bash
systemctl list-timers | grep logrotate
```

Override the timer to run hourly:

```bash
sudo systemctl edit logrotate.timer
```

Add:

```ini
[Timer]
OnCalendar=
OnCalendar=hourly
```

Then reload:

```bash
sudo systemctl daemon-reload
```

## Disk Sizing Guidelines

When planning disk space for a syslog server, consider the ingestion rate and desired retention period. Syslog text typically compresses at approximately 10:1 with gzip.

| Daily Ingestion | Retention | Uncompressed | Compressed (approx) |
|----------------|-----------|-------------|---------------------|
| 10 GB/day | 7 days | 70 GB | 7 GB |
| 50 GB/day | 7 days | 350 GB | 35 GB |
| 100 GB/day | 3 days | 300 GB | 30 GB |
| 500 GB/day | 1 day | 500 GB | 50 GB |
| 1 TB/day | 1 day | 1 TB | 100 GB |
| 1 TB/day | 3 days | 3 TB | 300 GB |

> **Tip:** Add a 20–30% safety margin to compressed estimates. Compression ratios vary depending on message content — structured or repetitive messages compress better than random data.

### Dedicated log partition

For high-volume servers, mount a separate partition or disk for log storage. This prevents log growth from affecting the operating system or other services:

```bash
# Example: mount a dedicated disk at /var/log
sudo mkfs.xfs /dev/sdX
sudo mount /dev/sdX /var/log
```

Add to `/etc/fstab` for persistence. If using LVM, extend the existing `/var` logical volume instead.

## Monitoring Disk Usage

Set up alerting to catch disk issues before they cause log loss:

- Alert at **80% usage** — investigate and clean up or expand
- Alert at **90% usage** — immediate action required
- Alert at **95% usage** — critical, log loss may be imminent

Most monitoring solutions (Azure Monitor, Prometheus, Zabbix, Nagios) can track filesystem usage and trigger alerts at defined thresholds.

## Additional Considerations

### rsyslog disk-assisted queues

rsyslog can buffer messages in a disk-assisted queue when the output (e.g. forwarding to a SIEM) is temporarily unavailable. These queue files are stored in the `WorkDirectory` (typically `/var/spool/rsyslog/`) and also consume disk space. Account for this when sizing the partition.

### Forwarding to a SIEM

If logs are being forwarded to a central SIEM (e.g. Microsoft Sentinel, Splunk, Elastic), the local server may only need to retain logs as a short-term buffer. In this case:

- Keep local retention to hours rather than days
- Size the disk to handle a forwarding backlog (e.g. if the SIEM is unreachable for several hours)
- Monitor the rsyslog queue size to detect forwarding issues early

### Testing rotation

After changing the logrotate config, do a dry run to verify it works:

```bash
sudo logrotate -d /etc/logrotate.d/rsyslog
```

This shows what logrotate would do without making changes. To force an immediate rotation:

```bash
sudo logrotate -f /etc/logrotate.d/rsyslog
```

## Dedicated Disk for Remote Syslog

For high-volume environments, mount a separate disk specifically for remote syslog. This isolates remote log traffic from the OS partition, preventing log growth from affecting system stability.

### rsyslog configuration

Add the following to `/etc/rsyslog.conf` **before** the existing local logging rules. This directs all remotely received syslog to the new disk while local OS logs remain on the original `/var/log/` partition.

**Option A — Separate file per host and program:**

```
# ---------------------------------------------------
# Remote syslog — write to dedicated disk
# ---------------------------------------------------
template(name="RemoteLog" type="string"
    string="/var/log/remote/%HOSTNAME%/%PROGRAMNAME%.log")

if $fromhost-ip != '127.0.0.1' then {
    action(type="omfile" dynaFile="RemoteLog")
    stop
}
```

This creates a folder structure like:

```
/var/log/remote/
  firewall01/
    kernel.log
    syslogd.log
  switch01/
    mgmt.log
```

**Option B — Single file for all remote syslog:**

```
if $fromhost-ip != '127.0.0.1' then {
    action(type="omfile" file="/var/log/remote/syslog.log")
    stop
}
```

The `stop` directive prevents remote messages from also being written to `/var/log/messages`.

### Logrotate configuration for the new location

Create a new file `/etc/logrotate.d/rsyslog-remote`:

```
/var/log/remote/*.log
/var/log/remote/**/*.log
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

The existing `/etc/logrotate.d/rsyslog` continues to handle local OS logs on the original disk — no changes needed there.

### SELinux labelling

If SELinux is enabled, label the new directory so rsyslog can write to it:

```bash
sudo semanage fcontext -a -t var_log_t "/var/log/remote(/.*)?"
sudo restorecon -Rv /var/log/remote
```

### Summary of changes

| File | Change |
|------|--------|
| `/etc/rsyslog.conf` | Add template and rule to direct remote syslog to `/var/log/remote/` |
| `/etc/logrotate.d/rsyslog-remote` | New file — rotation config for the remote log location |
| SELinux | Label `/var/log/remote/` as `var_log_t` |
| `/etc/logrotate.d/rsyslog` | No change — continues to handle local OS logs |
