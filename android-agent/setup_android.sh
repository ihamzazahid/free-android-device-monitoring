#!/data/data/com.termux/files/usr/bin/bash
set -e

echo "📱 Android Exporter Setup (Termux + Prometheus)"
echo "================================================"

# ---------------- CONFIG ----------------
SCRIPTS_DIR="$HOME/.scripts"
REPO_DIR="$SCRIPTS_DIR/android-agent"
LOG_FILE="$SCRIPTS_DIR/android_exporter.log"
TUNNEL_URL="dated-finding-troy-diverse.trycloudflare.com" # Replace your URL
INTERVAL=15

# ---------------- UPDATE SYSTEM ----------------
echo "🔄 Updating Termux packages..."
pkg update -y && pkg upgrade -y

# ---------------- INSTALL DEPENDENCIES ----------------
echo "📦 Installing dependencies..."
pkg install -y python git termux-api
pip install --upgrade prometheus-client psutil requests

# ---------------- CLEANUP PREVIOUS INSTALL ----------------
echo "🧹 Cleaning up old scripts..."
pkill -f android_exporter.py 2>/dev/null || true
rm -rf $REPO_DIR
mkdir -p $REPO_DIR

# ---------------- CLONE PYTHON EXPORTER ----------------
echo "📥 Cloning Python exporter..."
git clone https://github.com/ihamzazahid/free-android-device-monitoring.git $SCRIPTS_DIR/tmp_repo

# Move only the android-agent folder
mv $SCRIPTS_DIR/tmp_repo/android-agent $REPO_DIR
rm -rf $SCRIPTS_DIR/tmp_repo

chmod +x $REPO_DIR/*.py

# ---------------- MANAGEMENT SCRIPTS ----------------
# Start
cat > $SCRIPTS_DIR/start_exporter.sh << EOF
#!/data/data/com.termux/files/usr/bin/bash
cd $REPO_DIR
nohup python android_exporter.py >> $LOG_FILE 2>&1 &
PID=\$!
echo \$PID > $SCRIPTS_DIR/android_exporter.pid
echo "✅ Exporter started (PID: \$PID)"
EOF

# Stop
cat > $SCRIPTS_DIR/stop_exporter.sh << EOF
#!/data/data/com.termux/files/usr/bin/bash
pkill -f android_exporter.py 2>/dev/null
rm -f $SCRIPTS_DIR/android_exporter.pid 2>/dev/null
echo "✅ Exporter stopped"
EOF

# Status
cat > $SCRIPTS_DIR/status_exporter.sh << EOF
#!/data/data/com.termux/files/usr/bin/bash
if [ -f $SCRIPTS_DIR/android_exporter.pid ]; then
    PID=\$(cat $SCRIPTS_DIR/android_exporter.pid)
    if ps -p \$PID >/dev/null 2>&1; then
        echo "✅ Exporter running (PID: \$PID)"
    else
        echo "❌ Exporter not running (stale PID)"
    fi
else
    echo "❌ Exporter not running"
fi
EOF

chmod +x $SCRIPTS_DIR/*.sh

# ---------------- START EXPORTER ----------------
echo "🚀 Starting exporter automatically..."
$SCRIPTS_DIR/start_exporter.sh

echo ""
echo "✅ SETUP COMPLETE!"
echo "📄 Logs: tail -f $LOG_FILE"
echo "📋 Management commands:"
echo "   Start:  $SCRIPTS_DIR/start_exporter.sh"
echo "   Stop:   $SCRIPTS_DIR/stop_exporter.sh"
echo "   Status: $SCRIPTS_DIR/status_exporter.sh"
