#!/usr/bin/env python3
"""
Android Prometheus Exporter
Monitors CPU, Memory, Storage metrics
"""

import time
import os
import socket
import sys
from prometheus_client import start_http_server, Gauge, Counter

# Metrics
cpu_percent = Gauge('android_cpu_usage_percent', 'CPU usage percentage')
memory_total = Gauge('android_memory_total_mb', 'Total memory in MB')
memory_available = Gauge('android_memory_available_mb', 'Available memory in MB')
memory_used = Gauge('android_memory_used_mb', 'Used memory in MB')
uptime_seconds = Counter('android_uptime_seconds', 'System uptime in seconds')
storage_total_gb = Gauge('android_storage_total_gb', 'Total storage in GB')
storage_free_gb = Gauge('android_storage_free_gb', 'Free storage in GB')

def get_cpu_usage():
    try:
        with open('/proc/stat', 'r') as f:
            lines = f.readlines()
        for line in lines:
            if line.startswith('cpu '):
                parts = list(map(int, line.split()[1:]))
                total = sum(parts)
                idle = parts[3]
                usage = 100.0 * (total - idle) / total if total > 0 else 0
                return round(usage, 2)
    except:
        return 0

def get_memory_info():
    try:
        mem_data = {}
        with open('/proc/meminfo', 'r') as f:
            for line in f:
                if ':' in line:
                    key, value = line.split(':', 1)
                    mem_data[key.strip()] = value.strip().split()[0]
        
        total_kb = int(mem_data.get('MemTotal', 0))
        available_kb = int(mem_data.get('MemAvailable', 0))
        
        total_mb = total_kb / 1024
        available_mb = available_kb / 1024
        used_mb = total_mb - available_mb
        
        return round(total_mb, 2), round(available_mb, 2), round(used_mb, 2)
    except:
        return 0, 0, 0

def get_storage_info():
    try:
        stat = os.statvfs('/data')
        block_size = stat.f_frsize
        total_blocks = stat.f_blocks
        free_blocks = stat.f_bfree
        
        total_gb = (total_blocks * block_size) / (1024**3)
        free_gb = (free_blocks * block_size) / (1024**3)
        
        return round(total_gb, 2), round(free_gb, 2)
    except:
        return 0, 0

def get_uptime():
    try:
        with open('/proc/uptime', 'r') as f:
            uptime_sec = float(f.readline().split()[0])
        return uptime_sec
    except:
        return 0

def get_ip_address():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(('8.8.8.8', 53))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except:
        return 'unknown'

def main():
    device_ip = get_ip_address()
    hostname = os.uname().nodename
    
    print("\n" + "="*60)
    print("📱 ANDROID PROMETHEUS EXPORTER")
    print("="*60)
    print(f"Device IP:    {device_ip}")
    print(f"Hostname:     {hostname}")
    print(f"Metrics Port: 9100")
    print(f"SSH Port:     8022")
    print("="*60)
    print(f"Metrics: http://{device_ip}:9100/metrics")
    print("="*60 + "\n")
    
    try:
        start_http_server(9100, addr='0.0.0.0')
        print("✅ Exporter started!")
    except Exception as e:
        print(f"❌ Failed: {e}")
        sys.exit(1)
    
    print("📊 Collecting metrics every 15 seconds...")
    print("🛑 Press Ctrl+C to stop\n")
    
    last_uptime = 0
    try:
        while True:
            cpu = get_cpu_usage()
            mem_total, mem_avail, mem_used = get_memory_info()
            storage_total, storage_free = get_storage_info()
            current_uptime = get_uptime()
            
            cpu_percent.set(cpu)
            memory_total.set(mem_total)
            memory_available.set(mem_avail)
            memory_used.set(mem_used)
            storage_total_gb.set(storage_total)
            storage_free_gb.set(storage_free)
            
            uptime_delta = current_uptime - last_uptime if last_uptime > 0 else current_uptime
            uptime_seconds.inc(uptime_delta)
            last_uptime = current_uptime
            
            time.sleep(15)
            
    except KeyboardInterrupt:
        print("\n👋 Exporter stopped")
    except Exception as e:
        print(f"\n💥 Error: {e}")

if __name__ == '__main__':
    main()
