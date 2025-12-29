#!/data/data/com.termux/files/usr/bin/bash
set -e

echo "📱 Android Push Monitoring Setup"
echo "================================"

# Update system
pkg update -y && pkg upgrade -y

# Install dependencies
pkg install -y python curl git

# Install Prometheus client and psutil
pip install --upgrade prometheus-client psutil requests

# Install Tailscale
if ! command -v tailscale &> /dev/null; then
    echo "⬇️ Installing Tailscale..."
    curl -fsSL https://tailscale.com/install.sh | sh
fi

# Start tailscaled
echo "🚀 Starting Tailscale..."
tailscaled >/dev/null 2>&1 &
sleep 2
tailscale up || true

# Create directories
mkdir -p ~/.scripts
cd ~/.scripts

# Download Python exporter
echo "⬇️ Downloading Android pusher..."
curl -sL https://raw.githubusercontent.com/ihamzazahid/free-android-device-monitoring/main/android-agent/android_pusher.py -o android_pusher.py
chmod +x android_pusher.py

# Save config
cat > ~/.android_monitor.conf << EOF
PUSHGATEWAY=100.97.72.3:9091
JOB_NAME=android_device
PUSH_INTERVAL=15
EOF

# Start exporter
echo "📊 Starting metric pusher..."
nohup python ~/.scripts/android_pusher.py > ~/.scripts/android_pusher.log 2>&1 &

echo ""
echo "✅ Setup complete!"
echo "📡 Metrics are being PUSHED to your Windows laptop via Tailscale"
echo "📝 Logs: ~/.scripts/android_pusher.log"
