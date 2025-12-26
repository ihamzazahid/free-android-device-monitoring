# 📱 Free Android Device Monitoring

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](http://makeapullrequest.com)

Monitor Android devices remotely with Prometheus & Grafana. No root required!

## 🚀 Quick Start

### Step 1: Android Setup
1. Install [Termux](https://f-droid.org/en/packages/com.termux/)
2. Run in Termux:
<pre>
   curl -sL https://raw.githubusercontent.com/ihamzazahid/free-android-device-monitoring/main/android-agent/setup_android.sh | bash
  </pre>
4. Note IP address shown at end
5. Set SSH password when prompted

### Step 2: Windows Setup
1. Run PowerShell as Administrator:
   <pre>
   irm https://raw.githubusercontent.com/ihamzazahid/free-android-device-monitoring/main/windows-client/setup_windows.ps1 | iex
   </pre>
3. Install [Prometheus](https://prometheus.io/download/)
4. Install [Grafana](https://grafana.com/grafana/download)

### Step 3: Create SSH Tunnel
Open Git Bash/PowerShell:
<pre>
ssh -N -L 19100:localhost:9100 termux@YOUR_ANDROID_IP -p 8022
</pre>
Keep this terminal open!

### Step 4: Configure Prometheus
Edit `prometheus.yml` and add:
<pre>
 job_name: 'android-devices'
 static_configs:
  targets: ['localhost:19100']
</pre>

### Step 5: Import Grafana Dashboard
1. Open <pre>http://localhost:3000</pre>
2. Login (admin/admin)
3. Click **+ → Import**
4. Paste dashboard JSON from examples folder
5. Select Prometheus datasource
6. Click **Import**

## 📊 Metrics Collected
- `android_cpu_usage_percent` - CPU usage
- `android_memory_total_mb` - Total memory
- `android_memory_available_mb` - Available memory  
- `android_storage_free_gb` - Free storage
- `up{job="android-devices"}` - Device status

## 🛠️ Project Structure
<pre>
android-agent/          # Android scripts
├── android_exporter.py
└── setup_android.sh
windows-client/         # Windows scripts
└── setup_windows.ps1
examples/              # Config examples
├── prometheus.yml
└── grafana-dashboard.json
</pre>


## 🔧 Troubleshooting
- **SSH connection refused**: Check Android is on same Wi-Fi
- **Port 19100 in use**: Kill existing SSH process
- **No metrics**: Check tunnel is running
- **Prometheus can't scrape**: Test with `curl http://localhost:19100/metrics`

## 🤝 Contributing
Contributions welcome! Open issues or PRs.

## 📝 License
MIT License
