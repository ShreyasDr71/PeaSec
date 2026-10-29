# Start P2PSec on this device (Windows). Run the same script on every device on the Wi-Fi.
#   powershell -ExecutionPolicy Bypass -File scripts\start.ps1 [-LanIp 192.168.1.10]
# Run PowerShell as administrator once so the firewall ports can be opened.
param([string]$LanIp = "")
. "$PSScriptRoot\common.ps1"
Assert-Docker

if (-not $LanIp) { $LanIp = Get-LanIp }
Set-EnvValue "LAN_IP" $LanIp
Open-FirewallPort 7600 "P2PSec node 7600"
Open-FirewallPort 7606 "P2PSec demo Tom 7606"

docker compose up -d --build
if ($LASTEXITCODE -ne 0) { throw "docker compose failed." }
Write-Host "Waiting for P2PSec to start..."
Wait-Healthy @("http://127.0.0.1:8000/api/status")

Write-Host ""
Write-Host "P2PSec is running: http://127.0.0.1:8000" -ForegroundColor Green
Write-Host "  First sign-in: username 'user', password 'user' (change both in Node settings)."
Write-Host "  Teammates on this Wi-Fi pair with you at:  ${LanIp}:7600"
Write-Host "  Demo mode (sign-in page) starts a seeded team; other devices can pair with its Tom at ${LanIp}:7606"
