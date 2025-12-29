#!/data/data/com.termux/files/usr/bin/bash
set -e

echo "📱 Android Push Monitoring Setup (Direct Push)"
echo "============================================"

# ---------------- Configuration ----------------
SCRIPTS_DIR="$HOME/.scripts"
CONFIG_FILE="$HOME/.android_monitor.conf"
LOG_FILE="$SCRIPTS_DIR/android_pusher.log"

# ⚠️ IMPORTANT: Replace with YOUR laptop's Tailscale IP
# Get this by running 'tailscale ip --4' on your laptop
LAPTOP_TS_IP="100.97.72.3"  # ⬅️ CHANGE THIS TO YOUR LAPTOP'S TAILSCALE IP

echo "🔧 Will push metrics to laptop at: $LAPTOP_TS_IP:9091"
echo "   (Make sure Prometheus PushGateway is running there)"

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

# Try to download the original script
if curl -sL https://raw.githubusercontent.com/ihamzazahid/free-android-device-monitoring/main/android-agent/android_pusher.py -o android_pusher.py; then
    echo "✅ Downloaded original pusher script"
    
    # Modify it to use laptop's Tailscale IP
    echo "🔧 Modifying script to push to laptop at $LAPTOP_TS_IP..."
    
    # Create a modified version
    cat > android_pusher_modified.py << EOF
#!/usr/bin/env python3
"""
Android Prometheus Metrics Pusher
Modified to push directly to laptop's Tailscale IP
"""
import os
import time
import socket
import psutil
from prometheus_client import CollectorRegistry, Gauge, Counter, push_to_gateway

# Configuration - PUSH DIRECTLY TO LAPTOP
PUSHGATEWAY = "$LAPTOP_TS_IP:9091"  # Your laptop's Tailscale IP
JOB_NAME = f"android_{socket.gethostname().replace('.', '_')}"
PUSH_INTERVAL = int(os.getenv('PUSH_INTERVAL', '15'))
TOP_N_PROCESSES = int(os.getenv('TOP_N_PROCESSES', '5'))

print(f"🚀 Android Metrics Pusher")
print(f"📡 Target: {PUSHGATEWAY}")
print(f"📋 Job: {JOB_NAME}")
print(f"⏱️  Interval: {PUSH_INTERVAL}s")

def get_wifi_info():
    """Try to get WiFi information (Android-specific)"""
    try:
        # Try using termux-api if available
        import subprocess
        result = subprocess.run(['termux-wifi-connectioninfo'], 
                              capture_output=True, text=True, timeout=2)
        if result.returncode == 0:
            import json
            wifi_info = json.loads(result.stdout)
            return {
                'ssid': wifi_info.get('ssid', 'unknown'),
                'bssid': wifi_info.get('bssid', 'unknown'),
                'rssi': wifi_info.get('rssi', 0)
            }
    except:
        pass
    return {'ssid': 'unknown', 'bssid': 'unknown', 'rssi': 0}

def collect_android_metrics():
    """Collect Android-specific metrics"""
    registry = CollectorRegistry()
    
    # 1. System metrics
    cpu_percent = Gauge('android_cpu_percent', 'CPU usage percentage', registry=registry)
    cpu_percent.set(psutil.cpu_percent(interval=1))
    
    # 2. Memory metrics
    mem = psutil.virtual_memory()
    mem_percent = Gauge('android_memory_percent', 'Memory usage percentage', registry=registry)
    mem_used = Gauge('android_memory_used_bytes', 'Used memory in bytes', registry=registry)
    mem_total = Gauge('android_memory_total_bytes', 'Total memory in bytes', registry=registry)
    mem_available = Gauge('android_memory_available_bytes', 'Available memory in bytes', registry=registry)
    
    mem_percent.set(mem.percent)
    mem_used.set(mem.used)
    mem_total.set(mem.total)
    mem_available.set(mem.available)
    
    # 3. Disk metrics
    try:
        disk = psutil.disk_usage('/data')
        disk_percent = Gauge('android_disk_percent', 'Disk usage percentage', registry=registry)
        disk_used = Gauge('android_disk_used_bytes', 'Used disk space in bytes', registry=registry)
        disk_total = Gauge('android_disk_total_bytes', 'Total disk space in bytes', registry=registry)
        disk_free = Gauge('android_disk_free_bytes', 'Free disk space in bytes', registry=registry)
        
        disk_percent.set(disk.percent)
        disk_used.set(disk.used)
        disk_total.set(disk.total)
        disk_free.set(disk.free)
    except:
        pass
    
    # 4. Battery info (if available via termux-api)
    try:
        import subprocess
        result = subprocess.run(['termux-battery-status'], 
                              capture_output=True, text=True, timeout=2)
        if result.returncode == 0:
            import json
            battery = json.loads(result.stdout)
            battery_percent = Gauge('android_battery_percent', 'Battery percentage', registry=registry)
            battery_health = Gauge('android_battery_health', 'Battery health (1=good)', registry=registry)
            battery_plugged = Gauge('android_battery_plugged', 'Charging status (1=plugged)', registry=registry)
            
            battery_percent.set(battery.get('percentage', 0))
            battery_health.set(1 if battery.get('health', '') == 'GOOD' else 0)
            battery_plugged.set(1 if battery.get('plugged', '') != 'UNPLUGGED' else 0)
    except:
        pass
    
    # 5. Network info
    net_counters = psutil.net_io_counters()
    net_bytes_sent = Counter('android_network_bytes_sent_total', 'Total bytes sent', registry=registry)
    net_bytes_recv = Counter('android_network_bytes_received_total', 'Total bytes received', registry=registry)
    
    net_bytes_sent.inc(net_counters.bytes_sent)
    net_bytes_recv.inc(net_counters.bytes_recv)
    
    # 6. WiFi info (if termux-api is installed)
    try:
        wifi_info = get_wifi_info()
        wifi_rssi = Gauge('android_wifi_rssi', 'WiFi signal strength (RSSI)', registry=registry)
        wifi_rssi.set(wifi_info['rssi'])
        
        wifi_ssid_info = Gauge('android_wifi_ssid_info', 'WiFi SSID info', ['ssid'], registry=registry)
        wifi_ssid_info.labels(ssid=wifi_info['ssid']).set(1)
    except:
        pass
    
    # 7. Top processes by CPU
    try:
        processes = []
        for proc in psutil.process_iter(['pid', 'name', 'cpu_percent', 'memory_percent']):
            try:
                processes.append(proc.info)
            except:
                continue
        
        # Sort by CPU usage
        processes.sort(key=lambda x: x['cpu_percent'], reverse=True)
        
        for i, proc in enumerate(processes[:TOP_N_PROCESSES]):
            pid = proc['pid']
            name = proc['name'] or f'pid_{pid}'
            proc_cpu = Gauge(f'android_process_cpu', 'Process CPU usage', 
                           ['pid', 'name', 'rank'], registry=registry)
            proc_mem = Gauge(f'android_process_memory', 'Process memory usage', 
                           ['pid', 'name', 'rank'], registry=registry)
            
            proc_cpu.labels(pid=str(pid), name=name, rank=str(i+1)).set(proc['cpu_percent'])
            proc_mem.labels(pid=str(pid), name=name, rank=str(i+1)).set(proc['memory_percent'])
    except:
        pass
    
    # 8. Uptime
    uptime = Gauge('android_uptime_seconds', 'System uptime in seconds', registry=registry)
    uptime.set(time.time() - psutil.boot_time())
    
    # 9. Push counter
    push_counter = Counter('android_metrics_pushes_total', 'Total number of metric pushes', registry=registry)
    push_counter.inc()
    
    return registry

def test_connection():
    """Test if we can reach the laptop"""
    try:
        import socket
        sock = socket.create_connection(("$LAPTOP_TS_IP", 9091), timeout=5)
        sock.close()
        return True
    except:
        return False

def main():
    print("🧪 Testing connection to laptop...")
    if not test_connection():
        print(f"❌ Cannot connect to {LAPTOP_TS_IP}:9091")
        print("   Make sure:")
        print(f"   1. Laptop Tailscale IP is correct (currently: {LAPTOP_TS_IP})")
        print("   2. Prometheus PushGateway is running on laptop")
        print("   3. Both devices are on same Tailscale network")
        print("   4. Firewall allows port 9091 on laptop")
        return
    
    print("✅ Connection test passed!")
    print("🚀 Starting metric pushes...")
    
    while True:
        try:
            registry = collect_android_metrics()
            push_to_gateway(PUSHGATEWAY, job=JOB_NAME, registry=registry)
            print(f"✅ [{time.strftime('%H:%M:%S')}] Metrics pushed successfully")
        except Exception as e:
            print(f"❌ [{time.strftime('%H:%M:%S')}] Push failed: {str(e)[:50]}...")
        
        time.sleep(PUSH_INTERVAL)

if __name__ == '__main__':
    main()
EOF
    
    chmod +x android_pusher_modified.py
    echo "✅ Created modified pusher for direct laptop connection"
    
    # Use the modified version
    mv android_pusher_modified.py android_pusher.py
    
else
    echo "⚠️  Could not download, creating local version..."
    # Create local version (simplified)
    cat > android_pusher.py << EOF
#!/usr/bin/env python3
import time, psutil, socket
from prometheus_client import CollectorRegistry, Gauge, push_to_gateway

LAPTOP_IP = "$LAPTOP_TS_IP"
PUSHGATEWAY = f"{LAPTOP_IP}:9091"
JOB_NAME = f"android_{socket.gethostname()}"

print(f"Pushing to: {PUSHGATEWAY}")

while True:
    try:
        registry = CollectorRegistry()
        Gauge('cpu', 'CPU %', registry=registry).set(psutil.cpu_percent())
        Gauge('mem', 'Memory %', registry=registry).set(psutil.virtual_memory().percent)
        Gauge('disk', 'Disk %', registry=registry).set(psutil.disk_usage('/data').percent)
        
        push_to_gateway(PUSHGATEWAY, job=JOB_NAME, registry=registry)
        print(f"✓ Pushed at {time.ctime()}")
    except Exception as e:
        print(f"✗ Failed: {e}")
    
    time.sleep(15)
EOF
    chmod +x android_pusher.py
fi

# ---------------- Create config file ----------------
cat > $CONFIG_FILE << EOF
# Android Monitor Configuration
PUSHGATEWAY=$LAPTOP_TS_IP:9091
JOB_NAME=android_${DEVICE_NAME}
PUSH_INTERVAL=15
DEVICE_NAME=$DEVICE_NAME
SETUP_DATE=$(date)
LAPTOP_TS_IP=$LAPTOP_TS_IP

# Instructions:
# 1. On laptop, run: tailscale ip --4  (to get IP)
# 2. Update LAPTOP_TS_IP above if needed
# 3. Make sure PushGateway runs on laptop:9091
EOF

# ---------------- Create management scripts ----------------

# Start script
cat > $SCRIPTS_DIR/start_monitoring.sh << EOF
#!/data/data/com.termux/files/usr/bin/bash
echo "\$(date) - Starting Android Monitoring"

# Load configuration
source $CONFIG_FILE 2>/dev/null || true

echo "📱 Device: \$(hostname)"
echo "🎯 Target: \$PUSHGATEWAY"
echo "📋 Job: \$JOB_NAME"

# Check if Python script exists
if [ ! -f $SCRIPTS_DIR/android_pusher.py ]; then
    echo "❌ Pusher script not found!"
    exit 1
fi

# Kill existing process
pkill -f "python.*android_pusher" 2>/dev/null && echo "Stopped previous instance"

# Start new process
cd $SCRIPTS_DIR
nohup python android_pusher.py >> android_pusher.log 2>&1 &
PID=\$!
echo \$PID > android_pusher.pid

echo "✅ Monitoring started (PID: \$PID)"
echo "📄 Logs: tail -f $SCRIPTS_DIR/android_pusher.log"
echo ""
echo "🔍 Quick check:"
echo "   ps aux | grep android_pusher | grep -v grep"
echo "   tail -5 $SCRIPTS_DIR/android_pusher.log"
EOF

# Stop script
cat > $SCRIPTS_DIR/stop_monitoring.sh << EOF
#!/data/data/com.termux/files/usr/bin/bash
echo "Stopping Android Monitoring..."
pkill -f "python.*android_pusher" 2>/dev/null
rm -f $SCRIPTS_DIR/android_pusher.pid 2>/dev/null
echo "✅ Monitoring stopped"
EOF

# Status script
cat > $SCRIPTS_DIR/check_status.sh << EOF
#!/data/data/com.termux/files/usr/bin/bash
echo "=== Android Monitoring Status ==="
echo ""

# Check if running
if [ -f $SCRIPTS_DIR/android_pusher.pid ]; then
    PID=\$(cat $SCRIPTS_DIR/android_pusher.pid)
    if ps -p \$PID >/dev/null 2>&1; then
        echo "✅ Pusher: Running (PID: \$PID)"
        echo "   Uptime: \$(ps -o etime= -p \$PID | tr -d ' ')"
    else
        echo "❌ Pusher: Not running (stale PID)"
    fi
else
    echo "❌ Pusher: Not running"
fi

# Show config
echo ""
echo "📋 Configuration:"
echo "   Laptop IP: $LAPTOP_TS_IP"
echo "   Push URL: $LAPTOP_TS_IP:9091"
echo "   Device: \$(hostname)"

# Show last log entries
echo ""
echo "📄 Recent logs:"
tail -5 $SCRIPTS_DIR/android_pusher.log 2>/dev/null || echo "   No log file yet"
EOF

# Update config script (in case laptop IP changes)
cat > $SCRIPTS_DIR/update_laptop_ip.sh << EOF
#!/data/data/com.termux/files/usr/bin/bash
echo "Update Laptop Tailscale IP"
echo "=========================="
echo "Current IP: $LAPTOP_TS_IP"
echo ""
echo "To get your laptop's Tailscale IP:"
echo "1. On laptop, run: tailscale ip --4"
echo "2. Copy the IP (starts with 100.)"
echo ""
echo "Enter new laptop IP:"
read NEW_IP

if [[ \$NEW_IP =~ ^100\.[0-9]+\.[0-9]+\.[0-9]+\$ ]]; then
    # Update config file
    sed -i "s/LAPTOP_TS_IP=.*/LAPTOP_TS_IP=\$NEW_IP/" $CONFIG_FILE
    sed -i "s/PUSHGATEWAY=.*/PUSHGATEWAY=\$NEW_IP:9091/" $CONFIG_FILE
    
    # Update python script
    sed -i "s/LAPTOP_IP = \\".*\\"/LAPTOP_IP = \\"\$NEW_IP\\"/" $SCRIPTS_DIR/android_pusher.py 2>/dev/null
    sed -i "s/PUSHGATEWAY = \\".*:9091\\"/PUSHGATEWAY = \\"\$NEW_IP:9091\\"/" $SCRIPTS_DIR/android_pusher.py 2>/dev/null
    
    echo "✅ Updated laptop IP to: \$NEW_IP"
    echo ""
    echo "Restart monitoring:"
    echo "  $SCRIPTS_DIR/stop_monitoring.sh"
    echo "  $SCRIPTS_DIR/start_monitoring.sh"
else
    echo "❌ Invalid IP. Must be Tailscale IP (starts with 100.)"
fi
EOF

chmod +x $SCRIPTS_DIR/*.sh

# ---------------- Test connection first ----------------
echo ""
echo "🧪 Testing connection to laptop..."
python -c "
import socket
try:
    sock = socket.create_connection(('$LAPTOP_TS_IP', 9091), timeout=5)
    sock.close()
    print('✅ SUCCESS: Can connect to laptop at $LAPTOP_TS_IP:9091')
except Exception as e:
    print('❌ FAILED: Cannot connect to $LAPTOP_TS_IP:9091')
    print('   Error:', str(e))
    print('')
    print('⚠️  Please check:')
    print('   1. Run on laptop: tailscale ip --4')
    print('   2. Update LAPTOP_TS_IP in this script')
    print('   3. Ensure PushGateway runs on laptop port 9091')
"

# ---------------- Start monitoring ----------------
echo ""
echo "🚀 Starting monitoring..."
$SCRIPTS_DIR/start_monitoring.sh

# ---------------- Final instructions ----------------
echo ""
echo "✅ SETUP COMPLETE!"
echo "=================="
echo ""
echo "📱 Android Device: $DEVICE_NAME"
echo "💻 Laptop Target: $LAPTOP_TS_IP:9091"
echo ""
echo "⚡ Management Commands:"
echo "   Start:  $SCRIPTS_DIR/start_monitoring.sh"
echo "   Stop:   $SCRIPTS_DIR/stop_monitoring.sh"
echo "   Status: $SCRIPTS_DIR/check_status.sh"
echo "   Update IP: $SCRIPTS_DIR/update_laptop_ip.sh"
echo ""
echo "📊 On Your Laptop:"
echo "   1. Ensure Tailscale is running: tailscale status"
echo "   2. Run Prometheus PushGateway:"
echo "      docker run -d -p 9091:9091 prom/pushgateway"
echo "   3. Check received metrics:"
echo "      curl http://localhost:9091/metrics | grep android"
echo ""
echo "🔧 If connection fails:"
echo "   1. Get laptop IP: tailscale ip --4 (on laptop)"
echo "   2. Update: $SCRIPTS_DIR/update_laptop_ip.sh"
echo "   3. Restart: $SCRIPTS_DIR/stop_monitoring.sh && $SCRIPTS_DIR/start_monitoring.sh"
echo ""
echo "📝 Logs: tail -f $SCRIPTS_DIR/android_pusher.log"
