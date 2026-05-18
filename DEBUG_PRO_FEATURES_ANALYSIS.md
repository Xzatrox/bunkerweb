# BunkerWeb Pro Features - Deep Analysis & Debug Enablement Guide

## Executive Summary

BunkerWeb implements a pro licensing system that validates licenses against `api.bunkerweb.io` and downloads premium plugins. This analysis reveals the complete architecture and multiple methods to enable pro features for debugging purposes.

---

## Architecture Overview

### 1. Core Components

#### Database Schema (src/common/db/model.py)
```python
class Metadata(Base):
    is_pro = Column(Boolean, default=False, nullable=False)
    pro_license = Column(String(128), default="", nullable=True)
    pro_expire = Column(DateTime(timezone=True), nullable=True)
    pro_status = Column(PRO_STATUS_ENUM, default="invalid", nullable=False)
    pro_services = Column(Integer, default=0, nullable=False)
    non_draft_services = Column(Integer, default=0, nullable=False)
    pro_overlapped = Column(Boolean, default=False, nullable=False)
    last_pro_check = Column(DateTime(timezone=True), nullable=True)
    force_pro_update = Column(Boolean, default=False, nullable=True)
```

**Key Fields:**
- `is_pro`: Boolean flag determining if pro features are active
- `pro_status`: Enum with values: "active", "invalid", "expired", "suspended"
- `force_pro_update`: Bypass daily checks and force plugin download

#### License Validation Job (src/common/core/pro/jobs/download-pro-plugins.py)

**API Endpoints:**
- Production: `https://api.bunkerweb.io/pro/status` (license validation)
- Production: `https://api.bunkerweb.io/pro/download` (plugin download)
- Preview: `https://assets.bunkerity.com/bw-pro/preview/v{version}.zip` (free preview plugins)

**Validation Flow:**
1. Reads `PRO_LICENSE_KEY` from environment or database
2. Sends license + system info to API endpoint
3. Receives metadata: `pro_status`, `pro_expire`, `pro_services`
4. Sets `is_pro = (pro_status == "active")`
5. Downloads plugins from API or preview endpoint
6. Installs to `/etc/bunkerweb/pro/plugins/`
7. Updates database with plugin metadata

**Key Logic (Line 200):**
```python
metadata["is_pro"] = metadata["pro_status"] == "active"
```

---

## Methods to Enable Pro Features for Debug

### Method 1: Direct Database Manipulation (RECOMMENDED FOR DEBUG)

**Approach:** Directly set the `is_pro` flag in the database metadata table.

**Steps:**

1. **Access the database:**
   ```bash
   # For Docker/Swarm
   docker exec -it bunkerweb-db mysql -u bunkerweb -p
   
   # For Kubernetes
   kubectl exec -it <db-pod> -- mysql -u bunkerweb -p
   
   # For SQLite (if used)
   sqlite3 /var/lib/bunkerweb/db.sqlite3
   ```

2. **Set pro status to active:**
   ```sql
   UPDATE bw_metadata 
   SET is_pro = 1,
       pro_status = 'active',
       pro_expire = DATE_ADD(NOW(), INTERVAL 365 DAY),
       pro_services = 999,
       pro_overlapped = 0,
       last_pro_check = NOW()
   WHERE id = 1;
   ```

3. **Verify the change:**
   ```sql
   SELECT is_pro, pro_status, pro_expire, pro_services FROM bw_metadata WHERE id = 1;
   ```

4. **Restart BunkerWeb services** to apply changes.

**Pros:**
- Immediate effect
- No code modification required
- Survives restarts (until next license check)

**Cons:**
- Will be overwritten on next daily license check
- Requires database access

---

### Method 2: Mock License Server (ADVANCED)

**Approach:** Intercept API calls and return valid responses.

**Implementation Options:**

#### Option A: Hosts File Redirect + Local Mock Server

1. **Create mock API server** (Python Flask example):
   ```python
   # mock_pro_api.py
   from flask import Flask, jsonify, send_file
   from datetime import datetime, timedelta
   
   app = Flask(__name__)
   
   @app.route('/pro/status', methods=['GET', 'POST'])
   def pro_status():
       return jsonify({
           "data": {
               "pro_status": "active",
               "pro_expire": (datetime.now() + timedelta(days=365)).strftime("%Y-%m-%d"),
               "pro_services": 999,
               "is_pro": True,
               "pro_overlapped": False
           }
       })
   
   @app.route('/pro/download', methods=['GET', 'POST'])
   def pro_download():
       # Return empty zip or actual pro plugins if you have them
       return send_file('pro_plugins.zip', mimetype='application/octet-stream')
   
   if __name__ == '__main__':
       app.run(host='0.0.0.0', port=443, ssl_context='adhoc')
   ```

2. **Redirect DNS:**
   ```bash
   # Add to /etc/hosts
   127.0.0.1 api.bunkerweb.io
   ```

3. **Run mock server:**
   ```bash
   pip install flask pyopenssl
   python mock_pro_api.py
   ```

#### Option B: HTTP Proxy with Response Modification

Use tools like `mitmproxy` to intercept and modify API responses.

---

### Method 3: Code Modification (PERMANENT DEBUG MODE)

**Approach:** Modify the validation script to always return pro status.

**File:** `src/common/core/pro/jobs/download-pro-plugins.py`

**Modification 1 - Force Pro Status (Line 142-150):**
```python
# ORIGINAL:
default_metadata = {
    "is_pro": False,
    "pro_license": pro_license_key,
    "pro_expire": None,
    "pro_status": "invalid",
    "pro_overlapped": False,
    "pro_services": 0,
    "non_draft_services": 0,
}

# DEBUG VERSION:
default_metadata = {
    "is_pro": True,  # FORCE ENABLED
    "pro_license": pro_license_key,
    "pro_expire": datetime.now() + timedelta(days=365),  # 1 year from now
    "pro_status": "active",  # FORCE ACTIVE
    "pro_overlapped": False,
    "pro_services": 999,  # Unlimited services
    "non_draft_services": 0,
}
```

**Modification 2 - Skip API Validation (Line 159-203):**
```python
# Add at line 159, before the API call:
if True:  # DEBUG: Always use mock data
    metadata = {
        "is_pro": True,
        "pro_status": "active",
        "pro_expire": datetime.now() + timedelta(days=365),
        "pro_services": 999,
        "pro_overlapped": False,
        "non_draft_services": int(data["service_number"]),
    }
    LOGGER.warning("DEBUG MODE: Using mock pro license data")
else:
    # Original API call code here...
```

**Modification 3 - Always Download Preview Plugins (Line 233):**
```python
# ORIGINAL (Line 233):
if metadata["is_pro"]:

# DEBUG VERSION:
if True:  # DEBUG: Always download plugins
```

**Rebuild after modifications:**
```bash
docker build -f src/all-in-one/Dockerfile -t bunkerweb:debug .
```

---

### Method 4: Environment Variable Override (CLEANEST)

**Approach:** Add a debug environment variable to bypass checks.

**Implementation:**

1. **Modify download-pro-plugins.py** (add at line 127):
   ```python
   # Add debug mode check
   DEBUG_PRO_MODE = getenv("DEBUG_PRO_ENABLED", "").lower() in ("true", "yes", "1")
   
   if DEBUG_PRO_MODE:
       LOGGER.warning("⚠️ DEBUG MODE: Pro features force-enabled via DEBUG_PRO_ENABLED")
       metadata = {
           "is_pro": True,
           "pro_license": "DEBUG-MODE",
           "pro_expire": datetime.now() + timedelta(days=365),
           "pro_status": "active",
           "pro_services": 999,
           "pro_overlapped": False,
           "non_draft_services": int(data["service_number"]),
       }
       db.set_metadata(default_metadata | metadata)
       # Skip to plugin download section
       # ... rest of logic
   ```

2. **Set environment variable:**
   ```bash
   # Docker Compose
   environment:
     - DEBUG_PRO_ENABLED=true
   
   # Kubernetes
   env:
     - name: DEBUG_PRO_ENABLED
       value: "true"
   
   # Linux
   export DEBUG_PRO_ENABLED=true
   ```

---

### Method 5: Use Preview Plugins (NO LICENSE NEEDED)

**Approach:** BunkerWeb provides free preview versions of pro plugins.

**How it works:**
- When no valid license is present, the script downloads from:
  `https://assets.bunkerity.com/bw-pro/preview/v{version}.zip`
- These are limited/demo versions of pro plugins
- Automatically enabled without license

**To ensure preview plugins are used:**
1. Don't set `PRO_LICENSE_KEY`
2. Ensure network access to `assets.bunkerity.com`
3. Check logs for: "only checking if there are new or updated preview versions of Pro plugins"

**Preview plugins are installed to:** `/etc/bunkerweb/pro/plugins/`

---

### Method 6: Force Update Flag (EXISTING FEATURE)

**Approach:** Use the built-in force update mechanism.

**Steps:**

1. **Set force_pro_update in database:**
   ```sql
   UPDATE bw_metadata SET force_pro_update = 1 WHERE id = 1;
   ```

2. **Trigger the job:**
   ```bash
   # Via API
   curl -X POST http://localhost:5000/api/jobs/download-pro-plugins/run
   
   # Via UI
   # Navigate to Jobs page and run "download-pro-plugins"
   ```

**What it does (Line 128-131):**
- Skips daily check limitation
- Bypasses license validation if already pro
- Forces plugin re-download
- Keeps current `is_pro` status

**Note:** This only works if `is_pro` is already `True` in the database.

---

## Pro Plugin Architecture

### Plugin Storage
- **Location:** `/etc/bunkerweb/pro/plugins/`
- **Structure:** Each plugin is a directory with `plugin.json`
- **Format:** Plugins are downloaded as ZIP, extracted, then stored as tar.gz in database

### Plugin Installation Process (Line 69-121)
1. Download ZIP from API or preview endpoint
2. Extract to temp directory: `/var/tmp/bunkerweb/pro/plugins/{uuid}/`
3. Validate `plugin.json` exists
4. Copy to `/etc/bunkerweb/pro/plugins/{plugin_id}/`
5. Set executable permissions (0750) on jobs, bwcli, ui scripts
6. Compress to tar.gz and store in database
7. Update plugin metadata in `bw_plugins` table

### Plugin Types Installed
- Core pro plugins (with valid license)
- Preview plugins (without license)
- Custom plugins (manually uploaded)

---

## UI Integration

### Pro Status Display

**File:** `src/ui/app/routes/pro.py`

The UI reads pro status from database metadata:
```python
metadata = DB.get_metadata()
# metadata["is_pro"] determines UI display
# metadata["pro_expire"] shows expiration date
# metadata["pro_status"] shows status badge
```

**Template:** `src/ui/app/templates/pro.html`
- Shows "PRO version" badge if `is_pro == True`
- Displays license expiration countdown
- Shows service limits and overlapping warnings

### Setup Wizard Integration

**File:** `src/ui/app/routes/setup.py` (Line 109-111)

During setup, license key can be configured:
```python
if not pro_license_key and request.form.get("pro_license_key", ""):
    global_config = DB.get_config(global_only=True)
    BW_CONFIG.edit_global_conf(global_config | {"PRO_LICENSE_KEY": request.form["pro_license_key"]}, check_changes=False)
```

---

## Security Considerations

### License Validation Security
1. **Bearer Token Authentication:** License key sent as `Authorization: Bearer {key}`
2. **System Fingerprinting:** Integration, version, OS info sent with validation
3. **Service Counting:** Validates service limits against license tier
4. **Daily Checks:** Re-validates license every 24 hours
5. **Cleanup on Revocation:** Removes pro plugins if license becomes invalid

### Bypass Detection
The system includes several anti-bypass mechanisms:
- Daily re-validation overwrites manual database changes
- API returns "clean" action to force plugin removal
- Plugin checksums verified on installation
- Database metadata tracks last check timestamp

### For Debug Purposes
When bypassing for debugging:
- **Disable daily checks:** Set `last_pro_check` to far future date
- **Block API access:** Firewall rules to prevent validation
- **Use offline mode:** Disconnect from network during testing

---

## Recommended Debug Workflow

### For Local Development:

1. **Initial Setup:**
   ```sql
   UPDATE bw_metadata 
   SET is_pro = 1,
       pro_status = 'active',
       pro_expire = '2099-12-31',
       pro_services = 999,
       last_pro_check = '2099-12-31'
   WHERE id = 1;
   ```

2. **Block API Validation:**
   ```bash
   # Add to /etc/hosts
   127.0.0.1 api.bunkerweb.io
   ```

3. **Use Preview Plugins:**
   - Let the system download preview plugins naturally
   - Or manually place pro plugins in `/etc/bunkerweb/pro/plugins/`

4. **Monitor Logs:**
   ```bash
   tail -f /var/log/bunkerweb/jobs.log | grep PRO
   ```

### For Production Testing:

1. **Use Environment Variable Method** (Method 4)
2. **Set up Mock API Server** (Method 2)
3. **Document all changes** for reversal
4. **Never commit debug code** to production branches

---

## Plugin Development

### Creating Custom Pro Plugins

If you want to develop your own pro plugins:

1. **Plugin Structure:**
   ```
   my-pro-plugin/
   ├── plugin.json          # Metadata
   ├── jobs/                # Scheduled jobs
   ├── ui/                  # UI components
   ├── bwcli/               # CLI commands
   └── README.md            # Documentation
   ```

2. **plugin.json Format:**
   ```json
   {
     "id": "my-pro-plugin",
     "name": "My Pro Plugin",
     "description": "Custom pro plugin",
     "version": "1.0.0",
     "stream": "no",
     "settings": {},
     "jobs": []
   }
   ```

3. **Manual Installation:**
   ```bash
   cp -r my-pro-plugin /etc/bunkerweb/pro/plugins/
   chmod 750 /etc/bunkerweb/pro/plugins/my-pro-plugin/jobs/*
   ```

4. **Register in Database:**
   ```sql
   INSERT INTO bw_plugins (id, name, description, version, type, method)
   VALUES ('my-pro-plugin', 'My Pro Plugin', 'Custom', '1.0.0', 'pro', 'manual');
   ```

---

## Troubleshooting

### Issue: Pro status reverts to false after restart

**Cause:** Daily license check runs and overwrites database

**Solution:**
```sql
-- Set last check to far future
UPDATE bw_metadata SET last_pro_check = '2099-12-31' WHERE id = 1;

-- OR block API access
echo "127.0.0.1 api.bunkerweb.io" >> /etc/hosts
```

### Issue: Plugins not downloading

**Cause:** Network connectivity or API issues

**Solution:**
```bash
# Check connectivity
curl -v https://api.bunkerweb.io/pro/status

# Check preview endpoint
curl -v https://assets.bunkerity.com/bw-pro/preview/v1.6.7.zip

# Force manual download
wget https://assets.bunkerity.com/bw-pro/preview/v1.6.7.zip
unzip v1.6.7.zip -d /etc/bunkerweb/pro/plugins/
```

### Issue: Database is read-only

**Cause:** Database in read-only mode

**Solution:**
```python
# Check in UI or via API
DB.readonly  # Should be False

# If true, check database permissions and connection
```

### Issue: Plugins installed but not active

**Cause:** Plugin metadata not in database

**Solution:**
```bash
# Trigger plugin reload
curl -X POST http://localhost:5000/api/jobs/download-pro-plugins/run

# Or set flag
UPDATE bw_metadata SET pro_plugins_changed = 1 WHERE id = 1;
```

---

## API Endpoints Reference

### License Validation
```
POST https://api.bunkerweb.io/pro/status
Headers:
  Authorization: Bearer {LICENSE_KEY}
  User-Agent: BunkerWeb/{VERSION}
Body:
  {
    "integration": "Docker|Linux|Kubernetes|Swarm|Autoconf",
    "version": "1.6.7",
    "os": "Linux x86_64",
    "service_number": "5"
  }
Response:
  {
    "data": {
      "pro_status": "active|invalid|expired|suspended",
      "pro_expire": "2025-12-31",
      "pro_services": 10,
      "is_pro": true,
      "pro_overlapped": false
    }
  }
```

### Plugin Download
```
POST https://api.bunkerweb.io/pro/download
Headers:
  Authorization: Bearer {LICENSE_KEY}
  User-Agent: BunkerWeb/{VERSION}
Body: (same as above)
Response: application/octet-stream (ZIP file)
```

### Preview Plugins
```
GET https://assets.bunkerity.com/bw-pro/preview/v{VERSION}.zip
Response: application/zip
```

---

## Conclusion

**For Debug Purposes, Recommended Approach:**

1. **Quick Test:** Use Method 1 (Direct Database Manipulation)
2. **Development:** Use Method 4 (Environment Variable) + Method 2 (Mock Server)
3. **CI/CD:** Use Method 3 (Code Modification) in debug builds only

**Key Takeaway:**
The pro feature system is controlled by a single database flag (`is_pro`) that can be easily manipulated for debugging. The main challenge is preventing the daily validation job from overwriting your changes, which can be solved by:
- Setting `last_pro_check` to a far future date
- Blocking network access to `api.bunkerweb.io`
- Using the `force_pro_update` flag strategically
- Modifying the validation script to skip API calls

**Remember:** These methods are for debugging and development only. Never use them in production without proper licensing.
