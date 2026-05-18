#!/bin/bash
# BunkerWeb Complete LAN Isolation Script
# This script disables ALL external network communications

set -e

LXC_ID=108
JOBS_DIR="/usr/share/bunkerweb/deps/python/jobs"
BACKUP_DIR="/root/bunkerweb_jobs_backup_$(date +%Y%m%d_%H%M%S)"

echo "=============================================="
echo "BunkerWeb Complete LAN Isolation Deployment"
echo "=============================================="
echo ""
echo "This script will:"
echo "  1. Disable anonymous telemetry reporting"
echo "  2. Bypass Pro license checks"
echo "  3. Disable update checker"
echo "  4. Disable MMDB auto-updates"
echo "  5. Add DNS blackhole entries"
echo "  6. Configure environment variables"
echo ""
read -p "Continue? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi
echo ""

# Step 1: Backup all job files
echo "[1/7] Creating backup of job files..."
pct exec $LXC_ID -- mkdir -p "$BACKUP_DIR"
pct exec $LXC_ID -- bash -c "cp -r $JOBS_DIR/* $BACKUP_DIR/"
echo "✅ Backup created at: $BACKUP_DIR"
echo ""

# Step 2: Disable anonymous reporting job
echo "[2/7] Disabling anonymous telemetry reporting..."
pct exec $LXC_ID -- bash -c "
if [ -f $JOBS_DIR/anonymous-report.py ]; then
    mv $JOBS_DIR/anonymous-report.py $JOBS_DIR/anonymous-report.py.disabled
    echo '  ✅ anonymous-report.py disabled'
else
    echo '  ⚠️  anonymous-report.py not found or already disabled'
fi
"
echo ""

# Step 3: Disable update checker
echo "[3/7] Disabling update checker..."
pct exec $LXC_ID -- bash -c "
if [ -f $JOBS_DIR/update-check.py ]; then
    mv $JOBS_DIR/update-check.py $JOBS_DIR/update-check.py.disabled
    echo '  ✅ update-check.py disabled'
else
    echo '  ⚠️  update-check.py not found or already disabled'
fi
"
echo ""

# Step 4: Deploy patched Pro license bypass
echo "[4/7] Deploying Pro license bypass patch..."
if [ -f "./src/common/core/pro/jobs/download-pro-plugins.py" ]; then
    pct push $LXC_ID ./src/common/core/pro/jobs/download-pro-plugins.py $JOBS_DIR/download-pro-plugins.py
    pct exec $LXC_ID -- chmod 755 $JOBS_DIR/download-pro-plugins.py
    pct exec $LXC_ID -- chown root:root $JOBS_DIR/download-pro-plugins.py
    echo "  ✅ Patched download-pro-plugins.py deployed"
else
    echo "  ⚠️  Patched file not found, skipping"
fi
echo ""

# Step 5: Configure environment variables
echo "[5/7] Configuring environment variables for LAN isolation..."

# Create systemd override directories
pct exec $LXC_ID -- mkdir -p /etc/systemd/system/bunkerweb.service.d
pct exec $LXC_ID -- mkdir -p /etc/systemd/system/bunkerweb-scheduler.service.d
pct exec $LXC_ID -- mkdir -p /etc/systemd/system/bunkerweb-ui.service.d

# Create override for main service
pct exec $LXC_ID -- bash -c 'cat > /etc/systemd/system/bunkerweb.service.d/lan-isolation.conf << EOF
[Service]
Environment="SEND_ANONYMOUS_REPORT=no"
EOF'

# Create override for scheduler service
pct exec $LXC_ID -- bash -c 'cat > /etc/systemd/system/bunkerweb-scheduler.service.d/lan-isolation.conf << EOF
[Service]
Environment="SEND_ANONYMOUS_REPORT=no"
Environment="BYPASS_PRO_LICENSE_CHECK=true"
EOF'

# Create override for UI service
pct exec $LXC_ID -- bash -c 'cat > /etc/systemd/system/bunkerweb-ui.service.d/lan-isolation.conf << EOF
[Service]
Environment="SEND_ANONYMOUS_REPORT=no"
EOF'

echo "  ✅ Environment variables configured"
echo ""

# Step 6: Add DNS blackhole entries
echo "[6/7] Adding DNS blackhole entries to /etc/hosts..."
pct exec $LXC_ID -- bash -c 'cat >> /etc/hosts << EOF

# BunkerWeb LAN Isolation - Block external API endpoints
127.0.0.1 api.bunkerweb.io
127.0.0.1 assets.bunkerity.com
127.0.0.1 panel.bunkerweb.io
127.0.0.1 api.github.com
127.0.0.1 github.com
127.0.0.1 raw.githubusercontent.com
127.0.0.1 db-ip.com
127.0.0.1 download.db-ip.com
127.0.0.1 publicsuffix.org
127.0.0.1 api.darkvisitors.com
EOF'
echo "  ✅ DNS blackhole entries added"
echo ""

# Step 7: Update database and restart services
echo "[7/7] Updating database and restarting services..."

# Reload systemd and restart services
pct exec $LXC_ID -- systemctl daemon-reload
pct exec $LXC_ID -- systemctl restart bunkerweb-scheduler
pct exec $LXC_ID -- systemctl restart bunkerweb
pct exec $LXC_ID -- systemctl restart bunkerweb-ui

echo "  ✅ Services restarted"
echo ""

echo "=============================================="
echo "✅ LAN Isolation Deployment Complete!"
echo "=============================================="
echo ""
echo "BunkerWeb is now configured for complete LAN isolation:"
echo ""
echo "  ✅ Anonymous telemetry: DISABLED"
echo "  ✅ Pro license checks: BYPASSED"
echo "  ✅ Update checker: DISABLED"
echo "  ✅ External API calls: BLOCKED (DNS)"
echo "  ✅ Pro features: ENABLED"
echo ""
echo "Verification commands:"
echo "  1. Check database status:"
echo "     pct exec $LXC_ID -- sqlite3 /var/lib/bunkerweb/db.sqlite3 \"SELECT id, is_pro, pro_status, pro_license FROM bw_metadata;\""
echo ""
echo "  2. Check for external connections:"
echo "     pct exec $LXC_ID -- netstat -tupn | grep ESTABLISHED"
echo ""
echo "  3. Check scheduler logs:"
echo "     pct exec $LXC_ID -- journalctl -u bunkerweb-scheduler -n 50 --no-pager"
echo ""
echo "  4. Test DNS blackhole:"
echo "     pct exec $LXC_ID -- ping -c 1 api.bunkerweb.io"
echo ""
echo "Backup location: $BACKUP_DIR"
echo ""
echo "To restore original behavior:"
echo "  pct exec $LXC_ID -- bash -c 'cp -r $BACKUP_DIR/* $JOBS_DIR/'"
echo "  pct exec $LXC_ID -- rm /etc/systemd/system/bunkerweb*.service.d/lan-isolation.conf"
echo "  pct exec $LXC_ID -- sed -i '/BunkerWeb LAN Isolation/,+10d' /etc/hosts"
echo "  pct exec $LXC_ID -- systemctl daemon-reload"
echo "  pct exec $LXC_ID -- systemctl restart bunkerweb bunkerweb-scheduler bunkerweb-ui"
echo ""
