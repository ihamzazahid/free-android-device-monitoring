#!/data/data/com.termux/files/usr/bin/bash
set -e

echo "📱 Android Push Monitoring Setup (Cloudflare Tunnel)"
echo "==================================================="

# ---------------- CONFIGURATION ----------------
SCRIPTS_DIR="$HOME/.scripts"
PY_FILE="$SCRIPTS_DIR/android_exporter.py"
CONFIG_FILE="$HOME/.android_monitor.conf"
LOG_FILE="$SCRIPTS_DIR/android_exporter.log"
TUNNEL_URL="dated-finding-troy-diverse.trycloudflare.com"  # <--- Replace with your tunnel URL
INTERVAL=15
TOP_N_PROCESSES=5

# ---------------- DEVICE IDENTIFIER ----------------
RAND_SUFFIX=$((RANDOM%10000))
DEVICE_NAME="$(hostname)_$RAND_SUFFIX"
echo "$DEVICE_NAME" > "$CONFIG_FILE"
echo "📱 Device identifier: $DEVICE_NAME"

# ---------------- UPDATE SYSTEM ----------------
echo "🔄 Updating Termux packages..."
pkg update -y && pkg upgrade -y

# ---------------- INSTALL DEPENDENCIES ----------------
echo "📦 Installing dependencies..."
pkg install -y python curl git termux-api
pip install --upgrade prometheus-client psutil requests

# ---------------- CLEANUP PREVIOUS INSTALL ----------------
echo "🧹 Cleaning up old scripts..."
pkill -f android_exporter.py 2>/dev/null || true
rm -rf "$SCRIPTS_DIR"
mkdir -p "$SCRIPTS_DIR"

# ---------------- FETCH PYTHON EXPORTER ----------------
echo "📥 Downloading android_exporter.py..."
curl -sL https://raw.githubusercontent.com/ihamzazahid/free-android-device-monitoring/main/android-agent/android_exporter.py -o "$PY_FILE"
chmod +x "$PY_FILE"

# ---------------- MANAGEMENT SCRIPTS ----------------
# Start
cat > "$SCRIPTS_DIR/start_monitoring.sh" << EOF
#!/data/data/com.termux/files/usr/bin/bash
cd $SCRIPTS_DIR
nohup python android_exporter.py >> android_exporter.log 2>&1 &
PID=\$!
echo \$PID > android_exporter.pid
echo "✅ Monitoring started (PID: \$PID)"
EOF

# Stop
cat > "$SCRIPTS_DIR/stop_monitoring.sh" << EOF
#!/data/data/com.termux/files/usr/bin/bash
pkill -f android_exporter.py 2>/dev/null
rm -f $SCRIPTS_DIR/android_exporter.pid 2>/dev/null
echo "✅ Monitoring stopped"
EOF

# Status
cat > "$SCRIPTS_DIR/check_status.sh" << EOF
#!/data/data/com.termux/files/usr/bin/bash
if [ -f $SCRIPTS_DIR/android_exporter.pid ]; then
    PID=\$(cat $SCRIPTS_DIR/android_exporter.pid)
    if ps -p \$PID >/dev/null 2>&1; then
        echo "✅ Pusher running (PID: \$PID)"
    else
        echo "❌ Pusher not running (stale PID)"
    fi
else
    echo "❌ Pusher not running"
fi
EOF

chmod +x "$SCRIPTS_DIR"/*.sh

# ---------------- START MONITORING ----------------
echo "🚀 Starting monitoring automatically..."
"$SCRIPTS_DIR/start_monitoring.sh"

echo ""
echo "✅ SETUP COMPLETE!"
echo "📄 Logs: tail -f $LOG_FILE"
echo "📋 Management Commands:"
echo "   Start:  $SCRIPTS_DIR/start_monitoring.sh"
echo "   Stop:   $SCRIPTS_DIR/stop_monitoring.sh"
echo "   Status: $SCRIPTS_DIR/check_status.sh"
