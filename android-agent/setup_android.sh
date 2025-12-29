#!/data/data/com.termux/files/usr/bin/bash
set -e

echo "📱 Android Push Monitoring Setup (Full Exporter)"
echo "================================"

# ---------------- Configuration ----------------
TS_DIR="$HOME/.tailscale"
SCRIPTS_DIR="$HOME/.scripts"
CONFIG_FILE="$HOME/.android_monitor.conf"
LOG_FILE="$SCRIPTS_DIR/android_pusher.log"
# ⬇️ HARDCODED AUTH KEY ⬇️
AUTH_KEY="tskey-auth-kBg5XdeVa221CNTRL-VZmDmYoLpbcsgU6YcRrdbcaNoDT4C6yrH"

# ---------------- Update system ----------------
echo "🔄 Updating system packages..."
pkg update -y && pkg upgrade -y

# ---------------- Install dependencies ----------------
echo "📦 Installing dependencies..."
pkg install -y python curl git tar
pip install --upgrade prometheus-client psutil requests

# ---------------- Cleanup previous installations ----------------
echo "🧹 Cleaning up previous installations..."
pkill -f tailscaled 2>/dev/null || true
pkill -f android_pusher.py 2>/dev/null || true

# ---------------- Install Tailscale ----------------
echo "⬇️ Installing Tailscale for Termux..."

# Create directories
mkdir -p $TS_DIR $SCRIPTS_DIR
cd $TS_DIR

# Detect architecture
ARCH=$(uname -m)
case "$ARCH" in
    "aarch64"|"arm64")
        ARCH_TYPE="arm64"
        ;;
    "armv7l"|"armv8l"|"arm")
        ARCH_TYPE="arm"
        ;;
    *)
        ARCH_TYPE="arm64"  # Default for most Android devices
        ;;
esac

echo "📊 Detected architecture: $ARCH ($ARCH_TYPE)"

# Download Tailscale
TS_VER="1.68.1"  # Latest stable version
TS_FILE="tailscale_${TS_VER}_${ARCH_TYPE}.tgz"
TS_URL="https://pkgs.tailscale.com/stable/${TS_FILE}"

echo "⬇️ Downloading Tailscale $TS_VER..."
curl -LO --progress-bar "$TS_URL"

# Extract
echo "📂 Extracting Tailscale..."
tar xzf "${TS_FILE}"

# Move binaries to PATH
echo "🔧 Installing binaries..."
mv -f tailscaled tailscale $PREFIX/bin/
chmod 755 $PREFIX/bin/tailscaled $PREFIX/bin/tailscale

# Verify installation
echo "✅ Tailscale installed: $(tailscale version | head -1)"

# ---------------- Setup Tailscale ----------------
echo "🚀 Setting up Tailscale..."

# Start Tailscale daemon in background
echo "   Starting daemon..."
tailscaled --tun=userspace-networking --state=$TS_DIR/tailscaled.state --socket=$TS_DIR/tailscaled.sock 2>$TS_DIR/tailscaled.log &
TS_PID=$!
sleep 3

# Set socket path for tailscale command
export TAILSCALE_SOCKET="$TS_DIR/tailscaled.sock"

# ---------------- AUTOMATIC AUTHENTICATION WITH HARDCODED KEY ----------------
echo "🔑 Authenticating with hardcoded auth key..."
echo "   Using key: ${AUTH_KEY:0:15}..."  # Show first 15 chars for verification

if tailscale up --auth-key "$AUTH_KEY"; then
    echo "✅ Authentication successful!"
    TS_IP=$(tailscale ip --4 2>/dev/null || echo "Could not get IP")
    echo "   Tailscale IP: $TS_IP"
else
    echo "❌ Authentication failed!"
    echo "   Check your auth key and network connection."
    echo "   You can manually authenticate later with:"
    echo "   tailscale up --auth-key YOUR_KEY"
fi

# ---------------- Download Python exporter ----------------
cd $SCRIPTS_DIR
echo "⬇️ Downloading Android Prometheus pusher..."
curl -sL https://raw.githubusercontent.com/ihamzazahid/free-android-device-monitoring/main/android-agent/android_pusher.py -o android_pusher.py
chmod +x android_pusher.py

# ---------------- Create config ----------------
echo "⚙️ Creating configuration..."
cat > $CONFIG_FILE << EOF
# Android Monitor Configuration
PUSHGATEWAY=100.97.72.3:9091
JOB_NAME=android_device_$(hostname)
PUSH_INTERVAL=15
TOP_N_PROCESSES=5
TAILSCALE_SOCKET=$TS_DIR/tailscaled.sock
AUTH_KEY_USED=${AUTH_KEY:0:10}...  # Store first 10 chars for reference
EOF

# ---------------- Create management scripts ----------------
echo "🔧 Creating management scripts..."

# Start script with authentication
cat > $SCRIPTS_DIR/start_monitoring.sh << EOF
#!/data/data/com.termux/files/usr/bin/bash
set -e

echo "\$(date) - Starting Android Monitoring"

# Load environment
export TAILSCALE_SOCKET="$TS_DIR/tailscaled.sock"

# Start Tailscale if not running
if ! tailscale status >/dev/null 2>&1; then
    echo "Starting Tailscale daemon..."
    tailscaled --tun=userspace-networking \\
              --state=$TS_DIR/tailscaled.state \\
              --socket=$TS_DIR/tailscaled.sock 2>$TS_DIR/tailscaled.log &
    sleep 3
fi

# Check if connected to Tailscale
if tailscale status >/dev/null 2>&1; then
    echo "Tailscale is connected."
    echo "IP: \$(tailscale ip --4 2>/dev/null || echo 'Not connected')"
else
    echo "🔑 Authenticating with stored key..."
    if tailscale up --auth-key "$AUTH_KEY"; then
        echo "✅ Authentication successful!"
    else
        echo "⚠️  Authentication failed. Device may not be connected to Tailscale."
    fi
fi

# Start metrics pusher
echo "Starting metrics pusher..."
cd $SCRIPTS_DIR
nohup python android_pusher.py >> android_pusher.log 2>&1 &
echo \$! > android_pusher.pid

echo "Monitoring started!"
echo "Log: $SCRIPTS_DIR/android_pusher.log"
EOF

# Stop script
cat > $SCRIPTS_DIR/stop_monitoring.sh << EOF
#!/data/data/com.termux/files/usr/bin/bash
echo "Stopping Android Monitoring..."

# Stop pusher
if [ -f $SCRIPTS_DIR/android_pusher.pid ]; then
    pid=\$(cat $SCRIPTS_DIR/android_pusher.pid)
    kill \$pid 2>/dev/null && echo "Stopped metrics pusher (PID: \$pid)"
    rm -f $SCRIPTS_DIR/android_pusher.pid
fi

# Note: We don't stop Tailscale daemon to keep VPN connection
echo "Monitoring stopped (Tailscale connection remains active)"
EOF

# Status script
cat > $SCRIPTS_DIR/check_status.sh << EOF
#!/data/data/com.termux/files/usr/bin/bash
echo "=== Android Monitoring Status ==="
echo ""

# Check Tailscale
echo "Tailscale:"
if command -v tailscale >/dev/null 2>&1; then
    if tailscale status >/dev/null 2>&1; then
        echo "  ✅ Connected"
        echo "  IP: \$(tailscale ip --4 2>/dev/null || echo 'Unknown')"
        echo "  Auth: Using hardcoded key (${AUTH_KEY:0:10}...)"
    else
        echo "  ❌ Not connected"
        echo "  Auth key configured: ${AUTH_KEY:0:10}..."
    fi
else
    echo "  ❌ Not installed"
fi

# Check pusher
echo ""
echo "Metrics Pusher:"
if [ -f $SCRIPTS_DIR/android_pusher.pid ]; then
    pid=\$(cat $SCRIPTS_DIR/android_pusher.pid)
    if ps -p \$pid >/dev/null 2>&1; then
        echo "  ✅ Running (PID: \$pid)"
        echo "  Log: $SCRIPTS_DIR/android_pusher.log"
        echo -n "  Log entries: "
        wc -l $SCRIPTS_DIR/android_pusher.log 2>/dev/null | cut -d' ' -f1 || echo "0"
    else
        echo "  ❌ Not running (stale PID)"
    fi
else
    echo "  ❌ Not running"
fi
EOF

chmod +x $SCRIPTS_DIR/start_monitoring.sh $SCRIPTS_DIR/stop_monitoring.sh $SCRIPTS_DIR/check_status.sh

# ---------------- Start monitoring ----------------
echo "🚀 Starting monitoring..."
$SCRIPTS_DIR/start_monitoring.sh

# ---------------- Final instructions ----------------
echo ""
echo "✅ SETUP COMPLETE!"
echo "================================"
echo ""
echo "📱 YOUR TERMUX DEVICE IS NOW CONNECTED VIA TAILSCALE"
echo ""
echo "🔗 Connection Details:"
echo "   Auth Key: ${AUTH_KEY:0:15}... (hardcoded)"
echo "   Tailscale IP: $(tailscale ip --4 2>/dev/null || echo 'Check with: tailscale ip')"
echo ""
echo "⚡ Management Commands:"
echo "   Start:  $SCRIPTS_DIR/start_monitoring.sh"
echo "   Stop:   $SCRIPTS_DIR/stop_monitoring.sh"
echo "   Status: $SCRIPTS_DIR/check_status.sh"
echo ""
echo "🔧 Tailscale Commands:"
echo "   Check IP:    tailscale ip --4"
echo "   Status:      tailscale status"
echo "   Disconnect:  tailscale down"
echo "   Reconnect:   tailscale up --auth-key $AUTH_KEY"
echo ""
echo "⚠️  SECURITY NOTE:"
echo "   Your auth key is hardcoded in this script."
echo "   Keep this script secure or regenerate key if compromised."
echo ""
echo "📊 To verify connection from laptop:"
echo "   1. Check Tailscale admin panel: https://login.tailscale.com/admin/machines"
echo "   2. Look for device: $(hostname)"
echo "   3. Ping the Tailscale IP shown above"
