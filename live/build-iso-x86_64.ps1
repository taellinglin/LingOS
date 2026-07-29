# Build the LingOS x86_64 kernels (Live + Install) natively on Windows,
# then package them into a bootable GRUB ISO via WSL (grub-mkrescue/xorriso
# only exist there). Run from anywhere; paths are resolved relative to
# this script.
$ErrorActionPreference = "Stop"

$LingOSRoot = Split-Path -Parent $PSScriptRoot
$LingRoot = Join-Path (Split-Path -Parent $LingOSRoot) "ling"
$LingExe = Join-Path $LingRoot "target\release\ling.exe"
$Dist = Join-Path $LingOSRoot "dist"

if (-not (Test-Path $LingExe)) {
    Write-Error "ling.exe not found at $LingExe`nBuild it first: cd '$LingRoot'; cargo build --release --bin ling"
}

Write-Host "==> compiling LingOS x86_64 kernels (Live + Install)"
& $LingExe build (Join-Path $LingOSRoot "kernel\x86_64") --platform kernel --out $Dist
& $LingExe build (Join-Path $LingOSRoot "kernel\x86_64-installer") --platform kernel --out $Dist

Write-Host "==> packaging GRUB ISO (WSL)"
$wslLingOS = (wsl.exe wslpath -a "$LingOSRoot").Trim()
wsl.exe bash "$wslLingOS/live/build-iso-x86_64.sh"
