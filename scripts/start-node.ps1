# Device B: start one fresh, real (non-demo) node that teammates on the same Wi-Fi can reach.
#   powershell -ExecutionPolicy Bypass -File scripts\start-node.ps1 [-LanIp 192.168.1.20]
param([string]$LanIp = "")
. "$PSScriptRoot\common.ps1"
Assert-Docker

if (-not $LanIp) { $LanIp = Get-LanIp }
Set-EnvValue "LAN_IP" $LanIp
Open-FirewallPort 7600 "P2PSec node 7600"

docker compose -f docker-compose.lan.yml up -d --build
if ($LASTEXITCODE -ne 0) { throw "docker compose failed." }
Write-Host "Waiting for the node to start..."
Wait-Healthy @("http://127.0.0.1:8000/api/status")

Write-Host ""
Write-Host "Your node is running: open http://127.0.0.1:8000 and create your vault." -ForegroundColor Green
Write-Host "Teammates pair with you at:  ${LanIp}:7600"
Write-Host "To pair with the demo team, enter Tom's address shown on the other device (its-IP:7606)."
