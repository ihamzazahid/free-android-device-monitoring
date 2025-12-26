# Windows Setup for Android Monitoring

Write-Host "💻 Windows Setup for Android Monitoring" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Create directory
$monitorDir = "$env:USERPROFILE\AndroidMonitoring"
New-Item -ItemType Directory -Path $monitorDir -Force | Out-Null

# Create tunnel script
$tunnelScript = @'
# Start SSH Tunnel
param([string]$AndroidIP = "192.168.1.100")

Write-Host "Starting tunnel to: $AndroidIP" -ForegroundColor Yellow
Write-Host "Port 19100 → 9100" -ForegroundColor Yellow
Write-Host ""

ssh -N -L 19100:localhost:9100 termux@$AndroidIP -p 8022
'@

$tunnelScript | Out-File -FilePath "$monitorDir\Start-Tunnel.ps1" -Encoding UTF8

# Create monitor script
$monitorScript = @'
# Android Device Monitor
while ($true) {
    Clear-Host
    Write-Host "📱 ANDROID DEVICE MONITOR" -ForegroundColor Cyan
    Write-Host "=========================" -ForegroundColor Cyan
    Write-Host ""
    
    try {
        $metrics = Invoke-WebRequest -Uri "http://localhost:19100/metrics" -TimeoutSec 3
        $lines = $metrics.Content -split "`n"
        
        foreach ($line in $lines) {
            if ($line -match 'android_') {
                Write-Host $line -ForegroundColor Green
            }
        }
    } catch {
        Write-Host "❌ Cannot connect to device" -ForegroundColor Red
        Write-Host "Start tunnel first: .\Start-Tunnel.ps1" -ForegroundColor Yellow
    }
    
    Write-Host ""
    Write-Host "🔄 Refreshing in 10 seconds (Ctrl+C to exit)" -ForegroundColor Gray
    Start-Sleep -Seconds 10
}
'@

$monitorScript | Out-File -FilePath "$monitorDir\Monitor-Device.ps1" -Encoding UTF8

# Batch file
$batchFile = @'
@echo off
echo Android Device Monitor
echo =====================
powershell -ExecutionPolicy Bypass -File "Monitor-Device.ps1"
pause
'@

$batchFile | Out-File -FilePath "$monitorDir\Monitor.bat" -Encoding ASCII

Write-Host ""
Write-Host "✅ Setup complete!" -ForegroundColor Green
Write-Host "Files created in: $monitorDir" -ForegroundColor Yellow
Write-Host ""
Write-Host "📋 Next:"
Write-Host "1. Edit Start-Tunnel.ps1 with your Android IP"
Write-Host "2. Run Monitor.bat to start monitoring"
Write-Host "3. Start tunnel when prompted"
