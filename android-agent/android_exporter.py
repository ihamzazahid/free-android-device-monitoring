#!/usr/bin/env python3
import json
import os
import subprocess
import time
import hashlib
from prometheus_client import CollectorRegistry, Gauge, Counter, push_to_gateway

# ---------------- CONFIG ----------------
TUNNEL_URL = os.environ.get("PUSHGATEWAY_URL", "dated-finding-troy-diverse.trycloudflare.com")
INTERVAL = int(os.environ.get("INTERVAL", "15"))

# ---------------- HELPERS ----------------
def run_termux(cmd):
    """Run a termux-* command and return JSON output."""
    try:
        out = subprocess.check_output(cmd, stderr=subprocess.DEVNULL)
        return json.loads(out.decode())
    except Exception:
        return None

def stable_device_id():
    """Generate a stable device ID hash."""
    base = f"{os.uname().nodename}"
    return hashlib.sha256(base.encode()).hexdigest()[:12]

DEVICE_ID = stable_device_id()

# ---------------- PROMETHEUS ----------------
registry = CollectorRegistry()

# Device
device_info = Gauge("android_device_info", "Device info",
                    ["device_id", "brand", "model", "android_version"],
                    registry=registry)

# Memory / Storage
mem_total = Gauge("android_memory_total_mb", "Total memory MB", registry=registry)
mem_used = Gauge("android_memory_used_mb", "Used memory MB", registry=registry)
mem_percent = Gauge("android_memory_percent", "Memory percent", registry=registry)

disk_total = Gauge("android_storage_total_gb", "Storage total GB", registry=registry)
disk_free = Gauge("android_storage_free_gb", "Storage free GB", registry=registry)

# Battery
battery_percent = Gauge("android_battery_percent", "Battery percent", registry=registry)
battery_charging = Gauge("android_battery_charging", "Battery charging (1=yes)", registry=registry)
battery_temp = Gauge("android_battery_temperature_c", "Battery temperature C", registry=registry)

# Network
network_type = Gauge("android_network_type", "Network type", ["type"], registry=registry)
cell_signal = Gauge("android_cell_signal_dbm", "Cell signal dBm", registry=registry)
net_sent = Counter("android_network_bytes_sent_total", "Bytes sent", registry=registry)
net_recv = Counter("android_network_bytes_recv_total", "Bytes recv", registry=registry)

# Uptime / Processes
uptime = Gauge("android_uptime_seconds", "Uptime seconds", registry=registry)
process_count = Gauge("android_process_count", "Process count", registry=registry)

# ---------------- COLLECTORS ----------------
def collect_device():
    info = run_termux(["termux-telephony-deviceinfo"])
    if not info:
        return
    device_info.labels(
        device_id=DEVICE_ID,
        brand=info.get("manufacturer", "unknown"),
        model=info.get("model", "unknown"),
        android_version=info.get("device_version", "unknown")
    ).set(1)

def collect_memory_storage():
    info = run_termux(["termux-info"])
    if info:
        mem_total.set(info.get("total_mem", 0) / 1024 / 1024)
        mem_used.set(info.get("used_mem", 0) / 1024 / 1024)
        try:
            mem_percent.set((info.get("used_mem",0)/info.get("total_mem",1))*100)
        except ZeroDivisionError:
            mem_percent.set(0)

        disk_total.set(info.get("disk_total", 0) / 1024 / 1024 / 1024)
        disk_free.set(info.get("disk_free", 0) / 1024 / 1024 / 1024)

def collect_battery():
    b = run_termux(["termux-battery-status"])
    if not b:
        return
    battery_percent.set(b.get("percentage", 0))
    battery_charging.set(1 if b.get("status") == "CHARGING" else 0)
    battery_temp.set(b.get("temperature", 0))

def collect_network():
    wifi = run_termux(["termux-wifi-connectioninfo"])
    tele = run_termux(["termux-telephony-signalinfo"])
    network_type.clear()

    if wifi and wifi.get("supplicant_state") == "COMPLETED":
        network_type.labels(type="wifi").set(1)
    elif tele:
        network_type.labels(type="mobile").set(1)
        try:
            cell_signal.set(tele[0]["signalStrength"])
        except Exception:
            pass

    # Network usage not available via Termux API; skip counters

def collect_misc():
    info = run_termux(["termux-info"])
    if info:
        uptime.set(info.get("uptime", 0))
    else:
        uptime.set(0)

    top = run_termux(["termux-top", "-n", "1", "-b"])
    if top:
        process_count.set(top.get("procs_total", 0))
    else:
        process_count.set(0)

# ---------------- MAIN LOOP ----------------
print(f"📡 Android exporter running as {DEVICE_ID}")

while True:
    try:
        collect_device()
        collect_memory_storage()
        collect_battery()
        collect_network()
        collect_misc()

        push_to_gateway(
            TUNNEL_URL,
            job="android_device",
            grouping_key={"device": DEVICE_ID},
            registry=registry
        )

        print(f"✅ Metrics pushed at {time.ctime()}")
    except Exception as e:
        print(f"⚠️ Push error: {e}")

    time.sleep(INTERVAL)
