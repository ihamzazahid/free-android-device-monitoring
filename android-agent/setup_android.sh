#!/data/data/com.termux/files/usr/bin/bash
set -e

echo "📱 Android Push Monitoring Setup (Cloudflare Tunnel)"
echo "==================================================="

# ---------------- Configuration ----------------
SCRIPTS_DIR="$HOME/.scripts"
CONFIG_FILE="$HOME/.android_monitor.conf"
LOG_FILE="$SCRIPTS_DIR/android_pusher.log"

# ⚠️ IMPORTANT: Replace with your Cloudflare Tunnel URL
TUNNEL_URL="dated-finding-troy-diverse.trycloudflare.com"

echo "🔧 Will push metrics to Cloudflare Tunnel at: $TUNNEL_URL"
echo "   (Make sure Prometheus PushGateway is running via tunnel on your laptop)"

# ---------------- Update system ----------------
echo "🔄 Updating system packages..."
pkg update -y && pkg upgrade -y

# ---------------- Install dependencies ----------------
echo "📦 Installing dependencies..."
pkg install -y python curl git
pip install --upgrade prometheus-client psutil requests

# ---------------- Cleanup previous installations ----------------
echo "🧹 Cleaning up previous installations..."
pkill -f android_pusher.py 2>/dev/null || true
rm -rf $SCRIPTS_DIR
mkdir -p $SCRIPTS_DIR

# ---------------- Get device info ----------------
DEVICE_NAME=$(hostname)
echo "📱 Device name: $DEVICE_NAME"

# ---------------- Download/Update Python exporter ----------------
cd $SCRIPTS_DIR
echo "⬇️ Downloading Android Prometheus pusher..."

if curl -sL https://raw.githubusercontent.com/ihamzazahid/free-android-device-monitoring/main/android-agent/android_pusher.py -o android_pusher.py; then
    echo "✅ Downloaded original pusher script"
else
    echo "⚠️ Could not download script, creating local version..."
    cat > android_pusher.py << EOF
#!/usr/bin/env python3
import time, psutil
from prometheus_client import CollectorRegistry, Gauge, Counter, push_to_gateway

PUSHGATEWAY = "$TUNNEL_URL"
JOB_NAME = f"android_{DEVICE_NAME}"
INTERVAL = 15
TOP_N_PROCESSES = 5

registry = CollectorRegistry()
cpu = Gauge("android_cpu_percent", "CPU usage percent", registry=registry)
mem = Gauge("android_memory_percent", "Memory usage percent", registry=registry)

while True:
    cpu.set(psutil.cpu_percent())
    mem.set(psutil.virtual_memory().percent)
    try:
        push_to_gateway(PUSHGATEWAY, job=JOB_NAME, registry=registry)
        print(f"✅ Pushed metrics to {PUSHGATEWAY} at {time.ctime()}")
    except Exception as e:
        print(f"⚠️ Push failed: {e}")
    time.sleep(INTERVAL)
EOF
fi

chmod +x android_pusher.py

# ---------------- Create config file ----------------
cat > $CONFIG_FILE << EOF
# Android Monitor Configuration
PUSHGATEWAY=$TUNNEL_URL
JOB_NAME=android_${DEVICE_NAME}
PUSH_INTERVAL=15
DEVICE_NAME=$DEVICE_NAME
SETUP_DATE=$(date)
EOF

# ---------------- Management scripts ----------------
# Start
cat > $SCRIPTS_DIR/start_monitoring.sh << EOF
#!/data/data/com.termux/files/usr/bin/bash
cd $SCRIPTS_DIR
nohup python android_pusher.py >> android_pusher.log 2>&1 &
PID=\$!
echo \$PID > android_pusher.pid
echo "✅ Monitoring started (PID: \$PID)"
EOF

# Stop
cat > $SCRIPTS_DIR/stop_monitoring.sh << EOF
#!/data/data/com.termux/files/usr/bin/bash
pkill -f android_pusher.py 2>/dev/null
rm -f $SCRIPTS_DIR/android_pusher.pid 2>/dev/null
echo "✅ Monitoring stopped"
EOF

# Status
cat > $SCRIPTS_DIR/check_status.sh << EOF
#!/data/data/com.termux/files/usr/bin/bash
if [ -f $SCRIPTS_DIR/android_pusher.pid ]; then
    PID=\$(cat $SCRIPTS_DIR/android_pusher.pid)
    if ps -p \$PID >/dev/null 2>&1; then
        echo "✅ Pusher running (PID: \$PID)"
    else
        echo "❌ Pusher not running (stale PID)"
    fi
else
    echo "❌ Pusher not running"
fi
EOF

chmod +x $SCRIPTS_DIR/*.sh

echo ""
echo "✅ SETUP COMPLETE!"
echo "Use $SCRIPTS_DIR/start_monitoring.sh to start pushing metrics"
