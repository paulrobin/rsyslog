<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>rsyslog TLS Setup Guide — Red Hat</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            color: #333;
            margin: 0;
            padding: 20px;
            line-height: 1.6;
        }
        .container { max-width: 850px; margin: 0 auto; }
        h1 { border-bottom: 2px solid #333; padding-bottom: 10px; }
        h2 { margin-top: 40px; }
        .step { margin: 14px 0; }
        .desc { color: #666; font-size: 0.9em; margin: 2px 0 6px 28px; }
        code {
            background: #f4f4f4;
            color: #333;
            padding: 6px 12px;
            border-radius: 4px;
            border: 1px solid #ddd;
            display: block;
            margin: 4px 0 12px 28px;
            font-family: 'Consolas', monospace;
            font-size: 0.9em;
            white-space: pre-wrap;
            word-break: break-all;
        }
        .note {
            border-left: 4px solid #e6a800;
            background: #fff8e6;
            padding: 10px 14px;
            margin: 14px 0;
            font-size: 0.9em;
        }
        .warning {
            border-left: 4px solid #cc0000;
            background: #fff0f0;
            padding: 10px 14px;
            margin: 14px 0;
            font-size: 0.9em;
        }
    </style>
</head>
<body>
<div class="container">

<h1>rsyslog TLS Setup Guide — Red Hat</h1>
<p>Manual setup steps for configuring rsyslog with TLS on RHEL, CentOS Stream, Rocky Linux, or AlmaLinux. All commands require root or sudo.</p>

<h2>Install Required Packages</h2>

<div class="step">
    <strong>1. Install packages</strong>
    <div class="desc">Installs rsyslog, GnuTLS module for TLS support, certificate tools, and SELinux policy utilities.</div>
    <code>sudo dnf install -y rsyslog rsyslog-gnutls gnutls-utils policycoreutils-python-utils</code>
</div>

<h2>Create Directories</h2>

<div class="step">
    <strong>2. Create certificate and backup directories</strong>
    <div class="desc">Creates the directory where TLS certificates will be stored, plus a backup subfolder.</div>
    <code>sudo mkdir -p /etc/rsyslog.d/keys/backup</code>
</div>

<div class="step">
    <strong>3. Set permissions on certificate directory</strong>
    <div class="desc">Allows rsyslog to access the certificate directory.</div>
    <code>sudo chmod 755 /etc/rsyslog.d/keys</code>
</div>

<div class="step">
    <strong>4. Create spool directory</strong>
    <div class="desc">Used for disk-assisted queues — buffers messages if forwarding is temporarily unavailable.</div>
    <code>sudo mkdir -p /var/spool/rsyslog</code>
</div>

<h2>Configure SELinux</h2>
<div class="note"><strong>Note:</strong> Skip steps 5–10 if SELinux is disabled. Check with: <em>getenforce</em></div>

<div class="step">
    <strong>5. Allow rsyslog on TLS port 6514</strong>
    <div class="desc">Permits rsyslog to bind to port 6514/tcp (standard syslog-TLS port).</div>
    <code>sudo semanage port -a -t syslogd_port_t -p tcp 6514</code>
</div>

<div class="step">
    <strong>6. Label certificate directory</strong>
    <div class="desc">Assigns the cert_t SELinux type so rsyslog can read certificate files.</div>
    <code>sudo semanage fcontext -a -t cert_t "/etc/rsyslog.d/keys(/.*)?"</code>
</div>

<div class="step">
    <strong>7. Apply SELinux labels to certificate directory</strong>
    <div class="desc">Applies the label from step 6 to files on disk.</div>
    <code>sudo restorecon -Rv /etc/rsyslog.d/keys</code>
</div>

<div class="step">
    <strong>8. Label spool directory</strong>
    <div class="desc">Assigns the syslogd_var_lib_t SELinux type so rsyslog can write queue files.</div>
    <code>sudo semanage fcontext -a -t syslogd_var_lib_t "/var/spool/rsyslog(/.*)?"</code>
</div>

<div class="step">
    <strong>9. Apply SELinux labels to spool directory</strong>
    <div class="desc">Applies the label from step 8 to files on disk.</div>
    <code>sudo restorecon -Rv /var/spool/rsyslog</code>
</div>

<div class="step">
    <strong>10. Allow Azure Monitor Agent port (optional)</strong>
    <div class="desc">Pre-allows port 28330/tcp for AMA if it will be installed later.</div>
    <code>sudo semanage port -a -t syslogd_port_t -p tcp 28330</code>
</div>

<h2>Configure Firewall</h2>
<div class="note"><strong>Note:</strong> Skip steps 11–12 if firewalld is not running.</div>

<div class="step">
    <strong>11. Open port 6514 in firewall</strong>
    <div class="desc">Allows remote syslog clients to connect over TLS.</div>
    <code>sudo firewall-cmd --permanent --add-port=6514/tcp</code>
</div>

<div class="step">
    <strong>12. Reload firewall</strong>
    <div class="desc">Applies the new firewall rule immediately.</div>
    <code>sudo firewall-cmd --reload</code>
</div>

<h2>Deploy rsyslog Configuration</h2>

<div class="step">
    <strong>13. Back up existing config</strong>
    <div class="desc">Creates a timestamped backup of the current rsyslog.conf.</div>
    <code>sudo cp /etc/rsyslog.conf /etc/rsyslog.conf.backup.$(date +%Y%m%d%H%M%S)</code>
</div>

<div class="step">
    <strong>14. Edit rsyslog.conf — paste new TLS configuration</strong>
    <div class="desc">Open the file, delete all existing content, and paste the contents of rsyslog.conf.rh.</div>
    <code>sudo vi /etc/rsyslog.conf</code>
</div>

<div class="warning"><strong>vi tip:</strong> Type <em>gg</em> then <em>dG</em> to clear the file. Press <em>i</em> to enter insert mode, paste the config, then <em>:wq</em> to save and quit.</div>

<h2>Deploy Certificate Files</h2>
<p>Create each file and paste the PEM content from your local machine via the terminal session.</p>

<div class="step">
    <strong>15. Create CA certificate</strong>
    <div class="desc">Paste the CA certificate (or chain) in PEM format. Used to verify client certificates.</div>
    <code>sudo vi /etc/rsyslog.d/keys/ca.pem</code>
</div>

<div class="step">
    <strong>16. Create server certificate</strong>
    <div class="desc">Paste the server's TLS certificate in PEM format. Presented to clients during TLS handshake.</div>
    <code>sudo vi /etc/rsyslog.d/keys/server-cert.pem</code>
</div>

<div class="step">
    <strong>17. Create server private key</strong>
    <div class="desc">Paste the server's private key in PEM format. Must match the server certificate.</div>
    <code>sudo vi /etc/rsyslog.d/keys/server-key.pem</code>
</div>

<div class="warning"><strong>Security:</strong> The private key (server-key.pem) is sensitive. Do not share or expose it.</div>

<div class="step">
    <strong>18. Set ownership on all certificate files</strong>
    <div class="desc">Ensures all PEM files are owned by root.</div>
    <code>sudo chown root:root /etc/rsyslog.d/keys/*.pem</code>
</div>

<div class="step">
    <strong>19. Set permissions on CA certificate</strong>
    <div class="desc">World-readable (644) — the CA cert is public information.</div>
    <code>sudo chmod 644 /etc/rsyslog.d/keys/ca.pem</code>
</div>

<div class="step">
    <strong>20. Set permissions on server certificate</strong>
    <div class="desc">World-readable (644) — the server cert is sent during TLS negotiation.</div>
    <code>sudo chmod 644 /etc/rsyslog.d/keys/server-cert.pem</code>
</div>

<div class="step">
    <strong>21. Set permissions on server private key</strong>
    <div class="desc">Root-only (600) — protects the private key from other users.</div>
    <code>sudo chmod 600 /etc/rsyslog.d/keys/server-key.pem</code>
</div>

<div class="step">
    <strong>22. Restore SELinux labels on certificate files</strong>
    <div class="desc">Applies correct SELinux labels to the new files. Skip if SELinux is disabled.</div>
    <code>sudo restorecon -Rv /etc/rsyslog.d/keys/</code>
</div>

<h2>Validate and Start</h2>

<div class="step">
    <strong>23. Validate rsyslog configuration</strong>
    <div class="desc">Checks the config file for syntax errors. Should print the version and exit cleanly.</div>
    <code>sudo rsyslogd -N 1</code>
</div>

<div class="step">
    <strong>24. Verify server certificate against CA</strong>
    <div class="desc">Confirms the server certificate was signed by the CA. If this fails, TLS connections will not work.</div>
    <code>sudo certtool --verify --load-ca-certificate /etc/rsyslog.d/keys/ca.pem --infile /etc/rsyslog.d/keys/server-cert.pem</code>
</div>

<div class="step">
    <strong>25. Restart rsyslog</strong>
    <div class="desc">Restarts the service to load the new TLS configuration.</div>
    <code>sudo systemctl restart rsyslog</code>
</div>

<div class="step">
    <strong>26. Check service status</strong>
    <div class="desc">Verify rsyslog is running. Look for "active (running)" and no TLS errors in the output.</div>
    <code>sudo systemctl status rsyslog</code>
</div>

<div class="step">
    <strong>27. Verify TLS port is listening</strong>
    <div class="desc">Confirms rsyslog is listening on port 6514. You should see rsyslogd listed.</div>
    <code>sudo ss -tlnp | grep 6514</code>
</div>

<div class="note"><strong>Done!</strong> If step 27 shows rsyslog listening on port 6514, the server is ready to receive TLS-encrypted syslog messages.</div>

</div>
</body>
</html>
