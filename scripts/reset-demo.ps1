# Reset demo data back to the original seed.
#   powershell -ExecutionPolicy Bypass -File scripts\reset-demo.ps1            # whole team
#   powershell -ExecutionPolicy Bypass -File scripts\reset-demo.ps1 -Node tom  # one person only
#   powershell -ExecutionPolicy Bypass -File scripts\reset-demo.ps1 -Standalone # the device-B node (deletes its vault!)
param([string]$Node = "", [switch]$Standalone)
. "$PSScriptRoot\common.ps1"
Assert-Docker

if ($Standalone) {
    $answer = Read-Host "This deletes the standalone node's vault, keys and pairings for good. Type DELETE to continue"
    if ($answer -ne "DELETE") { Write-Host "Cancelled."; exit 1 }
    docker compose -f docker-compose.lan.yml down -v
    Write-Host "Standalone node removed. Start it again with scripts\start-node.ps1"
    exit 0
}

if ($Node) {
    $valid = "priya", "marcus", "elena", "jamal", "sofia", "tom"
    if ($valid -notcontains $Node) { throw "Unknown person '$Node'. Use one of: $($valid -join ', ')" }
    docker compose rm --stop --force $Node
    docker volume rm "p2psec_$Node"
    docker compose up -d $Node
    Write-Host "$Node was reset to the seed. Note: other people still remember their history with $Node."
} else {
    docker compose down -v
    docker compose up -d
    Write-Host "All six demo nodes were reset to the original seed."
}
