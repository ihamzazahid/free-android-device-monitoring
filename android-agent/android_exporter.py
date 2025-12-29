#!/usr/bin/env python3
"""
Android Prometheus PUSH exporter (CGNAT-safe)
Collects:
- CPU: total + per core + load average
- Memory + swap
- Storage
- Battery
- Network
- Uptime
- Processes: total, running
- Top N processes by CPU & memory
"""

import time
import os
import psutil
from prometheus_client import CollectorRegistry, Gauge, Counter, push_to_gateway

# ---------------- CONFIG ----------------
CONF = os.path.expanduser("~/.android_monitor.conf")
cfg = {}
with open(CONF) as f:
    for line in f:
        if "=" in line:
            k, v = line.strip().split("=", 1)
            cfg[k] = v

PUSHGATEWAY = cfg.get("PUSHGATEWAY")
JOB_NAME = cfg.get("JOB_NAME", "android_device")
INTERVAL = int(cfg.get("PUSH_INTERVAL", 15))
TOP_N_PROCESSES = int(cfg.get("TOP_N_PROCESSES", 5))
# ---------------------------------------

registry = CollectorRegistry()

# ---------------- METRICS ----------------
# CPU
cpu_percent = Gauge("android_cpu_usage_percent", "Total CPU usage percent", registry=registry)
cpu_per_core = Gauge("android_cpu_core_percent", "CPU usage per core", ["core"], registry=registry)
cpu_count = Gauge("android_cpu_count", "Number of CPU cores", registry=registry)
load_avg_1 = Gauge("android_loadavg_1", "1-minute load average", registry=registry)
load_avg_5 = Gauge("android_loadavg_5", "5-minute load average", registry=registry)
load_avg_15 = Gauge("android_loadavg_15", "15-minute load average", registry=registry)

# Memory
memory_total = Gauge("android_memory_total_mb", "Total memory MB", registry=registry)
memory_available = Gauge("android_memory_available_mb", "Available memory MB", registry=registry)
memory_used = Gauge("android_memory_used_mb", "Used memory MB", registry=registry)
swap_total = Gauge("android_swap_total_mb", "Swap total MB", registry=registry)
swap_used = Gauge("android_swap_used_mb", "Swap used MB", registry=registry)

# Storage
storage_total = Gauge("android_storage_total_gb", "Total storage GB", registry=registry)
storage_free = Gauge("android_storage_free_gb", "Free storage GB", registry=registry)

# Battery
battery_percent = Gauge("android_battery_percent", "Battery percentage", registry=registry)
battery_plugged = Gauge("android_battery_plugged", "Battery charging status (1=charging,0=not)", registry=registry)

# Network
network_sent = Counter("android_network_bytes_sent_total", "Network bytes sent", registry=registry)
network_recv = Counter("android_network_bytes_recv_total", "Network bytes received", registry=registry)
network_errin = Counter("android_network_errin_total", "Network input errors", registry=registry)
network_errout = Counter("android_network_errout_total", "Network output errors", registry=registry)

# Processes
total_processes = Gauge("android_total_processes", "Total number of processes", registry=registry)
running_processes = Gauge("android_running_processes", "Number of running processes", registry=registry)

# Top processes
process_cpu = Gauge("android_process_cpu_percent", "CPU usage percent per process", ["pid", "name"], registry=registry)
process_mem = Gauge("android_process_memory_mb", "Memory usage MB per process", ["pid", "name"], registry=registry)

# Uptime
uptime = Counter("android_uptime_seconds_total", "Uptime seconds", registry=registry)

# ---------------- LAST VALUES ----------------
last_uptime = 0
last_sent = 0
last_recv = 0
last_errin = 0
last_errout = 0

# ---------------- UPDATE FUNCTIONS ----------------
def update_cpu():
    cpu_percent.set(psutil.cpu_percent(interval=None))
    cpu_count.set(psutil.cpu_count())
    per_core = psutil.cpu_percent(interval=None, percpu=True)
    for i, val in enumerate(per_core):
        cpu_per_core.labels(core=str(i)).set(val)
    if hasattr(os, "getloadavg"):
        la1, la5, la15 = os.getloadavg()
        load_avg_1.set(la1)
        load_avg_5.set(la5)
        load_avg_15.set(la15)

def update_memory():
    mem = psutil.virtual_memory()
    memory_total.set(mem.total/1024/1024)
    memory_available.set(mem.available/1024/1024)
    memory_used.set(mem.used/1024/1024)
    swap = psutil.swap_memory()
    swap_total.set(swap.total/1024/1024)
    swap_used.set(swap.used/1024/1024)

def update_storage():
    s = psutil.disk_usage('/')
    storage_total.set(s.total/1024/1024/1024)
    storage_free.set(s.free/1024/1024/1024)

def update_battery():
    if hasattr(psutil, "sensors_battery"):
        bat = psutil.sensors_battery()
        if bat:
            battery_percent.set(bat.percent)
            battery_plugged.set(1 if bat.power_plugged else 0)
        else:
            battery_percent.set(0)
            battery_plugged.set(0)

def update_network():
    global last_sent, last_recv, last_errin, last_errout
    net = psutil.net_io_counters()
    network_sent.inc(net.bytes_sent - last_sent if last_sent else net.bytes_sent)
    network_recv.inc(net.bytes_recv - last_recv if last_recv else net.bytes_recv)
    network_errin.inc(net.errin - last_errin if last_errin else net.errin)
    network_errout.inc(net.errout - last_errout if last_errout else net.errout)
    last_sent = net.bytes_sent
    last_recv = net.bytes_recv
    last_errin = net.errin
    last_errout = net.errout

def update_processes():
    total_processes.set(len(psutil.pids()))
    running = sum(1 for p in psutil.process_iter(attrs=['status']) if p.info['status'] == psutil.STATUS_RUNNING)
    running_processes.set(running)

def update_top_processes():
    # Top CPU processes
    top_cpu = sorted(psutil.process_iter(attrs=["pid","name","cpu_percent","memory_info"]),
                     key=lambda p: p.info["cpu_percent"], reverse=True)[:TOP_N_PROCESSES]
    for proc in top_cpu:
        try:
            pid = str(proc.info["pid"])
            name = proc.info["name"]
            cpu = proc.info["cpu_percent"]
            mem = proc.info["memory_info"].rss/1024/1024
            process_cpu.labels(pid=pid,name=name).set(cpu)
            process_mem.labels(pid=pid,name=name).set(mem)
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            continue

def update_uptime():
    global last_uptime
    up = time.time() - psutil.boot_time()
    uptime.inc(up - last_uptime if last_uptime else up)
    last_uptime = up

# ---------------- MAIN LOOP ----------------
print("📡 Android metric pusher started")
print(f"➡️ Pushgateway: {PUSHGATEWAY}")
print(f"⏱ Interval: {INTERVAL}s")

while True:
    update_cpu()
    update_memory()
    update_storage()
    update_battery()
    update_network()
    update_processes()
    update_top_processes()
    update_uptime()

    # Push metrics
    try:
        push_to_gateway(PUSHGATEWAY, job=JOB_NAME, registry=registry)
    except Exception as e:
        print(f"⚠️ Push failed: {e}")

    time.sleep(INTERVAL)
