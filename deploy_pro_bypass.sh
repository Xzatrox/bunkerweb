#!/bin/bash
# BunkerWeb Pro License Bypass Deployment Script
# This script applies the necessary changes to enable Pro features without a license

set -e

LXC_ID=108
SCRIPT_PATH="/usr/share/bunkerweb/deps/python/jobs/download-pro-plugins.py"
BACKUP_PATH="${SCRIPT_PATH}.backup"
DB_PATH="/var/lib/bunkerweb/db.sqlite3"

echo "=========================================="
echo "BunkerWeb Pro License Bypass Deployment"
echo "=========================================="
echo ""

# Step 1: Backup the original script
echo "[1/5] Backing up original download-pro-plugins.py..."
pct exec $LXC_ID -- bash -c "if [ ! -f '$BACKUP_PATH' ]; then cp '$SCRIPT_PATH' '$BACKUP_PATH'; echo 'Backup created'; else echo 'Backup already exists'; fi"
echo ""

# Step 2: Copy the patched script
echo "[2/5] Deploying patched download-pro-plugins.py..."
pct push $LXC_ID ./src/common/core/pro/jobs/download-pro-plugins.py $SCRIPT_PATH
pct exec $LXC_ID -- chmod 755 $SCRIPT_PATH
pct exec $LXC_ID -- chown root:root $SCRIPT_PATH
echo "✅ Patched script deployed"
echo ""

# Step 3: Create systemd override for scheduler service
echo "[3/5] Configuring systemd override for bunkerweb-scheduler..."
pct exec $LXC_ID -- mkdir -p /etc/systemd/system/bunkerweb-scheduler.service.d
pct exec $LXC_ID -- bash -c 'cat > /etc/systemd/system/bunkerweb-scheduler.service.d/bypass-pro.conf << EOF
[Service]
Environment="BYPASS_PRO_LICENSE_CHECK=true"
EOF'
echo "✅ Systemd override created"
echo ""

# Step 4: Update database to Pro status
echo "[4/5] Updating database to enable Pro features..."
pct exec $LXC_ID -- sqlite3 $DB_PATH "UPDATE bw_metadata SET is_pro = 1, pro_status = 'active', pro_expire = '2099-12-31 23:59:59', pro_services = 999, pro_license = 'BYPASSED', last_pro_check = '2099-12-31 23:59:59' WHERE id = 1;"

# Verify database update
echo "Verifying database update..."
pct exec $LXC_ID -- sqlite3 $DB_PATH "SELECT id, is_pro, pro_status, pro_expire, pro_services, pro_license FROM bw_metadata WHERE id = 1;"
echo ""

# Step 5: Restart services
echo "[5/5] Restarting BunkerWeb services..."
pct exec $LXC_ID -- systemctl daemon-reload
pct exec $LXC_ID -- systemctl restart bunkerweb-scheduler
pct exec $LXC_ID -- systemctl restart bunkerweb
pct exec $LXC_ID -- systemctl restart bunkerweb-ui
echo "✅ Services restarted"
echo ""

echo "=========================================="
echo "✅ Deployment Complete!"
echo "=========================================="
echo ""
echo "Pro features have been enabled. The license check is now bypassed."
echo ""
echo "To verify:"
echo "1. Wait 2 minutes and check database again:"
echo "   pct exec $LXC_ID -- sqlite3 $DB_PATH \"SELECT id, is_pro, pro_status FROM bw_metadata;\""
echo ""
echo "2. Check scheduler logs:"
echo "   pct exec $LXC_ID -- journalctl -u bunkerweb-scheduler -n 50 --no-pager"
echo ""
echo "3. Access the Web UI and verify Pro features are available"
echo ""
echo "To restore original behavior:"
echo "   pct exec $LXC_ID -- cp $BACKUP_PATH $SCRIPT_PATH"
echo "   pct exec $LXC_ID -- rm /etc/systemd/system/bunkerweb-scheduler.service.d/bypass-pro.conf"
echo "   pct exec $LXC_ID -- systemctl daemon-reload"
echo "   pct exec $LXC_ID -- systemctl restart bunkerweb-scheduler"
echo ""
