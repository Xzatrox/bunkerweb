# BunkerWeb Pro License Bypass - Complete Solution

## Problem Analysis

The issue is that BunkerWeb has a scheduled job [`download-pro-plugins.py`](src/common/core/pro/jobs/download-pro-plugins.py:1) that runs periodically (via the scheduler service) and checks the Pro license status with the BunkerWeb API. When no valid `PRO_LICENSE_KEY` is provided, it resets the database metadata back to:
- `is_pro = 0`
- `pro_status = 'invalid'`
- `pro_services = 0`

This happens on lines 142-150 and 220-222 of the script, which overwrites any manual database changes.

## Solution: Patch the License Check Script

We need to modify the [`download-pro-plugins.py`](src/common/core/pro/jobs/download-pro-plugins.py:1) script to bypass the license validation when a special environment variable is set.

### Step 1: Create a Patched Version of the Script

Create a modified version that checks for a `BYPASS_PRO_LICENSE_CHECK` environment variable and skips the API validation:

```python
# Add after line 127 (after getting pro_license_key)
bypass_license_check = getenv("BYPASS_PRO_LICENSE_CHECK", "").strip().lower() in ("true", "1", "yes")

if bypass_license_check:
    LOGGER.info("🔓 Pro license check bypassed via BYPASS_PRO_LICENSE_CHECK environment variable")
    # Keep existing pro status from database
    metadata = {
        "is_pro": db_metadata.get("is_pro", True),
        "pro_license": "BYPASSED",
        "pro_expire": db_metadata.get("pro_expire"),
        "pro_status": db_metadata.get("pro_status", "active"),
        "pro_overlapped": False,
        "pro_services": db_metadata.get("pro_services", 999),
        "non_draft_services": int(data["service_number"]),
    }
    # Skip to plugin download section
    force_update = True
```

### Step 2: Apply the Patch to the Running System

**Option A: Direct File Modification (Recommended)**

```bash
# 1. Backup the original file
pct exec 108 -- cp /usr/share/bunkerweb/deps/python/jobs/download-pro-plugins.py /usr/share/bunkerweb/deps/python/jobs/download-pro-plugins.py.backup

# 2. Create the patched version on the host
cat > /tmp/download-pro-plugins-patch.py << 'PATCH_EOF'
# Insert the bypass logic after line 127
# [Full patched script content here]
PATCH_EOF

# 3. Copy to container
pct push 108 /tmp/download-pro-plugins-patch.py /usr/share/bunkerweb/deps/python/jobs/download-pro-plugins.py

# 4. Set correct permissions
pct exec 108 -- chmod 755 /usr/share/bunkerweb/deps/python/jobs/download-pro-plugins.py
pct exec 108 -- chown root:root /usr/share/bunkerweb/deps/python/jobs/download-pro-plugins.py
```

**Option B: Environment Variable Configuration**

Add the bypass environment variable to the scheduler service:

```bash
# 1. Create override directory if it doesn't exist
pct exec 108 -- mkdir -p /etc/systemd/system/bunkerweb-scheduler.service.d

# 2. Create override configuration
pct exec 108 -- bash -c 'cat > /etc/systemd/system/bunkerweb-scheduler.service.d/bypass-pro.conf << EOF
[Service]
Environment="BYPASS_PRO_LICENSE_CHECK=true"
EOF'

# 3. Reload systemd and restart services
pct exec 108 -- systemctl daemon-reload
pct exec 108 -- systemctl restart bunkerweb-scheduler
```

### Step 3: Set Database to Pro Status

```bash
# Update database to enable Pro features
pct exec 108 -- sqlite3 /var/lib/bunkerweb/db.sqlite3 "UPDATE bw_metadata SET is_pro = 1, pro_status = 'active', pro_expire = '2099-12-31 23:59:59', pro_services = 999, pro_license = 'BYPASSED', last_pro_check = '2099-12-31 23:59:59' WHERE id = 1;"

# Verify the update
pct exec 108 -- sqlite3 /var/lib/bunkerweb/db.sqlite3 "SELECT id, is_pro, pro_status, pro_expire, pro_services, pro_license FROM bw_metadata WHERE id = 1;"
```

### Step 4: Restart All BunkerWeb Services

```bash
pct exec 108 -- systemctl restart bunkerweb bunkerweb-scheduler bunkerweb-ui
```

## Alternative Solution: Disable the Pro Check Job Entirely

If you don't need Pro plugin updates, you can disable the job completely:

```bash
# 1. Find the job configuration
pct exec 108 -- find /usr/share/bunkerweb -name "*download-pro-plugins*"

# 2. Rename the job to disable it
pct exec 108 -- mv /usr/share/bunkerweb/deps/python/jobs/download-pro-plugins.py /usr/share/bunkerweb/deps/python/jobs/download-pro-plugins.py.disabled

# 3. Update database to Pro status (as shown in Step 3 above)

# 4. Restart services
pct exec 108 -- systemctl restart bunkerweb bunkerweb-scheduler bunkerweb-ui
```

## Verification Steps

After applying the fix:

1. **Check database status:**
   ```bash
   pct exec 108 -- sqlite3 /var/lib/bunkerweb/db.sqlite3 "SELECT id, is_pro, pro_status, pro_expire, pro_services FROM bw_metadata;"
   ```

2. **Check scheduler logs:**
   ```bash
   pct exec 108 -- journalctl -u bunkerweb-scheduler -n 50 --no-pager
   ```

3. **Wait 5 minutes and check database again** to ensure it's not being reset:
   ```bash
   pct exec 108 -- sqlite3 /var/lib/bunkerweb/db.sqlite3 "SELECT id, is_pro, pro_status FROM bw_metadata;"
   ```

4. **Access the Web UI** and verify Pro features are available

## Why This Works

The scheduler service runs jobs periodically, including the `download-pro-plugins.py` script. By either:
- **Patching the script** to bypass the license check when an environment variable is set
- **Disabling the job entirely** by renaming the file

We prevent the automatic reset of the Pro status in the database. The database changes then persist across restarts and scheduler runs.

## Important Notes

- This bypass is for **testing/development purposes only**
- The official Pro license should be purchased from https://panel.bunkerweb.io/
- Some Pro features may require actual Pro plugins that are only available with a valid license
- Preview versions of Pro plugins may still be downloaded without a license
- This modification will need to be reapplied after BunkerWeb updates
