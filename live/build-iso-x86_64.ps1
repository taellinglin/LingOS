# Build the LingOS x86_64 kernels (text/Rescue + Install GUI+text + Live
# desktop/wm) natively on Windows, then package them into a bootable GRUB
# ISO via WSL (grub-mkrescue/xorriso only exist there). Run from anywhere;
# paths are resolved relative to this script.
$ErrorActionPreference = "Stop"

$LingOSRoot = Split-Path -Parent $PSScriptRoot
$LingExe = Join-Path $LingOSRoot "bin\ling.exe"
$Dist = Join-Path $LingOSRoot "dist"

if (-not (Test-Path $LingExe)) {
    $LingRoot = Join-Path (Split-Path -Parent $LingOSRoot) "ling"
    Write-Error "ling.exe not found at $LingExe`nBuild it first: cd '$LingRoot'; cargo build --release --bin ling; then copy target\release\ling.exe to $LingExe"
}

Write-Host "==> compiling LingOS x86_64 kernels (text/Rescue + Install GUI+text + Live desktop)"
& $LingExe build (Join-Path $LingOSRoot "kernel\x86_64") --platform kernel --out $Dist
& $LingExe build (Join-Path $LingOSRoot "kernel\x86_64-installer") --platform kernel --out $Dist
& $LingExe build (Join-Path $LingOSRoot "kernel\x86_64-installer-gui") --platform kernel --out $Dist
& $LingExe build (Join-Path $LingOSRoot "kernel\x86_64-wm") --platform kernel --out $Dist

Write-Host "==> packaging GRUB ISO (WSL)"
$wslLingOS = (wsl.exe wslpath -a "$LingOSRoot").Trim()
wsl.exe bash "$wslLingOS/live/build-iso-x86_64.sh"
