#!/data/data/com.termux/files/usr/bin/bash
set -e

echo "📱 Android Push Monitoring Setup (Full Exporter)"
echo "================================"

# ---------------- Configuration ----------------
TS_DIR="$HOME/.tailscale"
SCRIPTS_DIR="$HOME/.scripts"
CONFIG_FILE="$HOME/.android_monitor.conf"
LOG_FILE="$SCRIPTS_DIR/android_pusher.log"
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
rm -rf $TS_DIR $SCRIPTS_DIR

# ---------------- Install Tailscale ----------------
echo "⬇️ Installing Tailscale for Termux..."

# Create fresh directories
mkdir -p $TS_DIR $SCRIPTS_DIR
cd $TS_DIR

# Detect architecture with better detection
ARCH=$(uname -m)
case "$ARCH" in
    "aarch64"|"arm64")
        ARCH_TYPE="arm64"
        echo "📊 Detected architecture: $ARCH (arm64)"
        ;;
    "armv7l"|"armv8l"|"arm")
        ARCH_TYPE="arm"
        echo "📊 Detected architecture: $ARCH (arm)"
        ;;
    "x86_64")
        ARCH_TYPE="amd64"
        echo "📊 Detected architecture: $ARCH (amd64)"
        ;;
    *)
        echo "⚠️  Unknown architecture: $ARCH, defaulting to arm64"
        ARCH_TYPE="arm64"
        ;;
esac

# Download Tailscale with better error handling
TS_VER="1.68.1"
TS_FILE="tailscale_${TS_VER}_${ARCH_TYPE}.tgz"
TS_URL="https://pkgs.tailscale.com/stable/${TS_FILE}"

echo "⬇️ Downloading Tailscale $TS_VER for $ARCH_TYPE..."
if ! curl -LO --progress-bar "$TS_URL"; then
    echo "❌ Failed to download Tailscale"
    echo "Trying alternative architecture..."
    # Try arm64 as fallback for most Android devices
    ARCH_TYPE="arm64"
    TS_FILE="tailscale_${TS_VER}_${ARCH_TYPE}.tgz"
    TS_URL="https://pkgs.tailscale.com/stable/${TS_FILE}"
    curl -LO --progress-bar "$TS_URL" || {
        echo "❌ Critical: Cannot download Tailscale"
        exit 1
    }
fi

# Verify download
if [ ! -f "$TS_FILE" ]; then
    echo "❌ Downloaded file not found: $TS_FILE"
    exit 1
fi

echo "📦 File size: $(du -h $TS_FILE | cut -f1)"

# Extract with verification
echo "📂 Extracting Tailscale..."
if ! tar -xzf "$TS_FILE"; then
    echo "❌ Failed to extract $TS_FILE"
    echo "Contents of directory:"
    ls -la
    exit 1
fi

# List extracted contents
echo "📁 Extracted contents:"
ls -la

# Check for binaries in multiple locations
BIN_DIR="."
if [ -f "tailscale_${TS_VER}_${ARCH_TYPE}/tailscale" ]; then
    BIN_DIR="tailscale_${TS_VER}_${ARCH_TYPE}"
    echo "📁 Found binaries in subdirectory: $BIN_DIR"
elif [ -d "tailscale" ]; then
    BIN_DIR="tailscale"
    echo "📁 Found binaries in 'tailscale' directory"
fi

# Verify binaries exist
echo "🔍 Looking for binaries..."
if [ ! -f "$BIN_DIR/tailscale" ] || [ ! -f "$BIN_DIR/tailscaled" ]; then
    echo "❌ Binaries not found!"
    echo "Available files in $BIN_DIR/:"
    ls -la $BIN_DIR/ 2>/dev/null || ls -la
    echo "Trying to find any tailscale files..."
    find . -name "*tailscale*" -type f | head -10
    exit 1
fi

# Install binaries
echo "🔧 Installing binaries..."
echo "Copying tailscale from: $BIN_DIR/"
cp -v "$BIN_DIR/tailscale" "$PREFIX/bin/" || {
    echo "❌ Failed to copy tailscale"
    exit 1
}
cp -v "$BIN_DIR/tailscaled" "$PREFIX/bin/" || {
    echo "❌ Failed to copy tailscaled"
    exit 1
}

chmod 755 "$PREFIX/bin/tailscale" "$PREFIX/bin/tailscaled"

# Verify installation
echo "✅ Verifying installation..."
if command -v tailscale >/dev/null 2>&1 && command -v tailscaled >/dev/null 2>&1; then
    echo "✅ Tailscale installed successfully"
    echo "   Version: $(tailscale version 2>/dev/null | head -1 || echo "Check with: tailscale --version")"
else
    echo "❌ Installation verification failed"
    echo "PATH: $PATH"
    echo "Files in $PREFIX/bin/:"
    ls -la "$PREFIX/bin/" | grep -i tailscale
    exit 1
fi

# ---------------- Setup Tailscale ----------------
echo "🚀 Setting up Tailscale..."

# Clean any existing state
rm -f $TS_DIR/tailscaled.state $TS_DIR/tailscaled.sock

# Start Tailscale daemon in background
echo "   Starting daemon..."
tailscaled --tun=userspace-networking --state=$TS_DIR/tailscaled.state --socket=$TS_DIR/tailscaled.sock >$TS_DIR/tailscaled.log 2>&1 &
TS_PID=$!
sleep 5

# Check if daemon is running
if ps -p $TS_PID >/dev/null 2>&1; then
    echo "✅ Tailscale daemon started (PID: $TS_PID)"
else
    echo "❌ Failed to start Tailscale daemon"
    echo "Log contents:"
    cat $TS_DIR/tailscaled.log
    exit 1
fi

# Set socket path
export TAILSCALE_SOCKET="$TS_DIR/tailscaled.sock"

# ---------------- AUTOMATIC AUTHENTICATION ----------------
echo "🔑 Authenticating with hardcoded auth key..."
echo "   Key: ${AUTH_KEY:0:20}..."

# Wait a bit for daemon to be ready
sleep 2

if tailscale up --auth-key "$AUTH_KEY" 2>&1; then
    echo "✅ Authentication successful!"
    sleep 2
    TS_IP=$(tailscale ip --4 2>/dev/null || echo "Checking...")
    echo "   Tailscale IP: $TS_IP"
else
    echo "⚠️  Authentication attempt completed"
    echo "   You can check status with: tailscale status"
fi

# ---------------- Download Python exporter ----------------
cd $SCRIPTS_DIR
echo "⬇️ Downloading Android Prometheus pusher..."
if curl -sL https://raw.githubusercontent.com/ihamzazahid/free-android-device-monitoring/main/android-agent/android_pusher.py -o android_pusher.py; then
    chmod +x android_pusher.py
    echo "✅ Exporter downloaded"
else
    echo "❌ Failed to download exporter"
    echo "Creating minimal exporter instead..."
    # ... [rest of your script continues with the minimal exporter or exits]
