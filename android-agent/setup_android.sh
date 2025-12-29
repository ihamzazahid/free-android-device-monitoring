#!/data/data/com.termux/files/usr/bin/bash
set -e

echo "📱 Android Push Monitoring Setup (Full Exporter)"
echo "================================"

# ---------------- Update system ----------------
pkg update -y && pkg upgrade -y

# ---------------- Install dependencies ----------------
pkg install -y python curl git tar
pip install --upgrade prometheus-client psutil requests

# ---------------- Install Tailscale ----------------
echo "⬇️ Installing Tailscale static binary for Termux..."

TS_DIR="$HOME/tailscale"
mkdir -p $TS_DIR
cd $TS_DIR

# Detect architecture
ARCH=$(uname -m)
if [[ "$ARCH" == "aarch64" ]]; then
    ARCH_TYPE="arm64"
else
    ARCH_TYPE="arm"
fi

TS_VER="1.44.4"  # you can update to latest
TS_FILE="tailscale_${TS_VER}_${ARCH_TYPE}.tgz"

# Download & extract
curl -LO https://pkgs.tailscale.com/stable/${TS_FILE}
tar xzf ${TS_FILE}

# Move binaries to PATH
mv tailscaled tailscale $PREFIX/bin/
chmod +x $PREFIX/bin/tailscaled $PREFIX/bin/tailscale

# Start Tailscale daemon
echo "🚀 Starting Tailscale daemon..."
tailscaled --state=$TS_DIR/tailscaled.state >/dev/null 2>&1 &
sleep 2

# Connect device to Tailscale network (you’ll need to authenticate via browser)
echo "🔑 Authenticate Tailscale in your browser:"
tailscale up || true

# ---------------- Create directories ----------------
mkdir -p ~/.scripts
cd ~/.scripts

# ---------------- Download Python exporter ----------------
echo "⬇️ Downloading Android Prometheus pusher..."
curl -sL https://raw.githubusercontent.com/ihamzazahid/free-android-device-monitoring/main/android-agent/android_pusher.py -o android_pusher.py
chmod +x android_pusher.py

# ---------------- Create config ----------------
cat > ~/.android_monitor.conf << EOF
PUSHGATEWAY=100.97.72.3:9091
JOB_NAME=android_device
PUSH_INTERVAL=15
TOP_N_PROCESSES=5
EOF

# ---------------- Start exporter ----------------
echo "📊 Starting metric pusher..."
nohup python ~/.scripts/android_pusher.py > ~/.scripts/android_pusher.log 2>&1 &

echo ""
echo "✅ Setup complete!"
echo "📡 Metrics are being PUSHED to your Windows laptop via Tailscale"
echo "📝 Logs: ~/.scripts/android_pusher.log"
echo "💻 Tailscale IP: $(tailscale ip)"
