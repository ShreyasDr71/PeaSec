# Device A: start the six-person demo team and let other devices on the Wi-Fi pair with Tom.
#   powershell -ExecutionPolicy Bypass -File scripts\start-team.ps1 [-LanIp 192.168.1.10]
param([string]$LanIp = "")
. "$PSScriptRoot\common.ps1"
Assert-Docker

if (-not $LanIp) { $LanIp = Get-LanIp }
Set-EnvValue "TOM_ADVERTISE" "${LanIp}:7606"
Open-FirewallPort 7606 "P2PSec demo (Tom) 7606"

docker compose up -d --build
if ($LASTEXITCODE -ne 0) { throw "docker compose failed." }
Write-Host "Waiting for the nodes to start..."
Wait-Healthy (8001..8006 | ForEach-Object { "http://127.0.0.1:$_/api/status" })

Write-Host ""
Write-Host "P2PSec demo team is running. Master password for everyone: p2psec-demo"
Write-Host "  Priya  http://127.0.0.1:8001    Marcus http://127.0.0.1:8002    Elena http://127.0.0.1:8003"
Write-Host "  Jamal  http://127.0.0.1:8004    Sofia  http://127.0.0.1:8005    Tom   http://127.0.0.1:8006"
Write-Host ""
Write-Host "From the other device, pair with Tom at:  ${LanIp}:7606" -ForegroundColor Green
