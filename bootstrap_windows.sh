#!/usr/bin/env bash
#
# Windows/WSL bootstrap — run from inside WSL
# Sources the main bootstrap.sh for helper functions (pwsh, win, logging, etc.)
#
# NOTE: Run your Windows Terminal as Administrator for the Windows
#       settings section (power, registry, bloatware removal) to work.
#

DOTS_DIR="$HOME/dots/"
source "$DOTS_DIR/bootstrap.sh"

if ! is_wsl; then
  _fail_error "This script must be run from inside WSL"
fi

# Windows/WSL helper functions
function pwsh {
  powershell.exe -NoProfile -Command "$@" 2>/dev/null | tr -d '\r'
}

function win {
  "$@" 2>/dev/null | tr -d '\r'
}

#    _       ___         __                   ___
#   | |     / (_)___    / /___ _      _______/   |  ____  ____  _____
#   | | /| / / / __ \  / / __ \ | /| / / ___/ /| | / __ \/ __ \/ ___/
#   | |/ |/ / / / / / / / /_/ / |/ |/ (__  ) ___ |/ /_/ / /_/ (__  )
#   |__/|__/_/_/ /_/ /_/\____/|__/|__/____/_/  |_/ .___/ .___/____/
#                                                /_/   /_/

WINDOWS_APPS=(
  "Google.Chrome"
  "Discord.Discord"
  "Spotify.Spotify"
  "Valve.Steam"
  "Microsoft.VisualStudioCode"
  "Git.Git"
  "7zip.7zip"
  "VideoLAN.VLC"
  "Microsoft.DotNet.SDK.9"
  "Microsoft.PowerShell"
  "Python.Python.3.12"
  "UnityTechnologies.UnityHub"
  "BlenderFoundation.Blender"
  "Docker.DockerDesktop"
  "LizardByte.Sunshine"
  "EpicGames.EpicGamesLauncher"
  "GOG.Galaxy"
  "Krita.Krita"
  "RandyRants.SharpKeys"
)

function _winget_install {
  local id="$1"
  if win winget.exe list --exact --id "$id" >/dev/null 2>&1; then
    _log_btw "Already installed: ${color_blue}$id${color_reset}. Skipping!"
  else
    _log_info "Installing ${color_blue}$id"
    win winget.exe install --id "$id" --silent --accept-package-agreements --accept-source-agreements
  fi
}

for app in "${WINDOWS_APPS[@]}"; do
  _winget_install "$app"
done

#   _       ___           __                  _____      __  __  _
#  | |     / (_)___  ____/ /___ _      _____ / ___/___  / /_/ /_(_)___  ____ ______
#  | | /| / / / __ \/ __  / __ \ | /| / / __|__ \/ _ \/ __/ __/ / __ \/ __ `/ ___/
#  | |/ |/ / / / / / /_/ / /_/ / |/ |/ (__  ) _/ /  __/ /_/ /_/ / / / / /_/ (__  )
#  |__/|__/_/_/ /_/\__,_/\____/|__/|__/____/____/\___/\__/\__/_/_/ /_/\__, /____/
#                                                                     /____/

# Power: high performance, no sleep, no hibernate
_log_info "Setting ${color_blue}High Performance${color_reset} power plan"
pwsh "powercfg /setactive SCHEME_MIN"
pwsh "powercfg /change standby-timeout-ac 0"
pwsh "powercfg /hibernate off"

# Disable telemetry
_log_info "Disabling ${color_blue}telemetry"
pwsh 'reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection" /v AllowTelemetry /t REG_DWORD /d 0 /f'

# Disable suggestions and ads
_log_info "Disabling ${color_blue}suggestions and ads"
pwsh 'reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v SystemPaneSuggestionsEnabled /t REG_DWORD /d 0 /f'

# Disable auto-reboot when logged in
_log_info "Disabling ${color_blue}auto-reboot with logged on users"
pwsh 'reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v NoAutoRebootWithLoggedOnUsers /t REG_DWORD /d 1 /f'

# Disable OneDrive autostart
_log_info "Disabling ${color_blue}OneDrive${color_reset} autostart"
pwsh 'reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v OneDrive /f'


# Remove bloatware
_log_info "Removing ${color_blue}Windows bloatware"
BLOATWARE_PATTERNS=("xbox" "bing" "skype")
for pattern in "${BLOATWARE_PATTERNS[@]}"; do
  _log_info "Removing ${color_blue}*${pattern}*"
  pwsh "Get-AppxPackage *${pattern}* | Remove-AppxPackage"
done

# Forward ports from Windows to WSL so that services running in WSL
# (e.g. ollama on 11434/11435, dev servers on 5000/8000) are reachable
# from the Windows host and LAN. WSL's IP changes on each boot, so this:
#   1. Writes a PowerShell script to %USERPROFILE%\scripts\ that resolves
#      the current WSL IP and runs netsh portproxy for each port
#   2. Runs it immediately
#   3. Registers a Windows Scheduled Task to re-run it at every logon
#   4. Opens the ports in Windows Firewall
function setup_wsl_port_forwarding {
  local ports="22, 2022, 5000, 8000, 11434, 11435, 25000, 25001, 25002, 25003, 25004, 25005, 25006, 25007, 25008, 25009, 25010"

  _log_info "Setting up ${color_blue}WSL port forwarding"

  # Write the forwarding script to the Windows filesystem
  local win_userprofile=$(win cmd.exe /C "echo %USERPROFILE%")
  local win_script_dir="${win_userprofile}\\scripts"
  local win_script_path="${win_script_dir}\\wsl-port-forward.ps1"
  local linux_script_dir=$(wslpath "$win_userprofile")/scripts
  mkdir -p "$linux_script_dir"

  cat > "$linux_script_dir/wsl-port-forward.ps1" << PSEOF
\$wslIp = (wsl.exe hostname -I).Trim().Split(' ')[0]
if (-not \$wslIp) { Write-Error "WSL not running"; exit 1 }

\$ports = @(${ports})

foreach (\$p in \$ports) {
    netsh interface portproxy delete v4tov4 listenport=\$p listenaddress=0.0.0.0 2>\$null
    netsh interface portproxy add v4tov4 listenport=\$p listenaddress=0.0.0.0 connectport=\$p connectaddress=\$wslIp
}

# Ensure firewall rules exist
foreach (\$p in \$ports) {
    if (-not (Get-NetFirewallRule -DisplayName "WSL Port \$p" -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName "WSL Port \$p" -Direction Inbound -Protocol TCP -LocalPort \$p -Action Allow
    }
}

Write-Host "Forwarding ports: \$ports -> \$wslIp"
PSEOF

  _log_info "Wrote port-forward script to ${color_blue}${win_script_path}"

  # Run it now (needs admin for netsh, so self-elevate)
  _log_info "Running port forwarding now"
  pwsh "Start-Process powershell -Verb RunAs -Wait -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File \"${win_script_path}\"'"

  # Register as a Scheduled Task that runs at startup with highest privileges
  _log_info "Registering ${color_blue}WSL Port Forward${color_reset} scheduled task"
  pwsh "
\$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NoProfile -ExecutionPolicy Bypass -File \"${win_script_path}\"'
\$trigger = New-ScheduledTaskTrigger -AtStartup
\$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
\$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -RunLevel Highest
Unregister-ScheduledTask -TaskName 'WSL Port Forward' -Confirm:\$false -ErrorAction SilentlyContinue
Register-ScheduledTask -TaskName 'WSL Port Forward' -Action \$action -Trigger \$trigger -Settings \$settings -Principal \$principal -Description 'Forward ports from Windows to WSL at startup'
"
}
setup_wsl_port_forwarding

#    _   ___      ___  _____
#   / | / / | /| / / |/ /   |
#  /  |/ /| |/ |/ /|   / /| |
# / /|  / |__/|__//   / ___ |
#/_/ |_/         /_/|_/_/  |_|

_winget_install "Nvidia.GeForceExperience"

if dpkg -s nvidia-cuda-toolkit >/dev/null 2>&1; then
  _log_btw "Already installed: ${color_blue}nvidia-cuda-toolkit${color_reset}. Skipping!"
else
  _log_info "Installing ${color_blue}nvidia-cuda-toolkit${color_reset} in WSL"
  sudo apt-get install nvidia-cuda-toolkit -y
fi

#   _       _______ __     ___
#  | |     / / ___// /    /   |  ____  ____  _____
#  | | /| / /\__ \/ /    / /| | / __ \/ __ \/ ___/
#  | |/ |/ /___/ / /___ / ___ |/ /_/ / /_/ (__  )
#  |__/|__//____/_____//_/  |_/ .___/ .___/____/
#                             /_/   /_/

if ! command -v sshd >/dev/null 2>&1; then
  _log_info "Installing ${color_blue}openssh-server"
  sudo apt-get update
  sudo apt-get install openssh-server -y
else
  _log_btw "Already installed: ${color_blue}openssh-server${color_reset}. Skipping!"
fi
if ! systemctl is-active --quiet ssh; then
  _log_info "Enabling ${color_blue}sshd"
  sudo systemctl enable ssh
  sudo systemctl start ssh
else
  _log_btw "Already running: ${color_blue}sshd${color_reset}. Skipping!"
fi

# Ollama runs as a systemd service; its service config lives at
# /etc/systemd/system/ollama.service and app config at ~/.ollama/
# After editing the service file, run:
#   sudo systemctl daemon-reload
#   sudo systemctl restart ollama
function setup_ollama {
  if ! command -v ollama >/dev/null 2>&1; then
    _log_info "Installing ${color_blue}ollama"
    curl -fsSL https://ollama.com/install.sh | sh
  else
    _log_btw "Already installed: ${color_blue}ollama${color_reset}. Skipping!"
  fi

}
setup_ollama

nanoclaw_path="$HOME/nanoclaw"
if [[ -d "$nanoclaw_path" ]]; then
  _log_btw "Already cloned: ${color_blue}nanoclaw${color_reset}. Skipping!"
else
  _log_info "Cloning ${color_blue}NanoClaw"
  git clone https://github.com/gavrielc/nanoclaw.git "$nanoclaw_path"
fi
_log_warn "To set up NanoClaw, run: ${color_blue}cd ~/nanoclaw && claude"

if ! command -v gh >/dev/null 2>&1; then
  _log_info "Installing ${color_blue}GitHub CLI"
  sudo mkdir -p /etc/apt/keyrings
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null
  sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
  sudo apt-get update
  sudo apt-get install gh -y
else
  _log_btw "Already installed: ${color_blue}gh${color_reset}. Skipping!"
fi

if [ -s "$HOME/.nvm/nvm.sh" ]; then
  _log_btw "Already installed: ${color_blue}nvm${color_reset}. Skipping!"
  source ~/.nvm/nvm.sh
else
  _log_info "Installing ${color_blue}nvm"
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/master/install.sh | bash
  source ~/.nvm/nvm.sh
fi

if ! command -v node >/dev/null 2>&1; then
  _log_info "Installing ${color_blue}Node.js${color_reset} LTS via nvm"
  nvm install --lts
else
  _log_btw "Already installed: ${color_blue}node${color_reset}. Skipping!"
fi

_log_btw "Enabling ${color_blue}corepack${color_reset} and activating ${color_blue}pnpm"
corepack enable
corepack prepare pnpm@latest --activate

_log_info "Windows bootstrap complete! 🎉 "
