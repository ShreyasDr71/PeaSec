# Wipe EVERYTHING on this device: your vault, keys, pairings, logs and the demo team.
# Afterwards the node starts fresh with the default sign-in user / user.
#   powershell -ExecutionPolicy Bypass -File scripts\reset-all.ps1
. "$PSScriptRoot\common.ps1"
Assert-Docker
$answer = Read-Host "This permanently deletes your vault, keys and pairings on this device. Type DELETE to continue"
if ($answer -ne "DELETE") { Write-Host "Cancelled."; exit 1 }
docker compose down -v
docker compose up -d
Write-Host "Done. Sign in at http://127.0.0.1:8000 as user / user."
