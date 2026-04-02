# Moving rsyslog Logs to a Dedicated Disk — /data/var/

Guide for moving rsyslog log files and spool directory to a dedicated disk mounted at `/data/var/` on RHEL-based systems with SELinux enabled.

## 1. Create Directory Structure

```bash
sudo mkdir -p /data/var/log/remote
```

Creates the main log directory and a `remote/` subfolder for logs received from network devices over TLS.

```bash
sudo mkdir -p /data/var/spool/rsyslog
```

Creates the spool directory for rsyslog's disk-assisted queues. rsyslog uses this to buffer messages when a downstream destination (e.g. AMA) is temporarily unavailable.

## 2. Set Ownership

```bash
sudo chown root:root /data/var/log /data/var/log/remote /data/var/spool/rsyslog
```

Sets all directories to be owned by `root:root`. rsyslog runs as root on RHEL and needs ownership to write log files and queue data.

## 3. Set Permissions

```bash
sudo chmod 755 /data/var/log /data/var/log/remote
```

Sets the log directories to 755 (owner read/write/execute, others read/execute). This allows rsyslog to write logs and other processes to read them.

```bash
sudo chmod 700 /data/var/spool/rsyslog
```

Sets the spool directory to 700 (owner only). Queue files may contain buffered log data and should not be readable by other users.

## 4. SELinux — Label All Directories in the Path

Every directory from the mount point down needs a valid SELinux label. Without this, rsyslog (running as `syslogd_t`) cannot traverse the path to reach the log and spool directories.

```bash
sudo chcon -t default_t /data
sudo chcon -t var_t /data/var
sudo chcon -t var_t /data/var/spool
sudo chcon -R -t var_log_t /data/var/log
sudo chcon -R -t syslogd_var_lib_t /data/var/spool/rsyslog
```

Make the labels persistent across relabels:

```bash
sudo semanage fcontext -a -t default_t "/data"
sudo semanage fcontext -a -t var_log_t "/data/var/log(/.*)?"
sudo semanage fcontext -a -t syslogd_var_lib_t "/data/var/spool/rsyslog(/.*)?"
```

## 5. Verify SELinux Labels

```bash
ls -laZ /data/var/log/
```

Lists the log directory with SELinux context labels. You should see `var_log_t` in the output.

```bash
ls -laZ /data/var/spool/rsyslog/
```

Lists the spool directory with SELinux context labels. You should see `syslogd_var_lib_t` in the output.

## 6. Update rsyslog Configuration

Edit `/etc/rsyslog.conf` and make the following changes:

### Change the work directory

```
$WorkDirectory /data/var/spool/rsyslog
```

Tells rsyslog to use the new spool directory for disk-assisted queues. **Important:** This line must appear before any `module()` directives — particularly `imjournal`, which resolves its `StateFile` path relative to `$WorkDirectory`. If `$WorkDirectory` comes after the module load, the state file will be written to `/` and SELinux will block it.

Also update the `global()` block if it contains a `workDirectory` setting:

```
global(
    ...
    workDirectory="/data/var/spool/rsyslog"
)
```

### Update local log paths (if moving local logs too)

Replace the existing local logging rules with the new paths:

```
*.info;mail.none;authpriv.none;cron.none    /data/var/log/messages
authpriv.*                                   /data/var/log/secure
mail.*                                       -/data/var/log/maillog
cron.*                                       /data/var/log/cron
*.emerg                                      :omusrmsg:*
local7.*                                     /data/var/log/boot.log
```

## 7. Update Logrotate

Since all logs are now on the dedicated disk, update `/etc/logrotate.d/rsyslog` with paths and settings suitable for high-volume ingestion:

```
/data/var/log/messages
/data/var/log/secure
/data/var/log/cron
/data/var/log/maillog
/data/var/log/spooler
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
| `hourly` | Rotate every hour instead of the default weekly |
| `rotate 48` | Keep 48 rotated files — approximately 2 days of history |
| `maxsize 500M` | Rotate immediately if a log exceeds 500MB, even between scheduled runs |
| `compress` | Gzip old log files, saving approximately 90% of disk space |
| `delaycompress` | Keep the most recent rotated file uncompressed for easier troubleshooting |
| `missingok` | Don't error if a log file doesn't exist |
| `notifempty` | Don't rotate if the log file is empty |
| `sharedscripts` | Run the postrotate script once for all files, not once per file |
| `postrotate` | Sends SIGHUP to rsyslog so it reopens log files after rotation |

### Enable hourly logrotate

By default, logrotate runs once per day. The `hourly` directive only works if logrotate itself is triggered every hour:

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

### Adjusting for your environment

| Daily Volume | Suggested `maxsize` | Suggested `rotate` | Approximate Disk Used |
|-------------|--------------------|--------------------|----------------------|
| 10–50 GB/day | 1G | 24 (1 day) | 5–10 GB compressed |
| 50–200 GB/day | 500M | 48 (2 days) | 20–40 GB compressed |
| 200 GB–1 TB/day | 200M | 24 (1 day) | 40–100 GB compressed |
| 1 TB+/day | 200M | 12 (12 hours) | 50–100 GB compressed |

### Test rotation

Dry run (shows what would happen without making changes):

```bash
sudo logrotate -d /etc/logrotate.d/rsyslog
```

Force an immediate rotation:

```bash
sudo logrotate -f /etc/logrotate.d/rsyslog
```
}
```

## 8. Validate and Restart

```bash
sudo rsyslogd -N 1
```

Runs rsyslog's built-in configuration checker. If the config is valid, it prints the version and exits cleanly. If there are errors (e.g. invalid paths, syntax issues), they are displayed.

```bash
sudo systemctl restart rsyslog
```

Restarts rsyslog to load the new configuration and begin writing to the new locations.

```bash
sudo systemctl status rsyslog
```

Confirms rsyslog is running without errors. Look for "active (running)" and check for any SELinux or permission errors in the output.

```bash
sudo ss -tlnp | grep 6514
```

Verifies rsyslog is still listening on port 6514 for TLS syslog connections after the restart.

## 9. Verify Logs Are Being Written

```bash
ls -la /data/var/log/
```

Confirms log files are being created in the new location.

```bash
sudo tail -f /data/var/log/messages
```

Watches the new log file for incoming messages in real time.

## Quick Reference — All Commands

```bash
# Create directories
sudo mkdir -p /data/var/log/remote
sudo mkdir -p /data/var/spool/rsyslog

# Set ownership and permissions
sudo chown root:root /data/var/log /data/var/log/remote /data/var/spool/rsyslog
sudo chmod 755 /data/var/log /data/var/log/remote
sudo chmod 700 /data/var/spool/rsyslog

# SELinux — label every directory in the path
sudo chcon -t default_t /data
sudo chcon -t var_t /data/var
sudo chcon -t var_t /data/var/spool
sudo chcon -R -t var_log_t /data/var/log
sudo chcon -R -t syslogd_var_lib_t /data/var/spool/rsyslog

# SELinux — make labels persistent across relabels
sudo semanage fcontext -a -t default_t "/data"
sudo semanage fcontext -a -t var_log_t "/data/var/log(/.*)?"
sudo semanage fcontext -a -t syslogd_var_lib_t "/data/var/spool/rsyslog(/.*)?"

# Verify labels
ls -laZ /data/
ls -laZ /data/var/
ls -laZ /data/var/log/
sudo ls -laZ /data/var/spool/rsyslog/

# Validate and restart
sudo rsyslogd -N 1
sudo systemctl restart rsyslog
sudo systemctl status rsyslog
sudo ss -tlnp | grep 6514
```
