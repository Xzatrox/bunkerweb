# BunkerWeb External Network Communications Analysis

## Executive Summary

BunkerWeb makes several types of external network calls. This document catalogs all outbound connections found in the source code and provides methods to disable them for complete LAN isolation.

---

## 🔴 Critical External Communications

### 1. **Anonymous Telemetry Reporting**
- **File**: [`src/common/core/misc/jobs/anonymous-report.py`](src/common/core/misc/jobs/anonymous-report.py:167)
- **Endpoint**: `https://api.bunkerweb.io/data`
- **Frequency**: Daily
- **Data Sent**: 
  - Version, integration type, database info
  - Service count, plugin list (IDs/versions only)
  - Non-default settings (names only, no values)
  - UI usage statistics
  - OS information
- **Control**: Set `SEND_ANONYMOUS_REPORT=no` environment variable
- **Default**: **ENABLED** (sends by default)

### 2. **Pro License Validation**
- **File**: [`src/common/core/pro/jobs/download-pro-plugins.py`](src/common/core/pro/jobs/download-pro-plugins.py:166)
- **Endpoints**: 
  - `https://api.bunkerweb.io/pro/status` (license check)
  - `https://api.bunkerweb.io/pro/download` (plugin download)
  - `https://assets.bunkerity.com/bw-pro/preview` (preview plugins)
- **Frequency**: Daily
- **Data Sent**: Integration, version, OS, service count, license key
- **Control**: 
  - Set `BYPASS_PRO_LICENSE_CHECK=true` (with our patch)
  - Or disable the job entirely
- **Default**: **ENABLED** if `PRO_LICENSE_KEY` is set

### 3. **BunkerNet Threat Intelligence**
- **File**: [`src/common/core/bunkernet/jobs/bunkernet.py`](src/common/core/bunkernet/jobs/bunkernet.py:29)
- **Endpoint**: `https://api.bunkerweb.io` (configurable via `BUNKERNET_SERVER`)
- **Endpoints Used**:
  - `/register` - Register instance
  - `/ping` - Keep-alive
  - `/db` - Download threat data
  - `/report` - Send attack reports
- **Frequency**: Periodic (based on configuration)
- **Data Sent**: Integration, version, OS, instance ID, attack reports
- **Control**: Don't enable BunkerNet feature
- **Default**: **DISABLED** (opt-in feature)

### 4. **Update Checker**
- **File**: [`src/common/core/jobs/jobs/update-check.py`](src/common/core/jobs/jobs/update-check.py:44)
- **Endpoint**: `https://api.github.com/repos/bunkerity/bunkerweb/releases`
- **Frequency**: Periodic (job-based)
- **Data Sent**: User-Agent header only
- **Control**: Disable the job or block GitHub API
- **Default**: **ENABLED**

---

## 🟡 Feature-Based External Communications

### 5. **MaxMind GeoIP Database Updates**
- **Files**: 
  - [`src/common/core/jobs/jobs/mmdb-country.py`](src/common/core/jobs/jobs/mmdb-country.py:88)
  - [`src/common/core/jobs/jobs/mmdb-asn.py`](src/common/core/jobs/jobs/mmdb-asn.py:88)
- **Endpoints**:
  - `https://db-ip.com/db/download/ip-to-country-lite`
  - `https://db-ip.com/db/download/ip-to-asn-lite`
  - `https://download.db-ip.com/free/dbip-*.mmdb.gz`
- **Frequency**: Monthly
- **Control**: Disable jobs or use local MMDB files
- **Default**: **ENABLED** if GeoIP features are used

### 6. **Blacklist/Whitelist/Greylist Downloads**
- **Files**:
  - [`src/common/core/blacklist/jobs/blacklist-download.py`](src/common/core/blacklist/jobs/blacklist-download.py:62)
  - [`src/common/core/whitelist/jobs/whitelist-download.py`](src/common/core/whitelist/jobs/whitelist-download.py:1)
  - [`src/common/core/greylist/jobs/greylist-download.py`](src/common/core/greylist/jobs/greylist-download.py:1)
  - [`src/common/core/dnsbl/jobs/dnsbl-download.py`](src/common/core/dnsbl/jobs/dnsbl-download.py:1)
- **Endpoints**: Various community lists from GitHub, etc.
  - `https://raw.githubusercontent.com/duggytuxy/Data-Shield_IPv4_Blocklist/...`
  - `https://www.dan.me.uk/torlist/?exit`
  - `https://raw.githubusercontent.com/mitchellkrogza/nginx-ultimate-bad-bot-blocker/...`
- **Frequency**: Periodic (when lists are configured)
- **Control**: Don't configure external lists
- **Default**: **DISABLED** (only if configured)

### 7. **ModSecurity Core Rule Set Updates**
- **Files**:
  - [`src/common/core/modsecurity/jobs/coreruleset-nightly.py`](src/common/core/modsecurity/jobs/coreruleset-nightly.py:61)
  - [`src/common/core/modsecurity/jobs/download-crs-plugins.py`](src/common/core/modsecurity/jobs/download-crs-plugins.py:204)
- **Endpoints**:
  - `https://github.com/coreruleset/coreruleset/releases/tag/nightly`
  - `https://github.com/coreruleset/coreruleset/archive/refs/tags/nightly.tar.gz`
  - `https://raw.githubusercontent.com/coreruleset/plugin-registry/...`
- **Frequency**: When nightly updates are enabled
- **Control**: Don't enable nightly CRS updates
- **Default**: **DISABLED** (opt-in feature)

### 8. **Let's Encrypt Certificate Issuance**
- **File**: [`src/common/core/letsencrypt/jobs/certbot-new.py`](src/common/core/letsencrypt/jobs/certbot-new.py:166)
- **Endpoints**:
  - `https://publicsuffix.org/list/public_suffix_list.dat` (PSL download)
  - Let's Encrypt ACME servers (via certbot)
  - DNS provider APIs (Google, Cloudflare, etc.)
- **Frequency**: Certificate renewal cycles
- **Control**: Use manual certificates instead of Let's Encrypt
- **Default**: **DISABLED** (only when Let's Encrypt is configured)

### 9. **Robots.txt AI Bot Lists**
- **Files**:
  - [`src/common/core/robotstxt/jobs/robots-txt-download.py`](src/common/core/robotstxt/jobs/robots-txt-download.py:25)
  - [`src/common/core/robotstxt/jobs/robots-txt-darkvisitors.py`](src/common/core/robotstxt/jobs/robots-txt-darkvisitors.py:24)
- **Endpoints**:
  - `https://raw.githubusercontent.com/ai-robots-txt/ai.robots.txt/...`
  - `https://raw.githubusercontent.com/danielmiessler/RobotsDisallowed/...`
  - `https://api.darkvisitors.com/robots-txts`
- **Frequency**: Periodic updates
- **Control**: Don't configure these features
- **Default**: **DISABLED** (opt-in feature)

### 10. **External Plugin Downloads**
- **File**: [`src/common/core/misc/jobs/download-plugins.py`](src/common/core/misc/jobs/download-plugins.py:31)
- **Endpoints**: User-configured plugin repositories (GitHub, etc.)
- **Frequency**: When external plugins are configured
- **Control**: Don't install external plugins
- **Default**: **DISABLED** (only when configured)

### 11. **Real IP Provider Lists**
- **File**: [`src/common/core/realip/jobs/realip-download.py`](src/common/core/realip/jobs/realip-download.py:16)
- **Endpoints**: CDN/proxy provider IP lists (Cloudflare, etc.)
- **Frequency**: Periodic updates
- **Control**: Don't configure external real IP lists
- **Default**: **DISABLED** (only when configured)

---

## 🟢 UI-Only External Communications

### 12. **Web UI External Resources**
- **File**: [`src/ui/main.py`](src/ui/main.py:1096)
- **Endpoints** (CSP allowed):
  - `https://www.bunkerweb.io` (documentation links)
  - `https://assets.bunkerity.com` (assets)
  - `https://api.github.com` (release info in UI)
  - `https://*.tile.openstreetmap.org` (map tiles if used)
- **Frequency**: User-initiated (browser loads)
- **Control**: These are browser-side, can be blocked with firewall
- **Default**: **ENABLED** (CSP allows these domains)

### 13. **UI Update Check**
- **File**: [`src/ui/app/utils.py`](src/ui/app/utils.py:278)
- **Endpoint**: `https://api.github.com/repos/bunkerity/bunkerweb/releases`
- **Frequency**: When UI checks for updates
- **Control**: Firewall block or disable UI feature
- **Default**: **ENABLED** in UI

---

## 🔒 Complete LAN Isolation Configuration

### Method 1: Environment Variables (Recommended)

Add these to your BunkerWeb environment configuration:

```bash
# Disable anonymous telemetry
SEND_ANONYMOUS_REPORT=no

# Bypass Pro license check (requires patch)
BYPASS_PRO_LICENSE_CHECK=true

# Don't enable BunkerNet
# (just don't set USE_BUNKERNET=yes)

# Don't configure external lists
# (don't set BLACKLIST_*, WHITELIST_*, etc. with URLs)
```

### Method 2: Disable Scheduler Jobs

Rename or delete job files to prevent execution:

```bash
# In LXC container
pct exec 108 -- bash -c '
cd /usr/share/bunkerweb/deps/python/jobs

# Disable telemetry
mv anonymous-report.py anonymous-report.py.disabled

# Disable update checker  
mv update-check.py update-check.py.disabled

# Disable Pro license check (if not using our patch)
mv download-pro-plugins.py download-pro-plugins.py.disabled

# Disable MMDB updates (use local files instead)
mv mmdb-country.py mmdb-country.py.disabled
mv mmdb-asn.py mmdb-asn.py.disabled
'
```

### Method 3: Firewall Rules (Defense in Depth)

Block all outbound connections from BunkerWeb:

```bash
# On Proxmox host or in LXC container
iptables -A OUTPUT -m owner --uid-owner nginx -j REJECT
iptables -A OUTPUT -m owner --uid-owner root -p tcp --dport 443 -j REJECT
iptables -A OUTPUT -m owner --uid-owner root -p tcp --dport 80 -j REJECT

# Or use nftables
nft add rule inet filter output meta skuid nginx reject
```

### Method 4: DNS Blackhole

Add to `/etc/hosts` in the container:

```bash
127.0.0.1 api.bunkerweb.io
127.0.0.1 assets.bunkerity.com
127.0.0.1 api.github.com
127.0.0.1 db-ip.com
127.0.0.1 download.db-ip.com
127.0.0.1 raw.githubusercontent.com
```

---

## ✅ Verification Steps

After applying isolation measures:

1. **Check for outbound connections:**
   ```bash
   pct exec 108 -- netstat -tupn | grep ESTABLISHED
   ```

2. **Monitor DNS queries:**
   ```bash
   pct exec 108 -- tcpdump -i any port 53
   ```

3. **Check scheduler logs:**
   ```bash
   pct exec 108 -- journalctl -u bunkerweb-scheduler -n 100 --no-pager | grep -i "http\|api\|download"
   ```

4. **Verify anonymous report is disabled:**
   ```bash
   pct exec 108 -- grep -r "SEND_ANONYMOUS_REPORT" /etc/bunkerweb/ /var/tmp/bunkerweb/
   ```

---

## 📊 Privacy Impact Assessment

### Data Sent by Default (Without Configuration Changes)

1. **Anonymous Report** (Daily):
   - ✅ Version number
   - ✅ Integration type (Docker/Linux/K8s)
   - ✅ Database type and version
   - ✅ Number of services
   - ✅ Plugin IDs and versions
   - ✅ OS information
   - ❌ NO IP addresses
   - ❌ NO domain names
   - ❌ NO configuration values
   - ❌ NO user data

2. **Update Check** (Periodic):
   - ✅ User-Agent: "BunkerWeb"
   - ❌ NO installation-specific data

3. **Pro License Check** (If key provided):
   - ✅ License key
   - ✅ Version, OS, integration
   - ✅ Service count

### Recommendation

For **complete LAN isolation**, apply **all four methods** above:
1. Set environment variables
2. Disable unnecessary jobs
3. Apply firewall rules
4. Use DNS blackhole

This ensures zero external communication even if a job accidentally runs or a configuration is missed.

---

## 🛠️ Automated Isolation Script

See [`disable_external_communications.sh`](disable_external_communications.sh) for a complete automation script.
