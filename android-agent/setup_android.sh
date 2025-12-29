#!/data/data/com.termux/files/usr/bin/bash
set -e

echo "📱 Android Push Monitoring Setup (Cloudflare Tunnel)"
echo "==================================================="

# ---------------- CONFIGURATION ----------------
SCRIPTS_DIR="$HOME/.scripts"
CONFIG_FILE="$HOME/.android_monitor.conf"
LOG_FILE="$SCRIPTS_DIR/android_pusher.log"
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
pkg install -y python curl git
pip install --upgrade prometheus-client psutil requests

# ---------------- CLEANUP PREVIOUS INSTALL ----------------
echo "🧹 Cleaning up old scripts..."
pkill -f android_pusher.py 2>/dev/null || true
rm -rf $SCRIPTS_DIR
mkdir -p $SCRIPTS_DIR

# ---------------- CREATE PYTHON PUSHER ----------------
cat > $SCRIPTS_DIR/android_pusher.py << EOF
#!/usr/bin/env python3
import time, os, psutil
from prometheus_client import CollectorRegistry, Gauge, Counter, push_to_gateway

TUNNEL_URL = "$TUNNEL_URL"
DEVICE_NAME = "$DEVICE_NAME"
INTERVAL = $INTERVAL
TOP_N_PROCESSES = $TOP_N_PROCESSES

registry = CollectorRegistry()

# ---------------- METRICS ----------------
def safe_gauge(name, description, labels=None):
    try:
        if labels:
            return Gauge(name, description, labels, registry=registry)
        return Gauge(name, description, registry=registry)
    except Exception as e:
        print(f"⚠️ Failed to create gauge {name}: {e}")
        return None

def safe_counter(name, description, labels=None):
    try:
        if labels:
            return Counter(name, description, labels, registry=registry)
        return Counter(name, description, registry=registry)
    except Exception as e:
        print(f"⚠️ Failed to create counter {name}: {e}")
        return None

# CPU
cpu_percent = safe_gauge("android_cpu_percent", "Total CPU usage percent")
cpu_per_core = safe_gauge("android_cpu_core_percent", "CPU usage per core", ["core"])
cpu_count = safe_gauge("android_cpu_count", "Number of CPU cores")
load_avg_1 = safe_gauge("android_loadavg_1", "1-minute load average")
load_avg_5 = safe_gauge("android_loadavg_5", "5-minute load average")
load_avg_15 = safe_gauge("android_loadavg_15", "15-minute load average")

# Memory
memory_total = safe_gauge("android_memory_total_mb", "Total memory MB")
memory_available = safe_gauge("android_memory_available_mb", "Available memory MB")
memory_used = safe_gauge("android_memory_used_mb", "Used memory MB")
swap_total = safe_gauge("android_swap_total_mb", "Swap total MB")
swap_used = safe_gauge("android_swap_used_mb", "Swap used MB")
mem_percent = safe_gauge("android_memory_percent", "Memory usage percent")

# Storage
storage_total = safe_gauge("android_storage_total_gb", "Total storage GB")
storage_free = safe_gauge("android_storage_free_gb", "Free storage GB")

# Battery
battery_percent = safe_gauge("android_battery_percent", "Battery percentage")
battery_plugged = safe_gauge("android_battery_plugged", "Battery charging status (1=charging,0=not)")

# Network
network_sent = safe_counter("android_network_bytes_sent_total", "Network bytes sent")
network_recv = safe_counter("android_network_bytes_recv_total", "Network bytes received")
network_errin = safe_counter("android_network_errin_total", "Network input errors")
network_errout = safe_counter("android_network_errout_total", "Network output errors")

# Processes
total_processes = safe_gauge("android_total_processes", "Total number of processes")
running_processes = safe_gauge("android_running_processes", "Number of running processes")
process_cpu = safe_gauge("android_process_cpu_percent", "CPU usage percent per process", ["pid", "name"])
process_mem = safe_gauge("android_process_memory_mb", "Memory usage MB per process", ["pid", "name"])

# Uptime
uptime = safe_counter("android_uptime_seconds_total", "Uptime seconds")

# ---------------- STATE ----------------
last_uptime = 0
last_sent = 0
last_recv = 0
last_errin = 0
last_errout = 0

# ---------------- UPDATE FUNCTIONS ----------------
def update_cpu():
    try:
        if cpu_percent: cpu_percent.set(psutil.cpu_percent(interval=None))
        if cpu_count: cpu_count.set(psutil.cpu_count())
        if cpu_per_core:
            for i, val in enumerate(psutil.cpu_percent(interval=None, percpu=True)):
                cpu_per_core.labels(core=str(i)).set(val)
        if hasattr(os, "getloadavg"):
            la1, la5, la15 = os.getloadavg()
            if load_avg_1: load_avg_1.set(la1)
            if load_avg_5: load_avg_5.set(la5)
            if load_avg_15: load_avg_15.set(la15)
    except Exception as e:
        print(f"⚠️ CPU metrics not accessible: {e}")

def update_memory():
    try:
        mem = psutil.virtual_memory()
        if memory_total: memory_total.set(mem.total/1024/1024)
        if memory_available: memory_available.set(mem.available/1024/1024)
        if memory_used: memory_used.set(mem.used/1024/1024)
        swap = psutil.swap_memory()
        if swap_total: swap_total.set(swap.total/1024/1024)
        if swap_used: swap_used.set(swap.used/1024/1024)
        if mem_percent: mem_percent.set(mem.percent)
    except Exception as e:
        print(f"⚠️ Memory metrics not accessible: {e}")

def update_storage():
    try:
        s = psutil.disk_usage('/')
        if storage_total: storage_total.set(s.total/1024/1024/1024)
        if storage_free: storage_free.set(s.free/1024/1024/1024)
    except Exception as e:
        print(f"⚠️ Storage metrics not accessible: {e}")

def update_battery():
    try:
        if hasattr(psutil, "sensors_battery"):
            try:
                bat = psutil.sensors_battery()
                if bat:
                    if battery_percent: battery_percent.set(bat.percent)
                    if battery_plugged: battery_plugged.set(1 if bat.power_plugged else 0)
                else:
                    if battery_percent: battery_percent.set(0)
                    if battery_plugged: battery_plugged.set(0)
            except PermissionError:
                print("⚠️ Battery metrics not accessible (Permission denied). Using defaults.")
                if battery_percent: battery_percent.set(0)
                if battery_plugged: battery_plugged.set(0)
    except Exception as e:
        print(f"⚠️ Unexpected error updating battery metrics: {e}")

def update_network():
    global last_sent, last_recv, last_errin, last_errout
    try:
        net = psutil.net_io_counters()
        if network_sent: network_sent.inc(net.bytes_sent - last_sent if last_sent else net.bytes_sent)
        if network_recv: network_recv.inc(net.bytes_recv - last_recv if last_recv else net.bytes_recv)
        if network_errin: network_errin.inc(net.errin - last_errin if last_errin else net.errin)
        if network_errout: network_errout.inc(net.errout - last_errout if last_errout else net.errout)
        last_sent = net.bytes_sent
        last_recv = net.bytes_recv
        last_errin = net.errin
        last_errout = net.errout
    except Exception as e:
        print(f"⚠️ Network metrics not accessible: {e}")

def update_processes():
    try:
        if total_processes: total_processes.set(len(psutil.pids()))
        if running_processes:
            running = sum(1 for p in psutil.process_iter(attrs=['status']) if p.info['status'] == psutil.STATUS_RUNNING)
            running_processes.set(running)
    except Exception as e:
        print(f"⚠️ Process metrics not accessible: {e}")

def update_top_processes():
    try:
        top_cpu = sorted(psutil.process_iter(attrs=["pid","name","cpu_percent","memory_info"]),
                         key=lambda p: p.info["cpu_percent"], reverse=True)[:TOP_N_PROCESSES]
        for proc in top_cpu:
            try:
                pid = str(proc.info["pid"])
                name = proc.info["name"]
                cpu_val = proc.info["cpu_percent"]
                mem_val = proc.info["memory_info"].rss/1024/1024
                if process_cpu: process_cpu.labels(pid=pid,name=name).set(cpu_val)
                if process_mem: process_mem.labels(pid=pid,name=name).set(mem_val)
            except Exception:
                continue
    except Exception as e:
        print(f"⚠️ Top process metrics not accessible: {e}")

def update_uptime():
    global last_uptime
    try:
        up = time.time() - psutil.boot_time()
        if uptime: uptime.inc(up - last_uptime if last_uptime else up)
        last_uptime = up
    except Exception as e:
        print(f"⚠️ Uptime metrics not accessible: {e}")

# ---------------- MAIN LOOP ----------------
print(f"📡 Pushing metrics to {TUNNEL_URL} every {INTERVAL}s as {DEVICE_NAME}")

while True:
    update_cpu()
    update_memory()
    update_storage()
    update_battery()
    update_network()
    update_processes()
    update_top_processes()
    update_uptime()

    try:
        push_to_gateway(TUNNEL_URL, job=f"android_{DEVICE_NAME}", registry=registry)
        print(f"✅ Pushed metrics at {time.ctime()}")
    except Exception as e:
        print(f"⚠️ Push failed: {e}")

    time.sleep(INTERVAL)
EOF

chmod +x $SCRIPTS_DIR/android_pusher.py

# ---------------- MANAGEMENT SCRIPTS ----------------
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

# ---------------- START MONITORING ----------------
echo "🚀 Starting monitoring automatically..."
$SCRIPTS_DIR/start_monitoring.sh

echo ""
echo "✅ SETUP COMPLETE!"
echo "📄 Logs: tail -f $SCRIPTS_DIR/android_pusher.log"
echo "📋 Management Commands:"
echo "   Start:  $SCRIPTS_DIR/start_monitoring.sh"
echo "   Stop:   $SCRIPTS_DIR/stop_monitoring.sh"
echo "   Status: $SCRIPTS_DIR/check_status.sh"
