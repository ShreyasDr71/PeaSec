# Shared helpers for the P2PSec start/reset scripts (Windows PowerShell 5+ or PowerShell 7).

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

function Get-LanIp {
    $cfg = Get-NetIPConfiguration |
        Where-Object { $_.IPv4DefaultGateway -ne $null -and $_.NetAdapter.Status -eq "Up" } |
        Select-Object -First 1
    if (-not $cfg) { throw "No connected network adapter found. Join the Wi-Fi, or pass -LanIp <address>." }
    return $cfg.IPv4Address.IPAddress
}

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Open-FirewallPort([int]$Port, [string]$Name) {
    if (Get-NetFirewallRule -DisplayName $Name -ErrorAction SilentlyContinue) {
        Write-Host "Firewall: rule '$Name' already exists."
        return
    }
    if (Test-Admin) {
        New-NetFirewallRule -DisplayName $Name -Direction Inbound -Protocol TCP -LocalPort $Port -Action Allow -Profile Private,Domain | Out-Null
        Write-Host "Firewall: opened TCP $Port for devices on this network."
    } else {
        Write-Warning "Not running as administrator, so the firewall was not changed. Other devices may be blocked."
        Write-Host  "  Fix: in an administrator PowerShell, run:"
        Write-Host  "  New-NetFirewallRule -DisplayName '$Name' -Direction Inbound -Protocol TCP -LocalPort $Port -Action Allow -Profile Private,Domain"
    }
}

function Set-EnvValue([string]$Key, [string]$Value) {
    # docker compose reads .env from the project folder, so plain "docker compose up" keeps working later
    $path = Join-Path $Root ".env"
    $lines = @()
    if (Test-Path $path) { $lines = Get-Content $path | Where-Object { $_ -notmatch "^$Key=" } }
    $lines += "$Key=$Value"
    Set-Content -Path $path -Value $lines -Encoding ascii
}

function Wait-Healthy([string[]]$Urls) {
    foreach ($u in $Urls) {
        for ($i = 0; $i -lt 90; $i++) {
            try { Invoke-RestMethod -Uri $u -TimeoutSec 2 | Out-Null; break } catch { Start-Sleep -Seconds 1 }
        }
    }
}

function Assert-Docker {
    docker info --format "{{.ServerVersion}}" *> $null
    if ($LASTEXITCODE -ne 0) { throw "Docker is not running. Start Docker Desktop and try again." }
}
