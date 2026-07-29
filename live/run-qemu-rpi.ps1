# Boot the LingOS Raspberry Pi kernel in QEMU's raspi3b machine (via WSL —
# qemu-system-aarch64 only exists there).
$ErrorActionPreference = "Stop"
$LingOSRoot = Split-Path -Parent $PSScriptRoot
$wslLingOS = (wsl.exe wslpath -a "$LingOSRoot").Trim()
wsl.exe bash "$wslLingOS/live/run-qemu-rpi.sh"
