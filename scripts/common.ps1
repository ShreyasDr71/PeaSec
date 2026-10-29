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

$P2PSecPorts = @(
    @{ Port = 7600; Name = "P2PSec node 7600" },
    @{ Port = 7606; Name = "P2PSec demo Tom 7606" }
)

function Test-FirewallReady {
    # A rule counts only if it lets the local network in on every network profile, so it also
    # works when Windows has marked the Wi-Fi as "Public" (the default for new networks).
    foreach ($p in $P2PSecPorts) {
        $rule = Get-NetFirewallRule -DisplayName $p.Name -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $rule -or $rule.Enabled -ne "True" -or "$($rule.Profile)" -ne "Any") { return $false }
        $scope = $rule | Get-NetFirewallAddressFilter
        if ("$($scope.RemoteAddress)" -ne "LocalSubnet") { return $false }
    }
    return $true
}

function Open-P2PSecFirewall {
    if (Test-FirewallReady) { Write-Host "Firewall: P2PSec ports are already open to your local network."; return }
    $cmds = foreach ($p in $P2PSecPorts) {
        "Remove-NetFirewallRule -DisplayName '$($p.Name)' -ErrorAction SilentlyContinue; " +
        "New-NetFirewallRule -DisplayName '$($p.Name)' -Direction Inbound -Protocol TCP -LocalPort $($p.Port) " +
        "-RemoteAddress LocalSubnet -Profile Any -Action Allow | Out-Null"
    }
    $script = $cmds -join "; "
    if (Test-Admin) {
        Invoke-Expression $script
    } else {
        Write-Host "Windows will ask once for permission to let devices on your Wi-Fi reach P2PSec"
        Write-Host "(TCP 7600 and 7606, local network only)."
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($script))
        try {
            $p = Start-Process powershell -Verb RunAs -Wait -PassThru -WindowStyle Hidden `
                 -ArgumentList "-NoProfile", "-EncodedCommand", $encoded
        } catch {
            Write-Warning "Permission was declined, so other devices cannot connect to this one yet."
            Write-Host  "  Run this script again and click Yes, or run it from an administrator PowerShell."
            return
        }
    }
    if (Test-FirewallReady) { Write-Host "Firewall: opened TCP 7600 and 7606 to devices on your local network." }
    else { Write-Warning "The firewall rules could not be created. Other devices may not be able to connect." }
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
