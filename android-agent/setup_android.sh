#!/data/data/com.termux/files/usr/bin/bash
# Android Device Monitoring Setup

echo "📱 Android Device Monitoring Setup"
echo "=================================="

# Update and install
pkg update -y && pkg upgrade -y
pkg install -y python openssh curl
pip install prometheus-client --upgrade

# Create directories
mkdir -p ~/.scripts ~/.termux/boot
cd ~/.scripts

# Download exporter
curl -sL https://raw.githubusercontent.com/ihamzazahid/free-android-device-monitoring/main/android-agent/android_exporter.py -o android_exporter.py
chmod +x android_exporter.py

# Setup SSH
echo "Set SSH password:"
passwd
sshd

# Get IP
DEVICE_IP=$(python3 -c "
import socket
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.connect(('8.8.8.8', 53))
print(s.getsockname()[0])
s.close()
")

echo "IP_ADDRESS=$DEVICE_IP" > ~/.android_config

# Create info script
cat > ~/connection_info.sh << EOF
echo ""
echo "📱 DEVICE INFO:"
echo "IP: \$DEVICE_IP"
echo "SSH Port: 8022"
echo "Metrics Port: 9100"
echo ""
echo "💻 On laptop, run:"
echo "ssh -N -L 19100:localhost:9100 termux@\$DEVICE_IP -p 8022"
EOF

chmod +x ~/connection_info.sh

# Start exporter
cd ~/.scripts
nohup python android_exporter.py > exporter.log 2>&1 &

echo ""
echo "✅ Setup complete!"
echo "Run './connection_info.sh' for connection details"
