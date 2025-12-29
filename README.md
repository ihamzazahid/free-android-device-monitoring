# 📱 Free Android Device Monitoring

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](http://makeapullrequest.com)

Monitor Android devices remotely using **Termux**, **Termux API**, **Python**, **Cloudflare Tunnel**, **Prometheus Pushgateway**, and **Grafana**.  
No root is required. Fully crash-proof and safe on all devices.

---

## 🛠️ Technologies Used

- **Termux** – Android terminal environment  
- **Termux API** – Access battery, storage, WiFi, mobile signal, and other device stats  
- **Python 3** – Metrics exporter (`android_exporter.py`)  
- **Prometheus Pushgateway** – Devices push metrics for Prometheus scraping  
- **Cloudflare Tunnel** – Secure remote access (optional NAT traversal)  
- **SSH / Port Forwarding** – Optional for local Prometheus  
- **Git / curl** – Quick setup automation  

---

## 🚀 Quick Start

### Step 1: Android Setup
1. Install [Termux](https://f-droid.org/en/packages/com.termux/)  
2. Open Termux shell  
3. Run the setup script:
<pre>
   curl -sL https://raw.githubusercontent.com/ihamzazahid/free-android-device-monitoring/main/android-agent/setup_android.sh | bash
  </pre>
4. Grant Termux API permissions when prompted
5. The setup script will:
   - Create .scripts/android_exporter.py
   - Create management scripts (start_monitoring.sh, stop_monitoring.sh, check_status.sh)
   - Start monitoring automatically   

6. Logs can be viewed with:
<pre> tail -f ~/.scripts/android_exporter.log
</pre>

### Step 2: Push Metrics to Pushgateway
The setup script uses Cloudflare Tunnel for secure access:
- Cloudflare DNS example: dated-finding-troy-diverse.trycloudflare.com
- Metrics are pushed from Android → Cloudflare Tunnel → Pushgateway

### Step 3: Configure Prometheus
Edit `prometheus.yml` and add:
<pre>- job_name: 'pushgateway'
  honor_labels: true
  static_configs:
    - targets: ['localhost:9091']
</pre>

Prometheus now collects all Android device metrics via the Pushgateway.

### Step 4: Import Grafana Dashboard
1. Open <pre>http://localhost:3000</pre>
2. Login (admin/admin)
3. Click **+ → Import**
4. Paste dashboard JSON from examples folder
5. Select Prometheus datasource
6. Click **Import**

## 🔧 Management Commands (on Android Termux)
<pre>~/.scripts/start_monitoring.sh   # Start metrics collection
~/.scripts/stop_monitoring.sh    # Stop metrics collection
~/.scripts/check_status.sh       # Check if exporter is running
</pre>

## 📊 Metrics Collected
All metrics come from Termux API, no root required:
- Device Info: android_device_info{device_id,brand,model,android_version}
- CPU: android_cpu_percent
- Memory: android_memory_total_mb, android_memory_used_mb, android_memory_percent
- Storage: android_storage_total_gb, android_storage_free_gb
- Battery: android_battery_percent, android_battery_charging, android_battery_temperature_c
- Network: android_network_type{type="wifi|mobile"}, android_cell_signal_dbm
- Network Traffic: android_network_bytes_sent_total, android_network_bytes_recv_total
- Processes / Uptime: android_process_count, android_uptime_seconds

## 🛠️ Project Structure
<pre>
free-android-device-monitoring/
├── README.md
├── LICENSE
├── .gitignore
├── android-agent/
│   ├── android_exporter.py    # Python Termux API exporter
│   └── setup_android.sh       # Setup script
├── examples/
│   ├── prometheus.yml
│   └── grafana-dashboard.json

</pre>

## 🌐 Workflow Diagram
<pre> 
Android Device (Termux API)
         │
         ▼
Cloudflare Tunnel
         │
         ▼
Pushgateway (Windows / Linux)
         │
         ▼
Prometheus → Grafana Dashboard

</pre>

## 🔧 Troubleshooting
- No metrics: Ensure android_exporter.py is running and Termux API permissions granted
- Pushgateway unreachable: Ensure Cloudflare Tunnel is active and DNS resolves
- Prometheus scrape fails: Test with:
<pre>curl http://localhost:9091/metrics
</pre>
- Logs: Check with:
<pre>tail -f ~/.scripts/android_exporter.log</pre>

## 🤝 Contributing
Open issues or submit PRs to improve metrics collection, dashboards, or setup automation.
## 📝 License
MIT License
