$wslIp = (wsl.exe hostname -I).Trim().Split(' ')[0]
if (-not $wslIp) { Write-Error "WSL not running"; exit 1 }

$ports = @(22, 2022, 5000, 8000, 11434, 11435, 25000, 25001, 25002, 25003, 25004, 25005, 25006, 25007, 25008, 25009, 25010)

foreach ($p in $ports) {
    netsh interface portproxy delete v4tov4 listenport=$p listenaddress=0.0.0.0 2>$null
    netsh interface portproxy add v4tov4 listenport=$p listenaddress=0.0.0.0 connectport=$p connectaddress=$wslIp
}

# Ensure firewall rules exist
foreach ($p in $ports) {
    if (-not (Get-NetFirewallRule -DisplayName "WSL Port $p" -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName "WSL Port $p" -Direction Inbound -Protocol TCP -LocalPort $p -Action Allow
    }
}

Write-Host "Forwarding ports: $ports -> $wslIp"
