# Boot the LingOS x86_64 live ISO in QEMU (via WSL — qemu-system-x86_64
# only exists there).
$ErrorActionPreference = "Stop"
$LingOSRoot = Split-Path -Parent $PSScriptRoot
$wslLingOS = (wsl.exe wslpath -a "$LingOSRoot").Trim()
wsl.exe bash "$wslLingOS/live/run-qemu-x86_64.sh"
